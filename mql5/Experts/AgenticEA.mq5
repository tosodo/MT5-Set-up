//+------------------------------------------------------------------+
//|                                                     AgenticEA.mq5 |
//|      Deterministic execution engine — the EA is the ownable IP.   |
//|      Claude/MCP orchestrates and monitors; this EA decides trades.|
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "1.20"
#property strict

#include <RuleGuards.mqh>

input double InpMaxDailyLossPct   = 4.0;    // hard stop for the day  — see NOTE below
input double InpMaxDrawdownPct    = 8.0;    // hard stop, full account — see NOTE below
input int    InpEntryOffsetMs     = 150;    // entry-time-offset concept, from lessons log
input double InpATRMultiplier     = 2.0;    // ATR trailing stop multiplier
input double InpMaxSpreadPoints   = 60;     // spread-limit gate — see note below
input int    InpATRPeriod         = 14;     // ATR period for the trailing stop
input double InpRiskPctPerTrade   = 2.0;    // max % of equity risked on one trade

// NOTE ON THE TWO LOSS LIMITS: set deliberately on 11 Aug 2026. They were
// placeholders before; these values are now a decision, not a leftover.
//
// They are set to the TIGHT END of what a funded/evaluation account is likely to
// impose (industry norm clusters at 4-5% daily and 8-10% overall). That direction
// is deliberate: a system that runs comfortably inside 4%/8% already satisfies a
// venue that allows 5%/10%, so choosing a venue later can only ever LOOSEN these,
// never force a tightening. Tightening after the fact is the expensive discovery.
//
// Also deliberate: the drawdown baseline stays TRAILING (from the equity high-water
// mark) rather than STATIC (from the starting balance) — see DrawdownOK(). Trailing
// is never looser than static, so the same reasoning applies: honouring a trailing
// 8% automatically honours a static 8%.
//
// WHAT ACTUALLY ENFORCES THESE. DailyLossOK/DrawdownOK are reactive — they read
// equity that has already moved, so alone they would only ever block the NEXT
// trade. What makes the limits hold is MaxLotForStop(): it refuses to size any
// trade at all if something is open without a stop loss, and it sizes every trade
// so that the total loss-to-stops across ALL open positions stays inside the room
// left to both limits. Every position stopped + total risk bounded in advance =
// open positions cannot collectively breach the limits. That is the guarantee.
// It rests on stops actually filling near their price, so it can still be beaten
// by a gap or severe slippage. Nothing in software fixes that; only smaller size.

// NOTE ON InpRiskPctPerTrade: raised 1.0 -> 2.0 deliberately, not casually.
// On a 1,000 account with a 0.01 lot floor, 1% (10) covered only a ~1,350-point
// stop, so the size cap correctly refused almost every realistic gold trade.
// 2% roughly doubles the tradable stop width AND allows a genuinely larger lot
// on tight stops. The ceiling on this number is InpMaxDailyLossPct, not comfort:
// at 2% per trade against a 4% daily limit, TWO losses end the trading day. Go
// much above 2% and a single loss does. See ReportSizingEnvelope() below, which
// warns in the journal when this ratio gets dangerous.

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

   // How many losing trades in a row before the daily gate shuts the day down?
   // This is the number that decides whether the risk % is survivable, and it
   // is the one nobody works out by hand. So the EA works it out and says it.
   if(InpRiskPctPerTrade > 0.0)
   {
      int lossesToDailyStop = (int)MathFloor(InpMaxDailyLossPct / InpRiskPctPerTrade);
      Print("AgenticEA: at ", DoubleToString(InpRiskPctPerTrade, 2), "% per trade, ",
            lossesToDailyStop, " consecutive full-stop losses reach the ",
            DoubleToString(InpMaxDailyLossPct, 1), "% daily limit and trading stops for the day.");

      if(lossesToDailyStop <= 1)
         Print("AgenticEA: WARNING — a SINGLE losing trade ends the day at this risk level. ",
               "That is almost certainly too high. Lower InpRiskPctPerTrade.");
   }
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
