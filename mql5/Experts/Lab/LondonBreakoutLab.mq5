//+------------------------------------------------------------------+
//| LondonBreakoutLab.mq5                                             |
//|                                                                   |
//| WHAT THIS IS: a BACKTEST INSTRUMENT, not a production EA.         |
//|                                                                   |
//| It exists to answer one question — does the London-breakout-of-   |
//| the-overnight-range idea have anything in it on XAUUSD? — using   |
//| MetaTrader's Strategy Tester. It is hypothesis #1, proposed on    |
//| 11 Aug 2026 because it is simple, mechanical and fits the         |
//| account's arithmetic, NOT because there is evidence it is         |
//| profitable. That is exactly what this file is meant to find out.  |
//|                                                                   |
//| WHY IT IS A SEPARATE FILE FROM AgenticEA.                         |
//| AgenticEA deliberately contains no order-sending code, so that no |
//| accident, misconfiguration or stray chart attach can make it      |
//| trade before someone decides it should. That property is worth    |
//| keeping. This file DOES send orders — it has to, the Strategy     |
//| Tester only runs EAs — so it is quarantined here in Lab/ under a  |
//| name nobody will confuse with the production EA. If the backtest  |
//| justifies it, the logic gets PORTED into AgenticEA deliberately.  |
//| It does not get promoted by being renamed.                        |
//|                                                                   |
//| >> DO NOT ATTACH THIS TO A LIVE CHART. Strategy Tester only. <<   |
//|                                                                   |
//| THE RULE, in full:                                                |
//|   1. Measure the high and low of the quiet overnight session.     |
//|   2. In the London morning, wait for the first M15 bar to CLOSE   |
//|      outside that range. Close above -> buy. Close below -> sell. |
//|   3. Stop loss at the MIDDLE of the overnight range.              |
//|   4. Take profit at twice the stop distance (2R).                 |
//|   5. One trade per day maximum, win or lose.                      |
//|   6. Everything flat by the evening. No overnight, no weekend.    |
//|                                                                   |
//| Position size is NOT a free parameter. It comes from              |
//| RuleGuards::MaxLotForStop(), the same preventive size cap the     |
//| production EA uses, so the backtest is constrained by the real    |
//| risk engine rather than an idealised one. If the guard returns    |
//| 0.0 the day is skipped — which is the honest result, not a bug.   |
//+------------------------------------------------------------------+
#property copyright "MT5-Set-up"
#property version   "1.00"
#property strict
#property description "BACKTEST ONLY - London breakout of the overnight range. Do not attach to a live chart."

#include <Trade/Trade.mqh>
#include <RuleGuards.mqh>

//--- Risk. These MIRROR the production EA. Kept as inputs so the tester
//    can sweep them, but the defaults are the live settings, deliberately:
//    a backtest run at gentler risk than production tells you nothing about
//    whether production survives.
input double InpRiskPctPerTrade   = 2.0;    // risk per trade, % of equity
input double InpMaxDailyLossPct   = 4.0;    // hard stop for the day
input double InpMaxDrawdownPct    = 8.0;    // hard stop, full account (trailing)
input double InpMaxSpreadPoints   = 60.0;   // refuse to trade through a dislocation

//--- Session windows, in SERVER time (the times the terminal itself shows).
//    Measured 11 Aug 2026: this broker's server clock runs UK time + 2 hours.
//    So the UK-time rule maps onto server time as:
//        overnight range  00:00-08:00 UK  ->  02:00-10:00 server
//        breakout window  08:00-12:00 UK  ->  10:00-14:00 server
//        flatten          19:00    UK     ->  21:00    server
//    If the broker changes its clock (or DST shifts), these are the only
//    numbers that need moving.
input int    InpRangeStartHour    = 2;      // server hour the overnight range starts
input int    InpRangeEndHour      = 10;     // server hour it ends (= breakout window opens)
input int    InpBreakoutEndHour   = 14;     // server hour after which no new entries
input int    InpFlattenHour       = 21;     // server hour everything gets closed

//--- Rule shape.
input double InpRewardMultiple    = 2.0;    // take profit = this x the stop distance
input int    InpMinRangePoints    = 200;    // ignore an absurdly tight night ($2.00)
input long   InpMagic             = 20260811;

CTrade   g_trade;

//--- Per-day state. All reset by RefreshDay() when the server date rolls.
datetime g_currentDay   = 0;      // server date these figures belong to
double   g_rangeHigh    = 0.0;
double   g_rangeLow     = 0.0;
bool     g_rangeReady   = false;  // has the overnight window closed and been measured?
bool     g_tradedToday  = false;  // one trade per day, win or lose
datetime g_lastBarTime  = 0;      // for new-bar detection

