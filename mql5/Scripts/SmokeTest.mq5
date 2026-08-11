//+------------------------------------------------------------------+
//|                                                     SmokeTest.mq5 |
//|  Proves the execution chain end to end: open one minimum-size     |
//|  position and close it immediately. Measures what it actually     |
//|  cost. This is the ONLY file in this repo that sends orders.      |
//|                                                                   |
//|  It is a Script, not part of AgenticEA, on purpose. Order-sending |
//|  code kept inside the EA is order-sending code that can run       |
//|  without anyone deciding it should.                               |
//+------------------------------------------------------------------+
#property copyright "aigentforce.io"
#property version   "1.00"
#property strict
#property script_show_inputs

input bool   InpDemoOnly       = true;   // refuse to run on a live account
input double InpMaxSpreadPts   = 200;    // refuse if spread is dislocated right now
input int    InpDeviationPts   = 50;     // max slippage accepted, in points
input int    InpCloseRetries   = 3;      // attempts to close before shouting
input string InpOutFile        = "AgenticEA_smoketest.txt";

#define SMOKE_MAGIC 20260811

string g_report = "";

void Log(string s) { Print("[SMOKE] ", s); g_report += s + "\r\n"; }

//+------------------------------------------------------------------+
string RetcodeText(uint rc)
{
   switch(rc)
   {
      case TRADE_RETCODE_DONE:            return "DONE (filled)";
      case TRADE_RETCODE_DONE_PARTIAL:    return "DONE_PARTIAL (partially filled)";
      case TRADE_RETCODE_PLACED:          return "PLACED (accepted, not yet filled)";
      case TRADE_RETCODE_REQUOTE:         return "REQUOTE (price moved)";
      case TRADE_RETCODE_REJECT:          return "REJECT (broker refused)";
      case TRADE_RETCODE_INVALID_FILL:    return "INVALID_FILL (wrong filling mode — the exact failure we were watching for)";
      case TRADE_RETCODE_INVALID_VOLUME:  return "INVALID_VOLUME (lot size not allowed)";
      case TRADE_RETCODE_INVALID_PRICE:   return "INVALID_PRICE";
      case TRADE_RETCODE_INVALID_STOPS:   return "INVALID_STOPS (SL/TP too close to price)";
      case TRADE_RETCODE_NO_MONEY:        return "NO_MONEY (not enough free margin)";
      case TRADE_RETCODE_MARKET_CLOSED:   return "MARKET_CLOSED";
      case TRADE_RETCODE_TRADE_DISABLED:  return "TRADE_DISABLED";
      case TRADE_RETCODE_PRICE_OFF:       return "PRICE_OFF (no quotes to trade against)";
      case TRADE_RETCODE_CONNECTION:      return "CONNECTION (no link to the trade server)";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "TOO_MANY_REQUESTS";
      case TRADE_RETCODE_FROZEN:          return "FROZEN (position locked by the broker)";
      case TRADE_RETCODE_LIMIT_VOLUME:    return "LIMIT_VOLUME (account volume cap)";
   }
   return "code " + IntegerToString(rc);
}

