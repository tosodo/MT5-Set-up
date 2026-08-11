//+------------------------------------------------------------------+
//|                                                     AgenticEA.mq5 |
//|      Deterministic execution engine — the EA is the ownable IP.   |
//|      Claude/MCP orchestrates and monitors; this EA decides trades.|
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "1.20"
#property strict

#include <RuleGuards.mqh>

input double InpMaxDailyLossPct   = 4.0;    // fill from rule-map-template.md
input double InpMaxDrawdownPct    = 8.0;    // fill from rule-map-template.md
input int    InpEntryOffsetMs     = 150;    // entry-time-offset concept, from lessons log
input double InpATRMultiplier     = 2.0;    // ATR trailing stop multiplier
input double InpMaxSpreadPoints   = 60;     // spread-limit gate — see note below
input int    InpATRPeriod         = 14;     // ATR period for the trailing stop
input double InpRiskPctPerTrade   = 1.0;    // max % of equity risked on one trade

// NOTE ON InpMaxSpreadPoints: this is per-instrument, not a universal number.
// It was 30 as a placeholder, which measurement showed was unusable: on
// XAUUSD.s at PU Prime, 60 samples over 15s in the thin overnight session ran
// 31-36 points, so a 30-point gate blocked 100% of ticks. See
// docs/broker-puprime-demo-2026-08-11.md. The gate exists to refuse trading
// through a dislocation (news spike, rollover), not to shave execution cost —
// so it belongs well above normal spread, not next to it.

int                     g_atrHandle   = INVALID_HANDLE;
ENUM_ORDER_TYPE_FILLING g_fillingMode = ORDER_FILLING_IOC;
double                  g_minLot      = 0.0;
long                    g_stopsLevel  = 0;

//+------------------------------------------------------------------+
//| Pick a filling mode the broker actually accepts.                  |
//| Getting this wrong is a silent killer: the EA looks healthy and   |
//| every order comes back "Unsupported filling mode". PU Prime       |
//| advertises IOC only — a hardcoded FOK would have failed there.    |
//+------------------------------------------------------------------+
bool ResolveFillingMode(string sym, ENUM_ORDER_TYPE_FILLING &mode)
{
   long flags = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);

   if((flags & SYMBOL_FILLING_IOC) != 0) { mode = ORDER_FILLING_IOC; return true; }
   if((flags & SYMBOL_FILLING_FOK) != 0) { mode = ORDER_FILLING_FOK; return true; }

   // Nothing advertised. RETURN is valid under market/exchange execution;
   // under instant/request execution it is not, and we should not guess.
   ENUM_SYMBOL_TRADE_EXECUTION exe =
      (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(sym, SYMBOL_TRADE_EXEMODE);

   if(exe == SYMBOL_TRADE_EXECUTION_MARKET || exe == SYMBOL_TRADE_EXECUTION_EXCHANGE)
   {
      mode = ORDER_FILLING_RETURN;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Read the symbol's trading conditions and refuse to start if the   |
//| account cannot actually trade it. Fail-closed: better to not load |
//| than to load and discover it at the first order.                  |
//+------------------------------------------------------------------+
bool ValidateSymbol(string sym)
{
   ENUM_SYMBOL_TRADE_MODE tradeMode =
      (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);

   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("AgenticEA: ", sym, " is not tradable on this account. Refusing to start.");
      return false;
   }
   if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      Print("AgenticEA: WARNING — ", sym, " is restricted (mode ", (int)tradeMode,
            "). Entries may be rejected; this is normal outside market hours.");

   if(!ResolveFillingMode(sym, g_fillingMode))
   {
      Print("AgenticEA: no order filling mode this broker accepts for ", sym,
            ". Refusing to start.");
      return false;
   }

   g_minLot     = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   g_stopsLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);

   // Can this account even afford one minimum-size position?
   double margin = 0.0;
   double ask    = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, g_minLot, ask, margin))
   {
      Print("AgenticEA: could not calculate margin for ", sym, ", error ", GetLastError(),
            ". Refusing to start.");
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin > freeMargin)
   {
      Print("AgenticEA: minimum position (", DoubleToString(g_minLot, 2), " lot) needs ",
            DoubleToString(margin, 2), " margin but only ", DoubleToString(freeMargin, 2),
            " is free. Refusing to start.");
      return false;
   }

   Print("AgenticEA: ", sym, " OK — min lot ", DoubleToString(g_minLot, 2),
         ", margin ", DoubleToString(margin, 2),
         ", stops level ", g_stopsLevel, " points, filling ", EnumToString(g_fillingMode));
   return true;
}