//--- Counters, printed at the end of the run. The Strategy Tester's own
//    report says how the money did; these say what the RULE did, which is
//    a different and equally important question. "0 trades" and "lost money"
//    need very different responses.
int      g_daysSeen      = 0;
int      g_daysNoRange   = 0;     // couldn't measure the overnight window
int      g_daysTooTight  = 0;     // range narrower than InpMinRangePoints
int      g_daysNoSize    = 0;     // risk engine refused: stop too wide for min lot
int      g_daysBlocked   = 0;     // a guard (daily/drawdown/spread) said no
int      g_entries       = 0;
int      g_flattened     = 0;     // closed by the evening cutoff, not SL/TP

//+------------------------------------------------------------------+
int OnInit()
{
   RuleGuards::Init();

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);   // this broker is IOC-only
   g_trade.SetDeviationInPoints(20);

   if(InpRangeStartHour >= InpRangeEndHour || InpRangeEndHour >= InpBreakoutEndHour)
   {
      Print("Lab: session hours are not in order (range start < range end < breakout end). Refusing to run.");
      return INIT_PARAMETERS_INCORRECT;
   }

   Print("LondonBreakoutLab: BACKTEST INSTRUMENT. Risk ", DoubleToString(InpRiskPctPerTrade, 2),
         "% per trade, stop at overnight-range midpoint, target ",
         DoubleToString(InpRewardMultiple, 1), "R, one trade per day.");
   Print("LondonBreakoutLab: server-time windows — range ", InpRangeStartHour, ":00-", InpRangeEndHour,
         ":00, entries until ", InpBreakoutEndHour, ":00, flat at ", InpFlattenHour, ":00.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("LondonBreakoutLab: %d trading days seen | %d entries taken", g_daysSeen, g_entries);
   PrintFormat("LondonBreakoutLab: days skipped — no range %d, range too tight %d, "
               "risk engine refused size %d, guard blocked %d",
               g_daysNoRange, g_daysTooTight, g_daysNoSize, g_daysBlocked);
   PrintFormat("LondonBreakoutLab: %d position(s) closed by the evening cutoff rather than SL/TP", g_flattened);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Call this EVERY tick, not just on entries: DrawdownOK() is what advances
   // the equity high-water mark, and the trailing drawdown floor is wrong if
   // it only gets updated on the ticks we happen to be looking for a trade.
   bool ddOK    = RuleGuards::DrawdownOK(InpMaxDrawdownPct);
   bool dailyOK = RuleGuards::DailyLossOK(InpMaxDailyLossPct);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   RefreshDay(now);

   // The evening cutoff is a tick-level job, not a bar-level one — a position
   // should not sit open for up to 15 more minutes waiting for a bar to close.
   if(now.hour >= InpFlattenHour)
   {
      FlattenAll();
      return;
   }

   //--- Everything below is decided on CLOSED bars only.
   datetime barTime = iTime(_Symbol, PERIOD_M15, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   // Measure the overnight range once, on the first new bar after the window shuts.
   if(!g_rangeReady && now.hour >= InpRangeEndHour)
      MeasureOvernightRange(now);

   if(!g_rangeReady)                    return;   // still inside the overnight window
   if(g_tradedToday)                    return;   // one trade per day, already used
   if(now.hour >= InpBreakoutEndHour)   return;   // London morning is over

   //--- Did the bar that just closed break the range?
   double closed = iClose(_Symbol, PERIOD_M15, 1);
   if(closed <= 0.0) return;

   int direction = 0;
   if(closed > g_rangeHigh)      direction =  1;
   else if(closed < g_rangeLow)  direction = -1;
   else return;

   //--- Guards, in the order that makes the skip reason readable.
   if(!dailyOK || !ddOK)
   {
      g_daysBlocked++;
      g_tradedToday = true;    // the day is over for us either way
      return;
   }
   if(!RuleGuards::SpreadOK(InpMaxSpreadPoints))
      return;                  // NOT counted as the day's trade — spread may narrow

   TryEnter(direction);
}

//+------------------------------------------------------------------+
//| Reset every per-day figure when the server date changes.          |
//+------------------------------------------------------------------+
void RefreshDay(const MqlDateTime &now)
{
   MqlDateTime d = now;
   d.hour = 0; d.min = 0; d.sec = 0;
   datetime today = StructToTime(d);

   if(today == g_currentDay) return;

   g_currentDay  = today;
   g_rangeHigh   = 0.0;
   g_rangeLow    = 0.0;
   g_rangeReady  = false;
   g_tradedToday = false;
   g_daysSeen++;
}

//+------------------------------------------------------------------+
//| High and low of the overnight window, from closed M15 bars.       |
//+------------------------------------------------------------------+
void MeasureOvernightRange(const MqlDateTime &now)
{
   MqlDateTime s = now;
   s.hour = InpRangeStartHour; s.min = 0; s.sec = 0;
   datetime rangeStart = StructToTime(s);

   MqlDateTime e = now;
   e.hour = InpRangeEndHour; e.min = 0; e.sec = 0;
   datetime rangeEnd = StructToTime(e);

   // Bar indices count BACKWARDS: 0 is the forming bar, larger is older. So the
   // start of the window has the LARGER index. Anything else means the history
   // has a hole in it and the range would be measured over the wrong bars.
   int shiftStart = iBarShift(_Symbol, PERIOD_M15, rangeStart, false);
   int shiftEnd   = iBarShift(_Symbol, PERIOD_M15, rangeEnd - 1, false);

   if(shiftStart < 0 || shiftEnd < 0 || shiftStart < shiftEnd)
   {
      g_daysNoRange++;
      g_rangeReady  = true;    // measured and rejected — do not retry all morning
      g_tradedToday = true;
      return;
   }

   int count = shiftStart - shiftEnd + 1;
   int hi = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, count, shiftEnd);
   int lo = iLowest (_Symbol, PERIOD_M15, MODE_LOW,  count, shiftEnd);
   if(hi < 0 || lo < 0)
   {
      g_daysNoRange++;
      g_rangeReady  = true;
      g_tradedToday = true;
      return;
   }

   g_rangeHigh  = iHigh(_Symbol, PERIOD_M15, hi);
   g_rangeLow   = iLow (_Symbol, PERIOD_M15, lo);
   g_rangeReady = true;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double heightPts = (point > 0.0) ? (g_rangeHigh - g_rangeLow) / point : 0.0;

   // A near-flat night gives a stop so tight the spread dominates it. Skipping
   // is the correct answer, not sizing up to compensate.
   if(heightPts < InpMinRangePoints)
   {
      g_daysTooTight++;
      g_tradedToday = true;
   }
}

