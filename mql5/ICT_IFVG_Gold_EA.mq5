//+------------------------------------------------------------------+
//|                                           ICT_IFVG_Gold_EA.mq5   |
//|                    Expert Advisor: ICT Inversion Fair Value Gap   |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright "Quant Trading"
#property link      "https://github.com/amfitrite/Gold-Tester"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- INPUT PARAMETER
input group "=== MONEY MANAGEMENT ($10.000 Default) ==="
input double   InpRiskPercent          = 1.0;       // Resiko per Trade (%)
input double   InpRewardRiskRatio      = 2.0;       // Target Reward:Risk (RR)
input double   InpFixedLotFallback     = 0.01;      // Minimal / Fallback Lot Size

input group "=== STRATEGI ICT INVERSION FVG ==="
input double   InpMinFVGPoints         = 0.50;      // Minimal Lebar FVG (Price Points)
input double   InpSLBufferPoints       = 0.50;      // Extra Buffer untuk Stop Loss
input int      InpPullbackWindow       = 12;        // Maksimal Lilin Menunggu Retest
input int      InpMaxLookbackBars      = 200;       // Lilin yang di-scan

input group "=== FILTER TREN EMA ==="
input bool     InpUseEMATrend          = true;      // Aktifkan Filter Tren EMA
input int      InpFastEMAPeriod        = 20;        // Periode Fast EMA
input int      InpSlowEMAPeriod        = 50;        // Periode Slow EMA

input group "=== PENGATURAN EKSEKUSI ==="
input ulong    InpMagicNumber          = 888777;    // Magic Number EA
input string   InpTradeComment         = "ICT_IFVG"; // Komentar Order
input int      InpSlippagePoints       = 30;        // Slippage Maksimal (Points)

//--- STRUCT UNTUK ZONA INVERSE FVG
struct IFVGZone
{
   double   top;
   double   bottom;
   int      polarity;      // +1 = Long Zone (Support), -1 = Short Zone (Resistance)
   datetime violatedTime;
   int      violatedBarShift;
   bool     isActive;
};

//--- GLOBAL VARIABLES
CTrade         ExtTrade;
int            ExtHandleFastEMA = INVALID_HANDLE;
int            ExtHandleSlowEMA = INVALID_HANDLE;
datetime       ExtLastBarTime   = 0;
IFVGZone       ExtZones[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpSlippagePoints);

   if(InpUseEMATrend)
   {
      ExtHandleFastEMA = iMA(_Symbol, _Period, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      ExtHandleSlowEMA = iMA(_Symbol, _Period, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(ExtHandleFastEMA == INVALID_HANDLE || ExtHandleSlowEMA == INVALID_HANDLE)
      {
         Print("Gagal membuat handle EMA! Error: ", GetLastError());
         return INIT_FAILED;
      }
   }

   ArrayResize(ExtZones, 0);
   Print("ICT IFVG EA Berhasil Dimuat. MagicNumber: ", InpMagicNumber);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ExtHandleFastEMA != INVALID_HANDLE) IndicatorRelease(ExtHandleFastEMA);
   if(ExtHandleSlowEMA != INVALID_HANDLE) IndicatorRelease(ExtHandleSlowEMA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Hanya jalankan analisa pada pembukaan candle baru (Anti-Repaint)
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == ExtLastBarTime)
      return;

   ExtLastBarTime = currentBarTime;

   if(HasOpenPosition())
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, InpMaxLookbackBars, rates);
   if(copied < 10) return;

   ScanIFVGZones(rates, copied);

   int trendDirection = 0;
   if(InpUseEMATrend)
   {
      double fastEMA[1], slowEMA[1];
      CopyBuffer(ExtHandleFastEMA, 0, 1, 1, fastEMA);
      CopyBuffer(ExtHandleSlowEMA, 0, 1, 1, slowEMA);

      if(fastEMA[0] > slowEMA[0])
         trendDirection = 1;
      else if(fastEMA[0] < slowEMA[0])
         trendDirection = -1;
   }
   else
   {
      trendDirection = 999;
   }

   CheckForEntrySignals(rates, trendDirection);
}

