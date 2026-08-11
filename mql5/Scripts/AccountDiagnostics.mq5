//+------------------------------------------------------------------+
//|                                          AccountDiagnostics.mq5 |
//|  READ-ONLY. Places no orders, changes no settings. Run this in a  |
//|  logged-in terminal to capture the account and symbol facts the   |
//|  EA will depend on. Answers the questions AgenticEA's OnInit TODO |
//|  currently leaves open: min lot, filling mode, stops level.       |
//|                                                                   |
//|  Must run in the GUI terminal, not headless — a headless run has  |
//|  no broker connection, so every account figure reads 0.00.        |
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "1.00"
#property strict
#property script_show_inputs

#include <RuleGuards.mqh>

input double InpMaxDailyLossPct = 4.0;   // same defaults as AgenticEA, so the
input double InpMaxDrawdownPct  = 8.0;   // guard verdicts below match what the
input double InpMaxSpreadPoints = 30;    // EA would decide on this same tick

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

   Print("[DIAG] ===== ACCOUNT DIAGNOSTICS - read-only, no orders =====");

   //--- permissions: the four switches that must all be on to trade ---
   bool termAllowed  = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool mqlAllowed   = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   bool acctAllowed  = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   bool expertAllowed= (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);

   Print("[DIAG] PERMISSIONS");
   Print("[DIAG]   Algo Trading button (terminal)  : ", YesNo(termAllowed));
   Print("[DIAG]   Allowed for this program        : ", YesNo(mqlAllowed));
   Print("[DIAG]   Broker allows trading on acct   : ", YesNo(acctAllowed));
   Print("[DIAG]   Broker allows EAs on acct       : ", YesNo(expertAllowed));
   if(!termAllowed)
      Print("[DIAG]   >> Algo Trading is OFF. An EA cannot place orders in this state.");

   //--- account ------------------------------------------------------
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   string ccy     = AccountInfoString(ACCOUNT_CURRENCY);

   Print("[DIAG] ACCOUNT");
   Print("[DIAG]   Login / server  : ", AccountInfoInteger(ACCOUNT_LOGIN), " @ ",
                                        AccountInfoString(ACCOUNT_SERVER));
   Print("[DIAG]   Company         : ", AccountInfoString(ACCOUNT_COMPANY));
   Print("[DIAG]   Balance         : ", DoubleToString(balance, 2), " ", ccy);
   Print("[DIAG]   Equity          : ", DoubleToString(equity, 2), " ", ccy);
   Print("[DIAG]   Free margin     : ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2), " ", ccy);
   Print("[DIAG]   Leverage        : 1:", AccountInfoInteger(ACCOUNT_LEVERAGE));
   Print("[DIAG]   Margin mode     : ", MarginModeText(AccountInfoInteger(ACCOUNT_MARGIN_MODE)));

   //--- symbol contract specs ----------------------------------------
   double minLot   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double lotStep  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double contract = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double point    = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   long   digits   = SymbolInfoInteger(sym, SYMBOL_DIGITS);
   long   spread   = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   long   stopsLvl = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl= SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);

   Print("[DIAG] SYMBOL: ", sym, "  (", SymbolInfoString(sym, SYMBOL_DESCRIPTION), ")");
   Print("[DIAG]   Trade mode      : ", TradeModeText(SymbolInfoInteger(sym, SYMBOL_TRADE_MODE)));
   Print("[DIAG]   Execution       : ", ExecModeText(SymbolInfoInteger(sym, SYMBOL_TRADE_EXEMODE)));
   Print("[DIAG]   Filling modes   : ", FillingText(SymbolInfoInteger(sym, SYMBOL_FILLING_MODE)));
   Print("[DIAG]   Contract size   : ", DoubleToString(contract, 2), " per 1.00 lot");
   Print("[DIAG]   Lots min/max/step: ", DoubleToString(minLot, 2), " / ",
                                         DoubleToString(maxLot, 2), " / ",
                                         DoubleToString(lotStep, 2));
   Print("[DIAG]   Digits / point  : ", digits, " / ", DoubleToString(point, 8));
   Print("[DIAG]   Spread now      : ", spread, " points (EA gate is ",
                                        DoubleToString(InpMaxSpreadPoints, 0), ")");
   Print("[DIAG]   Stops level     : ", stopsLvl, " points  (min SL/TP distance from price)");
   Print("[DIAG]   Freeze level    : ", freezeLvl, " points");

   //--- what a minimum-size trade actually costs ----------------------
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double margin = 0.0;
   bool   marginOK = OrderCalcMargin(ORDER_TYPE_BUY, sym, minLot, ask, margin);

   double valuePerPointMinLot = 0.0;
   if(tickSize > 0.0)
      valuePerPointMinLot = tickVal * (point / tickSize) * minLot;

   Print("[DIAG] MINIMUM TRADE (", DoubleToString(minLot, 2), " lot at ", DoubleToString(ask, (int)digits), ")");
   if(marginOK)
   {
      Print("[DIAG]   Margin required : ", DoubleToString(margin, 2), " ", ccy,
            "  (", DoubleToString(equity > 0.0 ? margin / equity * 100.0 : 0.0, 1), "% of equity)");
   }
   else
   {
      Print("[DIAG]   Margin required : CALCULATION FAILED, error ", GetLastError());
   }
   Print("[DIAG]   Value of 1 point: ", DoubleToString(valuePerPointMinLot, 4), " ", ccy);
   Print("[DIAG]   So a ", DoubleToString(100 * point, (int)digits), " move = ",
         DoubleToString(valuePerPointMinLot * 100.0, 2), " ", ccy);

   //--- the guards, on live numbers ----------------------------------
   RuleGuards::Init();

   bool dailyOK = RuleGuards::DailyLossOK(InpMaxDailyLossPct);
   bool ddOK    = RuleGuards::DrawdownOK(InpMaxDrawdownPct);
   bool sprdOK  = RuleGuards::SpreadOK(InpMaxSpreadPoints);

   Print("[DIAG] RULE GUARDS (after Init, on live account values)");
   Print("[DIAG]   Day-start equity: ", DoubleToString(RuleGuards::DayStartEquity(), 2), " ", ccy);
   Print("[DIAG]   Equity high-water: ", DoubleToString(RuleGuards::EquityHighWater(), 2), " ", ccy);
   Print("[DIAG]   Initial balance : ", DoubleToString(RuleGuards::InitialBalance(), 2), " ", ccy);
   Print("[DIAG]   DailyLossOK(", DoubleToString(InpMaxDailyLossPct, 1), "%) : ", YesNo(dailyOK));
   Print("[DIAG]   DrawdownOK(", DoubleToString(InpMaxDrawdownPct, 1), "%)  : ", YesNo(ddOK));
   Print("[DIAG]   SpreadOK(", DoubleToString(InpMaxSpreadPoints, 0), "pts)  : ", YesNo(sprdOK));
   Print("[DIAG]   >> Would the EA be clear to trade this tick? ",
         YesNo(dailyOK && ddOK && sprdOK));

   Print("[DIAG] ===== END - no orders were placed =====");
}
//+------------------------------------------------------------------+