//+------------------------------------------------------------------+
//| Size from the stop via the production risk engine, then send.     |
//+------------------------------------------------------------------+
void TryEnter(int direction)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0) return;

   double midpoint = (g_rangeHigh + g_rangeLow) / 2.0;
   double price    = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price <= 0.0) return;

   double stopDistance = (direction > 0) ? (price - midpoint) : (midpoint - price);
   if(stopDistance <= 0.0) return;          // price already through the midpoint

   double stopPoints = stopDistance / point;

   // The broker will reject a stop closer than its stops level.
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopPoints <= (double)stopsLevel) return;

   //--- THE size decision. Not a parameter — an output of the risk engine,
   //    which returns 0.0 when this stop cannot be traded inside the limits
   //    at the smallest lot the broker allows.
   double lot = RuleGuards::MaxLotForStop(_Symbol, stopPoints, InpRiskPctPerTrade,
                                          InpMaxDailyLossPct, InpMaxDrawdownPct);
   if(lot <= 0.0)
   {
      g_daysNoSize++;
      g_tradedToday = true;
      return;
   }

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(midpoint, digits);
   double tp = NormalizeDouble((direction > 0) ? price + InpRewardMultiple * stopDistance
                                               : price - InpRewardMultiple * stopDistance, digits);

   // Re-check immediately before sending: the account can move between the
   // sizing call and this one. Same discipline the production EA documents.
   if(!RuleGuards::SizeOK(_Symbol, lot, stopPoints, InpRiskPctPerTrade,
                          InpMaxDailyLossPct, InpMaxDrawdownPct))
   {
      g_daysNoSize++;
      g_tradedToday = true;
      return;
   }

   bool sent = (direction > 0)
               ? g_trade.Buy (lot, _Symbol, 0.0, sl, tp, "LBLab")
               : g_trade.Sell(lot, _Symbol, 0.0, sl, tp, "LBLab");

   // The day is used up either way. A rejected order is not a free retry —
   // re-firing on the next bar would quietly turn "one trade per day" into
   // "as many as it takes", which is a different and much riskier rule.
   g_tradedToday = true;

   if(sent) g_entries++;
   else     PrintFormat("Lab: order rejected — retcode %d (%s)",
                        g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Close anything this EA opened. Nothing is held overnight.         |
//+------------------------------------------------------------------+
void FlattenAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      if(g_trade.PositionClose(ticket)) g_flattened++;
   }
}
//+------------------------------------------------------------------+