//+------------------------------------------------------------------+
//| Same resolution logic as the EA. Deliberately duplicated rather   |
//| than shared: if the two ever disagree, this test should fail      |
//| loudly instead of quietly agreeing with a bug.                    |
//+------------------------------------------------------------------+
bool ResolveFillingMode(string sym, ENUM_ORDER_TYPE_FILLING &mode, string &label)
{
   long flags = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);

   if((flags & SYMBOL_FILLING_IOC) != 0) { mode = ORDER_FILLING_IOC; label = "IOC";    return true; }
   if((flags & SYMBOL_FILLING_FOK) != 0) { mode = ORDER_FILLING_FOK; label = "FOK";    return true; }

   ENUM_SYMBOL_TRADE_EXECUTION exe =
      (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(sym, SYMBOL_TRADE_EXEMODE);
   if(exe == SYMBOL_TRADE_EXECUTION_MARKET || exe == SYMBOL_TRADE_EXECUTION_EXCHANGE)
   {
      mode = ORDER_FILLING_RETURN; label = "RETURN (nothing advertised; market execution)";
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Every reason to refuse, checked before anything is sent.          |
//+------------------------------------------------------------------+
bool PreflightOK(string sym, ENUM_ORDER_TYPE_FILLING &filling, string &fillLabel, double &lot)
{
   Log("--- PREFLIGHT ---");

   ENUM_ACCOUNT_TRADE_MODE acctMode =
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string acctText = (acctMode == ACCOUNT_TRADE_MODE_DEMO)    ? "DEMO"
                   : (acctMode == ACCOUNT_TRADE_MODE_CONTEST) ? "CONTEST" : "REAL";
   Log("Account " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
       " @ " + AccountInfoString(ACCOUNT_SERVER) + " is a " + acctText + " account.");

   if(InpDemoOnly && acctMode == ACCOUNT_TRADE_MODE_REAL)
   {
      Log("REFUSING: this is a REAL-money account and InpDemoOnly is on.");
      Log("If you genuinely mean to send a live order, turn InpDemoOnly off deliberately.");
      return false;
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   { Log("REFUSING: the Algo Trading button is OFF. Turn it green and re-run."); return false; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Log("REFUSING: this script was not permitted to trade. Tick 'Allow Algo Trading' in its dialog."); return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { Log("REFUSING: the broker has trading disabled on this account."); return false; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   { Log("REFUSING: the broker has automated trading disabled on this account."); return false; }
   Log("Permissions: all four switches ON.");

   ENUM_SYMBOL_TRADE_MODE tradeMode =
      (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
   if(tradeMode != SYMBOL_TRADE_MODE_FULL)
   {
      Log("REFUSING: " + sym + " is not in full-access trade mode right now (mode " +
          IntegerToString((int)tradeMode) + "). Usually this means the market is closed.");
      return false;
   }

   if(!ResolveFillingMode(sym, filling, fillLabel))
   { Log("REFUSING: no filling mode this broker accepts for " + sym + "."); return false; }
   Log("Filling mode resolved from the broker: " + fillLabel);

   MqlTick tick;
   if(!SymbolInfoTick(sym, tick) || tick.bid <= 0 || tick.ask <= 0)
   { Log("REFUSING: no live quote for " + sym + "."); return false; }

   double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
   double spread = (point > 0) ? (tick.ask - tick.bid) / point : 0;
   Log("Live quote: bid " + DoubleToString(tick.bid, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
       " / ask " + DoubleToString(tick.ask, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)) +
       " ; spread " + DoubleToString(spread, 1) + " points");
   if(spread > InpMaxSpreadPts)
   {
      Log("REFUSING: spread " + DoubleToString(spread, 1) + " exceeds the " +
          DoubleToString(InpMaxSpreadPts, 0) + "-point sanity limit. Not a good moment to test.");
      return false;
   }

   lot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double margin = 0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, lot, tick.ask, margin))
   { Log("REFUSING: could not calculate margin, error " + IntegerToString(GetLastError())); return false; }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   Log("Test size " + DoubleToString(lot, 2) + " lot needs " + DoubleToString(margin, 2) +
       " " + AccountInfoString(ACCOUNT_CURRENCY) + " of the " +
       DoubleToString(freeMargin, 2) + " free.");
   if(margin > freeMargin)
   { Log("REFUSING: not enough free margin for even the minimum size."); return false; }

   if(PositionsTotal() > 0)
      Log("NOTE: " + IntegerToString(PositionsTotal()) +
          " position(s) already open. This test only ever touches the one it opens itself.");

   Log("Preflight passed.");
   return true;
}

//+------------------------------------------------------------------+
//| Find the position this script opened, by magic number. Never      |
//| touches anything it did not open.                                 |
//+------------------------------------------------------------------+
ulong FindOwnPosition(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == sym &&
         PositionGetInteger(POSITION_MAGIC)  == SMOKE_MAGIC)
         return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
void OnStart()
{
   string sym = _Symbol;
   Log("=== EXECUTION SMOKE TEST — " + sym + " — " +
       TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " server ===");
   Log("Opens one minimum-size position and closes it immediately. Nothing is held.");

   ENUM_ORDER_TYPE_FILLING filling = ORDER_FILLING_IOC;
   string fillLabel = "";
   double lot       = 0.0;

   if(!PreflightOK(sym, filling, fillLabel, lot))
   {
      Log("=== ABORTED before sending anything. No order was placed. ===");
      WriteReport();
      return;
   }

   double equityBefore = AccountInfoDouble(ACCOUNT_EQUITY);
   int    digits       = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   //--- OPEN ------------------------------------------------------------
   Log("--- OPEN ---");
   MqlTradeRequest req; MqlTradeResult res;
   ZeroMemory(req); ZeroMemory(res);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = sym;
   req.volume       = lot;
   req.type         = ORDER_TYPE_BUY;
   req.price        = SymbolInfoDouble(sym, SYMBOL_ASK);
   req.deviation    = InpDeviationPts;
   req.type_filling = filling;
   req.magic        = SMOKE_MAGIC;
   req.comment      = "AgenticEA smoke test";

   double wanted = req.price;
   uint   t0     = GetTickCount();
   bool   sent   = OrderSend(req, res);
   uint   openMs = GetTickCount() - t0;

   Log("BUY " + DoubleToString(lot, 2) + " at market, asked " + DoubleToString(wanted, digits) +
       " -> " + RetcodeText(res.retcode) + " in " + IntegerToString(openMs) + " ms");

   if(!sent || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_DONE_PARTIAL))
   {
      Log("Broker comment: " + res.comment);
      if(res.retcode == TRADE_RETCODE_INVALID_FILL)
         Log("This is the filling-mode failure. The mode we resolved (" + fillLabel +
             ") is not what this broker actually accepts for " + sym + ".");
      Log("=== FAILED at open. Nothing is open. ===");
      WriteReport();
      return;
   }

   double filled = res.price;
   double slip   = (filled - wanted) / SymbolInfoDouble(sym, SYMBOL_POINT);
   Log("Filled at " + DoubleToString(filled, digits) + " (" +
       DoubleToString(slip, 1) + " points of slippage), volume " + DoubleToString(res.volume, 2));

   ulong ticket = FindOwnPosition(sym);
   if(ticket == 0)
   {
      Log("!! The order filled but no matching position is visible. CHECK THE TERMINAL MANUALLY.");
      WriteReport();
      return;
   }
   long posId = PositionGetInteger(POSITION_IDENTIFIER);

   //--- CLOSE -----------------------------------------------------------
   Log("--- CLOSE ---");
   bool closed = false;
   for(int attempt = 1; attempt <= InpCloseRetries && !closed; attempt++)
   {
      if(!PositionSelectByTicket(ticket)) { closed = true; break; }

      ZeroMemory(req); ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = sym;
      req.position     = ticket;
      req.volume       = PositionGetDouble(POSITION_VOLUME);
      req.type         = ORDER_TYPE_SELL;
      req.price        = SymbolInfoDouble(sym, SYMBOL_BID);
      req.deviation    = InpDeviationPts;
      req.type_filling = filling;
      req.magic        = SMOKE_MAGIC;
      req.comment      = "AgenticEA smoke test close";

      t0 = GetTickCount();
      sent = OrderSend(req, res);
      uint closeMs = GetTickCount() - t0;

      Log("Attempt " + IntegerToString(attempt) + ": SELL to close -> " +
          RetcodeText(res.retcode) + " in " + IntegerToString(closeMs) + " ms");

      if(sent && (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL))
      {
         Log("Closed at " + DoubleToString(res.price, digits));
         closed = true;
      }
      else
      {
         Log("Broker comment: " + res.comment);
         Sleep(500);
      }
   }

   if(!closed || PositionSelectByTicket(ticket))
   {
      Log("!! COULD NOT CLOSE. A " + DoubleToString(lot, 2) + " lot position on " + sym +
          " IS STILL OPEN (ticket " + IntegerToString((long)ticket) + ").");
      Log("!! Close it by hand in the Trade tab now. Do not leave it running.");
      Alert("SMOKE TEST: position ", ticket, " still open on ", sym, " — close it manually.");
      WriteReport();
      return;
   }

   //--- WHAT IT COST ----------------------------------------------------
   Log("--- COST OF THE ROUND TRIP ---");
   double commission = 0.0, swap = 0.0, profit = 0.0;
   if(HistorySelectByPosition(posId))
   {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         commission += HistoryDealGetDouble(deal, DEAL_COMMISSION);
         swap       += HistoryDealGetDouble(deal, DEAL_SWAP);
         profit     += HistoryDealGetDouble(deal, DEAL_PROFIT);
      }
   }
   string ccy = AccountInfoString(ACCOUNT_CURRENCY);
   Log("Gross P/L " + DoubleToString(profit, 2) + " " + ccy +
       " ; commission " + DoubleToString(commission, 2) +
       " ; swap " + DoubleToString(swap, 2));
   Log("Net " + DoubleToString(profit + commission + swap, 2) + " " + ccy +
       " — this is the true cost of entering and leaving at minimum size.");

   double equityAfter = AccountInfoDouble(ACCOUNT_EQUITY);
   Log("Equity " + DoubleToString(equityBefore, 2) + " -> " + DoubleToString(equityAfter, 2) +
       " " + ccy + " (change " + DoubleToString(equityAfter - equityBefore, 2) + ")");

   Log("=== PASS: order sent, filled, and closed. The execution chain works. ===");
   Log("Positions still open on this account: " + IntegerToString(PositionsTotal()));
   WriteReport();
}

//+------------------------------------------------------------------+
void WriteReport()
{
   int h = FileOpen(InpOutFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE)
   { Print("[SMOKE] could not write ", InpOutFile, ", error ", GetLastError()); return; }
   FileWriteString(h, g_report);
   FileClose(h);
   Print("[SMOKE] report written to MQL5/Files/", InpOutFile);
}
//+------------------------------------------------------------------+
