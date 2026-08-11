//+------------------------------------------------------------------+
//|                                          AccountDiagnostics.mq5 |
//|  READ-ONLY. Places no orders, changes no settings. Run this in a  |
//|  logged-in terminal to capture the account and symbol facts the   |
//|  EA will depend on. Answers the questions AgenticEA's OnInit TODO |
//|  currently leaves open: min lot, filling mode, stops level.       |
//|                                                                   |
//|  Must run in the GUI terminal, not headless — a headless run has  |
//|  no broker connection, so every account figure reads 0.00.        |
//|                                                                   |
//|  Output goes to the Experts tab AND to MQL5/Files/<InpOutFile>,   |
//|  because reading a 40-line report off a screenshot loses the top  |
//|  of it every time.                                                |
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "1.10"
#property strict
#property script_show_inputs

#include <RuleGuards.mqh>

input double InpMaxDailyLossPct = 4.0;    // same defaults as AgenticEA, so the
input double InpMaxDrawdownPct  = 8.0;    // guard verdicts below match what the
input double InpMaxSpreadPoints = 30;     // EA would decide on this same tick
input int    InpSpreadSamples   = 60;     // spread samples to collect
input int    InpSampleGapMs     = 250;    // gap between samples (60 x 250ms = 15s)
input string InpOutFile         = "AgenticEA_diagnostics.txt";

string g_report = "";

//--- print to the Experts tab and accumulate for the file ----------
void Log(string s)
{
   Print(s);
   g_report += s + "\r\n";
}

//--- enum -> readable text -----------------------------------------
string MarginModeText(long m)
{
   switch((ENUM_ACCOUNT_MARGIN_MODE)m)
   {
      case ACCOUNT_MARGIN_MODE_RETAIL_NETTING: return "netting";
      case ACCOUNT_MARGIN_MODE_RETAIL_HEDGING: return "hedging";
      case ACCOUNT_MARGIN_MODE_EXCHANGE:       return "exchange";
   }
   return "unknown(" + (string)m + ")";
}

string TradeModeText(long m)
{
   switch((ENUM_SYMBOL_TRADE_MODE)m)
   {
      case SYMBOL_TRADE_MODE_DISABLED:  return "DISABLED - cannot trade this symbol";
      case SYMBOL_TRADE_MODE_LONGONLY:  return "long only";
      case SYMBOL_TRADE_MODE_SHORTONLY: return "short only";
      case SYMBOL_TRADE_MODE_CLOSEONLY: return "close only";
      case SYMBOL_TRADE_MODE_FULL:      return "full access";
   }
   return "unknown(" + (string)m + ")";
}

string ExecModeText(long m)
{
   switch((ENUM_SYMBOL_TRADE_EXECUTION)m)
   {
      case SYMBOL_TRADE_EXECUTION_REQUEST:  return "request";
      case SYMBOL_TRADE_EXECUTION_INSTANT:  return "instant";
      case SYMBOL_TRADE_EXECUTION_MARKET:   return "market";
      case SYMBOL_TRADE_EXECUTION_EXCHANGE: return "exchange";
   }
   return "unknown(" + (string)m + ")";
}

string FillingText(long flags)
{
   string s = "";
   if((flags & SYMBOL_FILLING_FOK) != 0) s += "FOK ";
   if((flags & SYMBOL_FILLING_IOC) != 0) s += "IOC ";
   if(s == "") s = "(none advertised - RETURN only)";
   return s;
}

string YesNo(bool b) { return b ? "YES" : "NO"; }

