//+------------------------------------------------------------------+
//| RuleGuards.mqh — the risk-rule half of the guard set.             |
//| The cadence/inactivity half deliberately lives OUTSIDE the EA,    |
//| in orchestration/watchdog/ — see docs/rule-map-template.md for why.|
//|                                                                   |
//| NOTE ON STRUCTURE: MQL5 has no `namespace` keyword. The same      |
//| `RuleGuards::Foo()` call syntax is achieved with a class of       |
//| static methods, which MQL5 does support.                          |
//|                                                                   |
//| FAIL-CLOSED: every guard returns false (= block trading) if it    |
//| has not been initialised. A guard that silently passes is exactly |
//| the failure mode this project already paid for once.              |
//+------------------------------------------------------------------+
#ifndef RULEGUARDS_MQH
#define RULEGUARDS_MQH

class RuleGuards
{
private:
   static bool     s_initialised;
   static double   s_dayStartEquity;   // equity at the start of the current server day
   static double   s_equityHighWater;  // running high-water mark, for trailing drawdown
   static double   s_initialBalance;   // balance when the EA was first attached
   static datetime s_currentDay;       // server-date of s_dayStartEquity

   // Roll the daily baseline when the server date changes.
   static void RollDayIfNeeded()
   {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(), t);
      t.hour = 0; t.min = 0; t.sec = 0;
      datetime today = StructToTime(t);

      if(today != s_currentDay)
      {
         s_currentDay     = today;
         s_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
   }

public:
   //--- Call once from OnInit(). Until this runs, every guard blocks.
   static void Init()
   {
      s_initialBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
      s_equityHighWater = AccountInfoDouble(ACCOUNT_EQUITY);
      s_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
      s_currentDay      = 0;
      s_initialised     = true;
      RollDayIfNeeded();
   }

   //--- Today's loss vs. the equity we started the server day with.
   //    Covers realised AND floating P&L, because equity includes both.
   static bool DailyLossOK(double maxDailyLossPct)
   {
      if(!s_initialised) return false;
      RollDayIfNeeded();

      if(s_dayStartEquity <= 0.0) return false;

      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double lossPct = (s_dayStartEquity - equity) / s_dayStartEquity * 100.0;
      return lossPct < maxDailyLossPct;
   }

   //--- Drawdown from the equity high-water mark (trailing DD).
   //    IMPORTANT: some firms measure STATIC drawdown from the initial balance
   //    instead. Confirm which one applies in docs/rule-map-template.md and
   //    switch the baseline below to s_initialBalance if the firm is static-DD.
   static bool DrawdownOK(double maxDrawdownPct)
   {
      if(!s_initialised) return false;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > s_equityHighWater) s_equityHighWater = equity;

      double baseline = s_equityHighWater;   // <- swap to s_initialBalance for static DD
      if(baseline <= 0.0) return false;

      double ddPct = (baseline - equity) / baseline * 100.0;
      return ddPct < maxDrawdownPct;
   }

   //--- Spread gate: refuse to trade through a widened spread.
   static bool SpreadOK(double maxSpreadPoints)
   {
      double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      return spread <= maxSpreadPoints;
   }

   //--- Read-only accessors, for logging / diagnostics.
   static double DayStartEquity()  { return s_dayStartEquity;  }
   static double EquityHighWater() { return s_equityHighWater; }
   static double InitialBalance()  { return s_initialBalance;  }
};

bool     RuleGuards::s_initialised     = false;
double   RuleGuards::s_dayStartEquity  = 0.0;
double   RuleGuards::s_equityHighWater = 0.0;
double   RuleGuards::s_initialBalance  = 0.0;
datetime RuleGuards::s_currentDay      = 0;

#endif