//+------------------------------------------------------------------+
//| Log the sizing envelope: the money at stake, and the range of     |
//| stop distances this account can actually trade. Both ends matter. |
//| Too tight a stop and the minimum lot risks more than allowed; too |
//| wide and the position cannot be made small enough to fit.         |
//+------------------------------------------------------------------+
void ReportSizingEnvelope()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double budget = equity * InpRiskPctPerTrade / 100.0;
   string ccy    = AccountInfoString(ACCOUNT_CURRENCY);

   Print("AgenticEA: risking at most ", DoubleToString(InpRiskPctPerTrade, 2), "% of ",
         DoubleToString(equity, 2), " ", ccy, " = ", DoubleToString(budget, 2), " ", ccy,
         " per trade.");

   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(point <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0 || g_minLot <= 0.0)
      return;

   // Loss of one point at the smallest position the broker will accept.
   double perPointMinLot = g_minLot * point / tickSize * tickValue;
   if(perPointMinLot <= 0.0) return;

   double widestStop = budget / perPointMinLot;
   Print("AgenticEA: at the minimum ", DoubleToString(g_minLot, 2), " lot that budget covers a stop of ",
         DoubleToString(widestStop, 0), " points. Wider than that and the trade is skipped —",
         " the position cannot be made any smaller.");

   if(widestStop < (double)g_stopsLevel)
      Print("AgenticEA: WARNING — that is narrower than the broker's own ", g_stopsLevel,
            "-point minimum stop. No trade can satisfy both. Lower the risk %, or fund more.");
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(!ValidateSymbol(_Symbol))
      return(INIT_FAILED);

   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("AgenticEA: failed to create ATR handle on ", _Symbol);
      return(INIT_FAILED);
   }

   // Captures the daily/high-water baselines the risk guards measure against.
   // Until this runs, every guard blocks trading by design.
   RuleGuards::Init();

   // Print the sizing envelope once, so the journal records what this EA was
   // actually permitted to do — not what someone assumed it was permitted to do.
   ReportSizingEnvelope();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("AgenticEA: loaded, but Algo Trading is OFF — no order can be sent.");

   // TODO: load ONNX model here if the entry signal ends up model-driven

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!RuleGuards::DailyLossOK(InpMaxDailyLossPct))  return; // hard stop, no override
   if(!RuleGuards::DrawdownOK(InpMaxDrawdownPct))    return; // hard stop, no override
   if(!RuleGuards::SpreadOK(InpMaxSpreadPoints))     return; // spread-gate

   // TODO: entry signal logic (your existing strategy)
   // TODO: entry-time-offset — delay InpEntryOffsetMs before sending the order
   // TODO: ATR trailing stop management on open positions (uses g_atrHandle)
   // TODO: partial close at 1R -> move to breakeven -> trail remainder

   // WHEN THE ORDER-SENDING CODE LANDS, it must do all three of these:
   //
   //   1. Decide the stop FIRST, then let the stop decide the size — never the
   //      other way round. Size is an output, not an input.
   //
   //         double stopPts = ...;                       // from ATR, structure, etc.
   //         stopPts = MathMax(stopPts, (double)g_stopsLevel);   // broker minimum
   //
   //         double lot = RuleGuards::MaxLotForStop(_Symbol, stopPts,
   //                         InpRiskPctPerTrade, InpMaxDailyLossPct,
   //                         InpMaxDrawdownPct);
   //         if(lot <= 0.0) return;                      // 0 means DO NOT TRADE
   //
   //      A zero is a real answer, not an error: no room left inside the limits,
   //      something unstopped is already open, or the broker's minimum lot is
   //      itself too big for this account. All three mean the same thing — stand
   //      down. Never substitute a minimum lot for a zero.
   //
   //   2. Re-check with RuleGuards::SizeOK(...) immediately before OrderSend.
   //      The account can move between sizing and sending.
   //
   //   3. Send with g_fillingMode (resolved in OnInit from what the broker
   //      advertises) and keep stops at least g_stopsLevel points from price.
   //      Neither is safe to hardcode; both are broker-specific.

   // NOTE: this EA does NOT self-monitor inactivity — that guard lives in the
   // orchestration layer (inactivity_watchdog.py), which reads this account's
   // trade history via the MCP server. Don't duplicate that logic here.
}
//+------------------------------------------------------------------+