//+------------------------------------------------------------------+
void OnStart()
{
   string sym = _Symbol;

   Log("[DIAG] ===== ACCOUNT DIAGNOSTICS - read-only, no orders =====");
   Log("[DIAG] Run at " + TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS) +
       " local / " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " server");

   //--- permissions: the four switches that must all be on to trade ---
   bool termAllowed   = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool mqlAllowed    = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool acctAllowed   = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool expertAllowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

   Log("[DIAG] PERMISSIONS");
   Log("[DIAG]   Algo Trading button (terminal)  : " + YesNo(termAllowed));
   Log("[DIAG]   Allowed for this program        : " + YesNo(mqlAllowed));
   Log("[DIAG]   Broker allows trading on acct   : " + YesNo(acctAllowed));
   Log("[DIAG]   Broker allows EAs on acct       : " + YesNo(expertAllowed));
   if(!termAllowed)
      Log("[DIAG]   >> Algo Trading is OFF. An EA cannot place orders in this state.");

   //--- account ------------------------------------------------------
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   string ccy     = AccountInfoString(ACCOUNT_CURRENCY);

   Log("[DIAG] ACCOUNT");
   Log("[DIAG]   Login / server  : " + (string)AccountInfoInteger(ACCOUNT_LOGIN) +
                                       " @ " + AccountInfoString(ACCOUNT_SERVER));
   Log("[DIAG]   Company         : " + AccountInfoString(ACCOUNT_COMPANY));
   Log("[DIAG]   Balance         : " + DoubleToString(balance, 2) + " " + ccy);
   Log("[DIAG]   Equity          : " + DoubleToString(equity, 2) + " " + ccy);
   Log("[DIAG]   Free margin     : " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + " " + ccy);
   Log("[DIAG]   Leverage        : 1:" + (string)AccountInfoInteger(ACCOUNT_LEVERAGE));
   Log("[DIAG]   Margin mode     : " + MarginModeText(AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
   Log("[DIAG]   Data folder     : " + TerminalInfoString(TERMINAL_DATA_PATH));

   //--- symbol contract specs ----------------------------------------
   double minLot    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double contract  = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickVal   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   long   digits    = SymbolInfoInteger(sym, SYMBOL_DIGITS);
   long   stopsLvl  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);

   Log("[DIAG] SYMBOL: " + sym + "  (" + SymbolInfoString(sym, SYMBOL_DESCRIPTION) + ")");
   Log("[DIAG]   Trade mode      : " + TradeModeText(SymbolInfoInteger(sym, SYMBOL_TRADE_MODE)));
   Log("[DIAG]   Execution       : " + ExecModeText(SymbolInfoInteger(sym, SYMBOL_TRADE_EXEMODE)));
   Log("[DIAG]   Filling modes   : " + FillingText(SymbolInfoInteger(sym, SYMBOL_FILLING_MODE)));
   Log("[DIAG]   Contract size   : " + DoubleToString(contract, 2) + " per 1.00 lot");
   Log("[DIAG]   Lots min/max/step: " + DoubleToString(minLot, 2) + " / " +
                                        DoubleToString(maxLot, 2) + " / " +
                                        DoubleToString(lotStep, 2));
   Log("[DIAG]   Digits / point  : " + (string)digits + " / " + DoubleToString(point, 8));
   Log("[DIAG]   Stops level     : " + (string)stopsLvl + " points  (min SL/TP distance from price)");
   Log("[DIAG]   Freeze level    : " + (string)freezeLvl + " points");

   //--- spread, sampled rather than guessed ---------------------------
   // A single reading told us almost nothing except that we tripped the gate.
   // What sets a sane gate is the distribution, and how it moves with session.
   int n = MathMax(1, InpSpreadSamples);
   long samples[];
   ArrayResize(samples, n);
   for(int i = 0; i < n; i++)
   {
      samples[i] = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      if(i < n - 1) Sleep(InpSampleGapMs);
   }
   ArraySort(samples);

   long   sprMin = samples[0];
   long   sprMax = samples[n - 1];
   long   sprMed = samples[n / 2];
   double sprAvg = 0.0;
   for(int i = 0; i < n; i++) sprAvg += (double)samples[i];
   sprAvg /= n;

   int blocked = 0;
   for(int i = 0; i < n; i++) if((double)samples[i] > InpMaxSpreadPoints) blocked++;

   Log("[DIAG] SPREAD over " + (string)n + " samples / " +
       DoubleToString(n * InpSampleGapMs / 1000.0, 1) + "s");
   Log("[DIAG]   min / median / max: " + (string)sprMin + " / " + (string)sprMed +
                                         " / " + (string)sprMax + " points");
   Log("[DIAG]   mean             : " + DoubleToString(sprAvg, 1) + " points");
   Log("[DIAG]   in money         : median spread costs " +
       DoubleToString((double)sprMed * point, (int)digits) + " per ounce");
   Log("[DIAG]   blocked by gate  : " + (string)blocked + " of " + (string)n +
       " samples exceeded " + DoubleToString(InpMaxSpreadPoints, 0) + " points (" +
       DoubleToString(100.0 * blocked / n, 0) + "% of the time the EA would refuse to trade)");

   //--- what a minimum-size trade actually costs ----------------------
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double margin = 0.0;
   bool   marginOK = OrderCalcMargin(ORDER_TYPE_BUY, sym, minLot, ask, margin);

   double valuePerPointMinLot = 0.0;
   if(tickSize > 0.0)
      valuePerPointMinLot = tickVal * (point / tickSize) * minLot;

   Log("[DIAG] MINIMUM TRADE (" + DoubleToString(minLot, 2) + " lot at " +
       DoubleToString(ask, (int)digits) + ")");
   if(marginOK)
      Log("[DIAG]   Margin required : " + DoubleToString(margin, 2) + " " + ccy +
          "  (" + DoubleToString(equity > 0.0 ? margin / equity * 100.0 : 0.0, 1) + "% of equity)");
   else
      Log("[DIAG]   Margin required : CALCULATION FAILED, error " + (string)GetLastError());

   Log("[DIAG]   Value of 1 point: " + DoubleToString(valuePerPointMinLot, 4) + " " + ccy);
   Log("[DIAG]   So a " + DoubleToString(100 * point, (int)digits) + " move = " +
       DoubleToString(valuePerPointMinLot * 100.0, 2) + " " + ccy);
   Log("[DIAG]   Cost to cross the median spread: " +
       DoubleToString(valuePerPointMinLot * (double)sprMed, 2) + " " + ccy);

   //--- risk sizing sanity check --------------------------------------
   // At minimum size, how big a stop can a 1% risk budget actually pay for?
   double risk1pct = equity * 0.01;
   if(valuePerPointMinLot > 0.0)
   {
      double affordablePoints = risk1pct / valuePerPointMinLot;
      Log("[DIAG] RISK SIZING at minimum lot");
      Log("[DIAG]   1% of equity    : " + DoubleToString(risk1pct, 2) + " " + ccy);
      Log("[DIAG]   buys a stop of  : " + DoubleToString(affordablePoints, 0) + " points = " +
          DoubleToString(affordablePoints * point, (int)digits) + " of price movement");
      Log("[DIAG]   NOTE: 0.01 lot is the floor here. If the strategy needs a wider stop");
      Log("[DIAG]         than that, 1% risk is not reachable on this account size.");
   }

   //--- the guards, on live numbers ----------------------------------
   RuleGuards::Init();

   bool dailyOK = RuleGuards::DailyLossOK(InpMaxDailyLossPct);
   bool ddOK    = RuleGuards::DrawdownOK(InpMaxDrawdownPct);
   bool sprdOK  = RuleGuards::SpreadOK(InpMaxSpreadPoints);

   Log("[DIAG] RULE GUARDS (after Init, on live account values)");
   Log("[DIAG]   Day-start equity: " + DoubleToString(RuleGuards::DayStartEquity(), 2) + " " + ccy);
   Log("[DIAG]   Equity high-water: " + DoubleToString(RuleGuards::EquityHighWater(), 2) + " " + ccy);
   Log("[DIAG]   Initial balance : " + DoubleToString(RuleGuards::InitialBalance(), 2) + " " + ccy);
   Log("[DIAG]   DailyLossOK(" + DoubleToString(InpMaxDailyLossPct, 1) + "%) : " + YesNo(dailyOK));
   Log("[DIAG]   DrawdownOK(" + DoubleToString(InpMaxDrawdownPct, 1) + "%)  : " + YesNo(ddOK));
   Log("[DIAG]   SpreadOK(" + DoubleToString(InpMaxSpreadPoints, 0) + "pts)  : " + YesNo(sprdOK));
   Log("[DIAG]   >> Would the EA be clear to trade this tick? " + YesNo(dailyOK && ddOK && sprdOK));

   Log("[DIAG] ===== END - no orders were placed =====");

   //--- write the report out ------------------------------------------
   int fh = FileOpen(InpOutFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh == INVALID_HANDLE)
      Print("[DIAG] could not write ", InpOutFile, ", error ", GetLastError());
   else
   {
      FileWriteString(fh, g_report);
      FileClose(fh);
      Print("[DIAG] report written to MQL5/Files/", InpOutFile);
   }
}
//+------------------------------------------------------------------+