//+------------------------------------------------------------------+
//| Scan Candlestick untuk Mendeteksi FVG yang Tembus (Inversion)   |
//+------------------------------------------------------------------+
void ScanIFVGZones(const MqlRates &rates[], int totalBars)
{
   ArrayResize(ExtZones, 0);

   for(int i = totalBars - 3; i >= 1; i--)
   {
      double c1_high = rates[i+2].high;
      double c1_low  = rates[i+2].low;
      double c3_high = rates[i].high;
      double c3_low  = rates[i].low;

      if((c3_low - c1_high) >= InpMinFVGPoints)
      {
         double top = c3_low;
         double bottom = c1_high;

         for(int j = i - 1; j >= 1; j--)
         {
            if(rates[j].close < bottom)
            {
               AddZone(top, bottom, -1, rates[j].time, j);
               break;
            }
         }
      }

      if((c1_low - c3_high) >= InpMinFVGPoints)
      {
         double top = c1_low;
         double bottom = c3_high;

         for(int j = i - 1; j >= 1; j--)
         {
            if(rates[j].close > top)
            {
               AddZone(top, bottom, +1, rates[j].time, j);
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Tambahkan Zona Inversion FVG ke Array                           |
//+------------------------------------------------------------------+
void AddZone(double top, double bottom, int polarity, datetime vTime, int vShift)
{
   int size = ArraySize(ExtZones);
   ArrayResize(ExtZones, size + 1);
   ExtZones[size].top = top;
   ExtZones[size].bottom = bottom;
   ExtZones[size].polarity = polarity;
   ExtZones[size].violatedTime = vTime;
   ExtZones[size].violatedBarShift = vShift;
   ExtZones[size].isActive = true;
}

//+------------------------------------------------------------------+
//| Periksa Retest Lilin Terkini pada Zona IFVG                      |
//+------------------------------------------------------------------+
void CheckForEntrySignals(const MqlRates &rates[], int trendDirection)
{
   int totalZones = ArraySize(ExtZones);
   if(totalZones == 0) return;

   double bar1_high = rates[1].high;
   double bar1_low  = rates[1].low;
   double bar1_close = rates[1].close;

   for(int i = totalZones - 1; i >= 0; i--)
   {
      if(!ExtZones[i].isActive) continue;

      int barsSinceViolation = ExtZones[i].violatedBarShift - 1;
      if(barsSinceViolation <= 0 || barsSinceViolation > InpPullbackWindow)
         continue;

      if(ExtZones[i].polarity == 1 && (trendDirection == 1 || trendDirection == 999))
      {
         if(bar1_low <= ExtZones[i].top && bar1_close >= ExtZones[i].top)
         {
            double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double slPrice    = NormalizeDouble(ExtZones[i].bottom - InpSLBufferPoints, _Digits);
            double riskDist   = entryPrice - slPrice;

            if(riskDist > 0)
            {
               double tpPrice = NormalizeDouble(entryPrice + (riskDist * InpRewardRiskRatio), _Digits);
               double lots    = CalculateLotSize(riskDist);

               if(ExtTrade.Buy(lots, _Symbol, entryPrice, slPrice, tpPrice, InpTradeComment))
               {
                  PrintFormat("BUY IFVG Executed! Lots: %.2f | SL: %.2f | TP: %.2f", lots, slPrice, tpPrice);
                  ExtZones[i].isActive = false;
                  return;
               }
            }
         }
      }

      if(ExtZones[i].polarity == -1 && (trendDirection == -1 || trendDirection == 999))
      {
         if(bar1_high >= ExtZones[i].bottom && bar1_close <= ExtZones[i].bottom)
         {
            double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double slPrice    = NormalizeDouble(ExtZones[i].top + InpSLBufferPoints, _Digits);
            double riskDist   = slPrice - entryPrice;

            if(riskDist > 0)
            {
               double tpPrice = NormalizeDouble(entryPrice - (riskDist * InpRewardRiskRatio), _Digits);
               double lots    = CalculateLotSize(riskDist);

               if(ExtTrade.Sell(lots, _Symbol, entryPrice, slPrice, tpPrice, InpTradeComment))
               {
                  PrintFormat("SELL IFVG Executed! Lots: %.2f | SL: %.2f | TP: %.2f", lots, slPrice, tpPrice);
                  ExtZones[i].isActive = false;
                  return;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Hitung Lot Berdasarkan Resiko 1% dari Saldo (Prop-Firm Standard) |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney   = balance * (InpRiskPercent / 100.0);
   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double minLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(slDistancePrice <= 0 || tickSize <= 0 || tickValue <= 0)
      return InpFixedLotFallback;

   double pointsAtRisk = slDistancePrice / tickSize;
   double rawLots      = riskMoney / (pointsAtRisk * tickValue);

   double lots = MathFloor(rawLots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Cek Posisi Aktif Milik EA                                        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return true;
      }
   }
   return false;
}
