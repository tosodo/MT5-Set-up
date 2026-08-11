//+------------------------------------------------------------------+
//|                                                     AgenticEA.mq5 |
//|      Deterministic execution engine — the EA is the ownable IP.   |
//|      Claude/MCP orchestrates and monitors; this EA decides trades.|
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "1.10"
#property strict

#include <RuleGuards.mqh>

input double InpMaxDailyLossPct   = 4.0;    // fill from rule-map-template.md
input double InpMaxDrawdownPct    = 8.0;    // fill from rule-map-template.md
input int    InpEntryOffsetMs     = 150;    // entry-time-offset concept, from lessons log
input double InpATRMultiplier     = 2.0;    // ATR trailing stop multiplier
input double InpMaxSpreadPoints   = 60;     // spread-limit gate — see note below
input int    InpATRPeriod         = 14;     // ATR period for the trailing stop

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
   //
   // When the order-sending code lands, it must use g_fillingMode (resolved in
   // OnInit from what the broker advertises) and keep stops at least
   // g_stopsLevel points from price. Both are broker-specific and neither is
   // safe to hardcode.

   // NOTE: this EA does NOT self-monitor inactivity — that guard lives in the
   // orchestration layer (inactivity_watchdog.py), which reads this account's
   // trade history via the MCP server. Don't duplicate that logic here.

   // NOTE: there is no position-size cap here yet. At 1:500 leverage a single
   // oversized order can breach both the daily-loss and drawdown limits between
   // one tick and the next, and these guards are reactive — they measure equity
   // that has already moved. A pre-trade size check belongs alongside the entry
   // logic. See docs/broker-puprime-demo-2026-08-11.md.
}
//+------------------------------------------------------------------+
