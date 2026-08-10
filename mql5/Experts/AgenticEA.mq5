//+------------------------------------------------------------------+
//|                                                     AgenticEA.mq5 |
//|      Deterministic execution engine — the EA is the ownable IP.   |
//|      Claude/MCP orchestrates and monitors; this EA decides trades.|
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "0.1"
#property strict

#include <RuleGuards.mqh>

input double InpMaxDailyLossPct   = 4.0;    // fill from rule-map-template.md
input double InpMaxDrawdownPct    = 8.0;    // fill from rule-map-template.md
input int    InpEntryOffsetMs     = 150;    // entry-time-offset concept, from lessons log
input double InpATRMultiplier     = 2.0;    // ATR trailing stop multiplier
input double InpMaxSpreadPoints   = 30;     // spread-limit gate
input int    InpATRPeriod         = 14;     // ATR period for the trailing stop

int g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("AgenticEA: failed to create ATR handle on ", _Symbol);
      return(INIT_FAILED);
   }

   // Captures the daily/high-water baselines the risk guards measure against.
   // Until this runs, every guard blocks trading by design.
   RuleGuards::Init();

   // TODO: validate symbol trading conditions (filling mode, min lot, stops level)
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

   // NOTE: this EA does NOT self-monitor inactivity — that guard lives in the
   // orchestration layer (inactivity_watchdog.py), which reads this account's
   // trade history via the MCP server. Don't duplicate that logic here.
}
//+------------------------------------------------------------------+
