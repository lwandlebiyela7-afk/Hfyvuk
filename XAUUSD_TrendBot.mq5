//+------------------------------------------------------------------+
//| XAUUSD_TrendBot.mq5                                              |
//| Educational demo EA: EMA trend + pullback, ATR SL, fixed-R TP    |
//| Test on demo. No strategy guarantees profits.                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "XAUUSD M15 trend-following demo EA with risk controls"

#include <Trade/Trade.mqh>
CTrade trade;

input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M15;
input int FastEMAPeriod = 50;
input int SlowEMAPeriod = 200;
input int ATRPeriod = 14;
input double RiskPercent = 0.5;          // Risk per trade (% of equity)
input double ATRStopMultiplier = 1.5;
input double RewardRiskRatio = 2.0;      // TP distance = SL distance * this
input double MaxDailyLossPercent = 2.0;  // Stop opening trades after this daily equity loss
input int MaxSpreadPoints = 500;         // Broker points; verify for your XAUUSD symbol
input ulong MagicNumber = 18102026;
input bool AllowNewTrades = true;

int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;
int atrHandle  = INVALID_HANDLE;
datetime lastBarTime = 0;
int trackedDay = -1;
double dayStartEquity = 0.0;
bool dailyStopReached = false;

// Return true if this EA already has a position on the current symbol.
bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionSelectByTicket(ticket))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
         if(sym == _Symbol && magic == MagicNumber)
            return true;
      }
   }
   return false;
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, SignalTimeframe, 0);
   if(t == 0) return false;
   if(t != lastBarTime)
   {
      lastBarTime = t;
      return true;
   }
   return false;
}

void RefreshDailyGuard()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(now.day_of_year != trackedDay)
   {
      trackedDay = now.day_of_year;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      dailyStopReached = false;
   }

   if(dayStartEquity > 0.0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double lossPercent = 100.0 * (dayStartEquity - equity) / dayStartEquity;
      if(lossPercent >= MaxDailyLossPercent)
         dailyStopReached = true;
   }
}

double NormalizeVolumeDown(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0 || minLot <= 0.0) return 0.0;
   lots = MathMin(lots, maxLot);
   lots = MathFloor(lots / step) * step;
   lots = NormalizeDouble(lots, 8);

   if(lots < minLot) return 0.0;
   return lots;
}

double CalculateLots(double stopDistancePrice)
{
   if(stopDistancePrice <= 0.0) return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * RiskPercent / 100.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0 || riskMoney <= 0.0)
      return 0.0;

   double lossPerLot = (stopDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0) return 0.0;

   return NormalizeVolumeDown(riskMoney / lossPerLot);
}

bool ReadValue(int handle, int shift, double &value)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
      return false;
   value = buffer[0];
   return true;
}

void CheckForEntry()
{
   if(!AllowNewTrades || dailyStopReached || HasOurPosition())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return;

   double spreadPoints = (tick.ask - tick.bid) / _Point;
   if(spreadPoints > MaxSpreadPoints)
   {
      Print("Entry skipped: spread too high (", DoubleToString(spreadPoints, 1), " points).");
      return;
   }

   // Read only completed candles/indicator values (shifts 1 and 2).
   double fast1, fast2, slow1, atr1;
   if(!ReadValue(fastHandle, 1, fast1) ||
      !ReadValue(fastHandle, 2, fast2) ||
      !ReadValue(slowHandle, 1, slow1) ||
      !ReadValue(atrHandle, 1, atr1))
      return;

   if(atr1 <= 0.0) return;

   double open1  = iOpen(_Symbol, SignalTimeframe, 1);
   double close1 = iClose(_Symbol, SignalTimeframe, 1);
   double low1   = iLow(_Symbol, SignalTimeframe, 1);
   double high1  = iHigh(_Symbol, SignalTimeframe, 1);
   double low2   = iLow(_Symbol, SignalTimeframe, 2);
   double high2  = iHigh(_Symbol, SignalTimeframe, 2);

   if(open1 == 0 || close1 == 0 || low1 == 0 || high1 == 0 || low2 == 0 || high2 == 0)
      return;

   // Trend direction is determined by EMA 50 versus EMA 200.
   // Entry requires a pullback near the fast EMA followed by a candle
   // closing back in the direction of the trend.
   bool bullishTrend = fast1 > slow1;
   bool bearishTrend = fast1 < slow1;
   double pullbackBand = atr1 * 0.15;

   bool buySignal = bullishTrend &&
                    low2 <= fast2 + pullbackBand &&
                    close1 > open1 &&
                    close1 > fast1;

   bool sellSignal = bearishTrend &&
                     high2 >= fast2 - pullbackBand &&
                     close1 < open1 &&
                     close1 < fast1;

   if(!buySignal && !sellSignal) return;

   double stopDistance = atr1 * ATRStopMultiplier;
   int stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minimumStop = stopsLevelPoints * _Point;
   if(stopDistance < minimumStop)
      stopDistance = minimumStop + 2.0 * _Point;

   double lots = CalculateLots(stopDistance);
   if(lots <= 0.0)
   {
      Print("Entry skipped: calculated volume is below broker minimum or symbol tick values are unavailable.");
      return;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool sent = false;
   if(buySignal)
   {
      double sl = NormalizeDouble(tick.ask - stopDistance, _Digits);
      double tp = NormalizeDouble(tick.ask + stopDistance * RewardRiskRatio, _Digits);
      sent = trade.Buy(lots, _Symbol, 0.0, sl, tp, "XAU TrendBot BUY");
   }
   else if(sellSignal)
   {
      double sl = NormalizeDouble(tick.bid + stopDistance, _Digits);
      double tp = NormalizeDouble(tick.bid - stopDistance * RewardRiskRatio, _Digits);
      sent = trade.Sell(lots, _Symbol, 0.0, sl, tp, "XAU TrendBot SELL");
   }

   if(sent)
      Print("Order request accepted. Check Trade tab and Journal for final server result. Lots=", DoubleToString(lots, 2));
   else
      Print("Order failed. Retcode=", trade.ResultRetcode(), " / ", trade.ResultRetcodeDescription());
}

int OnInit()
{
   if(RiskPercent <= 0.0 || RiskPercent > 1.0 ||
      MaxDailyLossPercent <= 0.0 ||
      ATRStopMultiplier <= 0.0 || RewardRiskRatio <= 0.0)
   {
      Print("Invalid inputs. For this starter EA, RiskPercent must be > 0 and <= 1.");
      return INIT_PARAMETERS_INCORRECT;
   }

   fastHandle = iMA(_Symbol, SignalTimeframe, FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowHandle = iMA(_Symbol, SignalTimeframe, SlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle  = iATR(_Symbol, SignalTimeframe, ATRPeriod);

   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Could not create indicator handles.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   RefreshDailyGuard();
   lastBarTime = iTime(_Symbol, SignalTimeframe, 0);
   Print("XAUUSD TrendBot initialized. Demo testing only; verify the chart symbol and settings.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(atrHandle  != INVALID_HANDLE) IndicatorRelease(atrHandle);
}

void OnTick()
{
   RefreshDailyGuard();
   if(IsNewBar())
      CheckForEntry();
}
