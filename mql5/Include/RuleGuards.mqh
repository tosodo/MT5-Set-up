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
//| the failure mode this project already paid for once. The sizing   |
//| guard follows the same rule, returning 0.0 (= trade nothing).     |
//|                                                                   |
//| TWO KINDS OF GUARD, and the difference matters:                   |
//|   REACTIVE  — DailyLossOK / DrawdownOK read equity that has       |
//|               already moved. They stop the NEXT trade. They can   |
//|               never stop the one that caused the breach.          |
//|   PREVENTIVE — MaxLotForStop runs before the order exists and     |
//|               bounds the worst case in advance. This is the only  |
//|               one that can keep a limit rather than report it.    |
//| Both are needed. Neither substitutes for the other.               |
//+------------------------------------------------------------------+
#ifndef RULEGUARDS_MQH
#define RULEGUARDS_MQH

// Never commit more than this fraction of free margin to a single position.
// Not a risk limit — the stop loss is that. This is the separate protection
// against a margin call closing positions for us, at a price of the broker's
// choosing rather than ours.
#define MARGIN_USE_LIMIT 0.50

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
   //
   //    TRAILING IS A DECISION, NOT A DEFAULT (made 11 Aug 2026). Some venues
   //    measure STATIC drawdown from the initial balance instead. Trailing is
   //    never looser than static — once equity has made a new high the trailing
   //    floor sits above the static one, and before that they are identical — so
   //    an account that respects a trailing 8% has already respected a static 8%.
   //    Choosing trailing means a future venue can only ever let us relax this,
   //    never force us to tighten it after the fact.
   //
   //    Switching to static is therefore optional, not a fix. If a venue's rules
   //    make it worth doing, change s_equityHighWater to s_initialBalance BOTH
   //    here and in MaxLotForStop() below — they must agree or the size cap will
   //    be budgeting against a different floor than the guard is enforcing.
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
      if(!s_initialised) return false;
      double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      return spread <= maxSpreadPoints;
   }

   //--- How much can still be lost from HERE if every open position runs to
   //    its stop. Uses current price, not entry price, because equity already
   //    reflects the move so far — counting from entry would double-count it.
   //
   //    Returns -1.0 if any position has no stop loss. That is not a number we
   //    can work with: an unstopped position's worst case is the whole account,
   //    so the only correct answer is to refuse to add more risk on top of it.
   static double OpenRiskFromHere()
   {
      double total = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;

         double sl = PositionGetDouble(POSITION_SL);
         if(sl <= 0.0) return -1.0;              // unstopped: unbounded risk

         ENUM_ORDER_TYPE dir =
            ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

         double profit = 0.0;
         if(!OrderCalcProfit(dir,
                             PositionGetString(POSITION_SYMBOL),
                             PositionGetDouble(POSITION_VOLUME),
                             PositionGetDouble(POSITION_PRICE_CURRENT),
                             sl, profit))
            return -1.0;                          // cannot price it: refuse

         if(profit < 0.0) total += -profit;       // stop already in profit costs nothing
      }
      return total;
   }

   //--- THE POSITION-SIZE CAP.
   //
   //    The other guards are reactive: they read equity that has already moved,
   //    so they can only stop the NEXT trade, never the one that breached the
   //    limit. At high leverage a single oversized order can blow through both
   //    the daily and the drawdown limit between one tick and the next. This is
   //    the guard that runs BEFORE the order exists, and it is the only one that
   //    can prevent that rather than report it.
   //
   //    Returns the largest volume that keeps the worst case inside EVERY limit:
   //      - the per-trade risk budget,
   //      - the room left before today's daily-loss limit,
   //      - the room left before the drawdown limit,
   //      - what is already at risk in open positions,
   //      - free margin,
   //      - the symbol's own min/max/step.
   //    Returns 0.0 for "do not trade" — including when the smallest lot the
   //    broker allows would already be too big. Fail-closed: every unknown
   //    returns 0.0 rather than a guess.
   static double MaxLotForStop(string sym,
                               double stopDistancePoints,
                               double maxRiskPctPerTrade,
                               double maxDailyLossPct,
                               double maxDrawdownPct)
   {
      if(!s_initialised)            return 0.0;
      if(stopDistancePoints <= 0.0) return 0.0;   // no stop = no size we can justify
      if(maxRiskPctPerTrade <= 0.0) return 0.0;

      RollDayIfNeeded();

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0) return 0.0;

      //--- 1. How much money may this trade put at risk?
      double budget = equity * maxRiskPctPerTrade / 100.0;

      // Never more than the room left to the daily limit...
      if(s_dayStartEquity > 0.0)
      {
         double dailyFloor = s_dayStartEquity * (1.0 - maxDailyLossPct / 100.0);
         budget = MathMin(budget, equity - dailyFloor);
      }
      else return 0.0;

      // ...nor to the drawdown limit. Keep this baseline in step with
      // DrawdownOK() above: swap to s_initialBalance together, or not at all.
      double ddBaseline = s_equityHighWater;      // <- swap with DrawdownOK()
      if(ddBaseline > 0.0)
      {
         double ddFloor = ddBaseline * (1.0 - maxDrawdownPct / 100.0);
         budget = MathMin(budget, equity - ddFloor);
      }
      else return 0.0;

      // What open positions could still lose comes out of the same budget.
      double openRisk = OpenRiskFromHere();
      if(openRisk < 0.0) return 0.0;              // something unstopped is open
      budget -= openRisk;

      if(budget <= 0.0) return 0.0;               // no room left at all

      //--- 2. What does one lot lose over that stop distance?
      double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
      double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(point <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0) return 0.0;

      double lossPerLot = stopDistancePoints * point / tickSize * tickValue;
      if(lossPerLot <= 0.0) return 0.0;

      double lot = budget / lossPerLot;

      //--- 3. Margin is a second, independent ceiling.
      //    Deliberately capped well under free margin: a position sized to the
      //    last available pound of margin leaves nothing for the adverse move
      //    that has not happened yet.
      double marginPerLot = 0.0;
      double price = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, price, marginPerLot)) return 0.0;
      if(marginPerLot > 0.0)
      {
         double usableMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * MARGIN_USE_LIMIT;
         lot = MathMin(lot, usableMargin / marginPerLot);
      }

      //--- 4. Fit it to what the broker will actually accept.
      return FloorToLotStep(sym, lot);
   }

   //--- Boolean form, for validating a size someone else calculated.
   //    Use this immediately before OrderSend, even if MaxLotForStop produced
   //    the number — the account can move between sizing and sending.
   static bool SizeOK(string sym,
                      double lot,
                      double stopDistancePoints,
                      double maxRiskPctPerTrade,
                      double maxDailyLossPct,
                      double maxDrawdownPct)
   {
      if(lot <= 0.0) return false;
      double maxLot = MaxLotForStop(sym, stopDistancePoints, maxRiskPctPerTrade,
                                    maxDailyLossPct, maxDrawdownPct);
      return (maxLot > 0.0 && lot <= maxLot + 1e-9);
   }

   //--- Round DOWN to the broker's lot step and clamp to its min/max.
   //    Down, never nearest: rounding up crosses the limit we just calculated.
   //    Returns 0.0 if the result falls below the minimum tradable lot, which
   //    means "this account cannot take this trade at an acceptable size" —
   //    a real and correct answer, not an error.
   static double FloorToLotStep(string sym, double lot)
   {
      double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      if(step <= 0.0) return 0.0;

      // Decimal places implied by the step, so 0.01 normalises to 2 places.
      int digits = 0;
      for(double s = step; s < 1.0 && digits < 8; s *= 10.0) digits++;

      double snapped = NormalizeDouble(MathFloor(lot / step + 1e-9) * step, digits);

      if(snapped > maxLot) snapped = NormalizeDouble(MathFloor(maxLot / step) * step, digits);
      if(snapped < minLot) return 0.0;
      return snapped;
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
