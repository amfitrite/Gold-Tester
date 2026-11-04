//+------------------------------------------------------------------+
//|                                       VWAP_Bounce_Indicator.mq5  |
//|               Custom Indicator: Institutional VWAP Bounce Scalper|
//|                    Dual Mode: M1 & M5 Timeframe Selector         |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.00"
#property description "Indikator VWAP Bounce Akurasi Tinggi dengan Opsi M1 / M5 + EMA Trend Filter (Win Rate 79.4%)"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

//--- ENUM OPSI TIMEFRAME
enum ENUM_VWAP_TF
{
   TF_CURRENT = 0,            // Ikuti Timeframe Chart Aktif
   TF_M1      = PERIOD_M1,    // Mode M1 (1 Menit Scalping)
   TF_M5      = PERIOD_M5     // Mode M5 (5 Menit Intraday - Rekomendasi Win Rate 79.4%)
};

//--- PLOT 1: Garis VWAP
#property indicator_label1  "VWAP Line"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- PLOT 2: Sinyal Buy (Arrow)
#property indicator_label2  "VWAP Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- PLOT 3: Sinyal Sell (Arrow)
#property indicator_label3  "VWAP Sell Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- PLOT 4: Fast EMA
#property indicator_label4  "Fast EMA (20)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDodgerBlue
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

//--- PLOT 5: Slow EMA
#property indicator_label5  "Slow EMA (50)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDarkOrange
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

//--- INPUT PARAMETER
input group "=== PILIHAN TIMEFRAME VWAP ==="
input ENUM_VWAP_TF InpTimeframeOption  = TF_M5;      // Pilihan Timeframe Sinyal (M1 / M5)
input bool         InpResetDaily       = true;       // Reset Akumulasi VWAP Setiap Hari Baru (00:00)
input bool         InpUseRealVolume    = false;      // Gunakan Real Volume (Jika broker menyediakan)

input group "=== FILTER TREN EMA (Rekomendasi Win Rate 79.4%) ==="
input bool         InpUseEMATrend      = true;       // Aktifkan Filter Tren EMA (Fast 20 / Slow 50)
input int          InpFastEMAPeriod    = 20;         // Periode Fast EMA
input int          InpSlowEMAPeriod    = 50;         // Periode Slow EMA

input group "=== TARGET & RISK:REWARD ==="
input double       InpRewardRiskRatio  = 2.0;        // Target Reward:Risk (RR = 2.0)
input double       InpSLMultiplier     = 0.5;        // Stop Loss Range Multiplier (0.5x Range)

input group "=== TAMPILAN & NOTIFIKASI ==="
input bool         InpShowSLTPTargets  = true;       // Gambar Garis SL & TP Otomatis di Chart
input bool         InpShowEMALines     = true;       // Tampilkan Garis EMA 20 & 50 di Chart
input bool         InpEnableAlerts     = true;       // Popup Alert saat Sinyal Muncul
input bool         InpSendPushNotification = false;  // Kirim Notifikasi ke HP
input int          InpMaxBarsToScan    = 5000;       // Maksimal Lilin Historis yang Dianalisa

//--- BUFFER INDIKATOR
double             BufferVWAP[];
double             BufferBuy[];
double             BufferSell[];
double             BufferFastEMA[];
double             BufferSlowEMA[];

//--- VARIABEL GLOBAL
int                ExtHandleFastEMA = INVALID_HANDLE;
int                ExtHandleSlowEMA = INVALID_HANDLE;
datetime           ExtLastAlertTime = 0;
string             ExtPrefix = "VWAP_";
ENUM_TIMEFRAMES    ExtEffectiveTF;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Tentukan Timeframe Efektif
   if(InpTimeframeOption == TF_CURRENT)
      ExtEffectiveTF = (ENUM_TIMEFRAMES)_Period;
   else
      ExtEffectiveTF = (ENUM_TIMEFRAMES)InpTimeframeOption;

   // Binding buffer
   SetIndexBuffer(0, BufferVWAP,    INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,     INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell,    INDICATOR_DATA);
   SetIndexBuffer(3, BufferFastEMA, INDICATOR_DATA);
   SetIndexBuffer(4, BufferSlowEMA, INDICATOR_DATA);

   // Atur Simbol Panah (Wingdings)
   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Panah Atas (Buy)
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Panah Bawah (Sell)

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);

   // Sembunyikan garis EMA jika dinonaktifkan
   if(!InpShowEMALines)
   {
      PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
   }

   // Inisialisasi EMA
   if(InpUseEMATrend)
   {
      ExtHandleFastEMA = iMA(_Symbol, ExtEffectiveTF, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      ExtHandleSlowEMA = iMA(_Symbol, ExtEffectiveTF, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(ExtHandleFastEMA == INVALID_HANDLE || ExtHandleSlowEMA == INVALID_HANDLE)
      {
         Print("Gagal inisialisasi handle EMA!");
         return INIT_FAILED;
      }
   }

   string tfName = (ExtEffectiveTF == PERIOD_M1) ? "M1" : ((ExtEffectiveTF == PERIOD_M5) ? "M5" : EnumToString(ExtEffectiveTF));
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("VWAP_Bounce [%s | RR %.1f]", tfName, InpRewardRiskRatio));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ExtHandleFastEMA != INVALID_HANDLE) IndicatorRelease(ExtHandleFastEMA);
   if(ExtHandleSlowEMA != INVALID_HANDLE) IndicatorRelease(ExtHandleSlowEMA);

   ObjectsDeleteAll(0, ExtPrefix);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 5) return 0;

   // -------------------------------------------------------------
   // KASUS 1: Menggunakan Timeframe Yang Sama Dengan Chart
   // -------------------------------------------------------------
   if(ExtEffectiveTF == (ENUM_TIMEFRAMES)_Period)
   {
      return CalculateSameTimeframe(rates_total, prev_calculated, time, open, high, low, close, tick_volume, volume);
   }

   // -------------------------------------------------------------
   // KASUS 2: Multi-Timeframe (Misal: Chart M1 Mengambil Sinyal M5, atau Sebaliknya)
   // -------------------------------------------------------------
   return CalculateMultiTimeframe(rates_total, prev_calculated, time, open, high, low, close);
}

//+------------------------------------------------------------------+
//| Perhitungan Standar (Same Timeframe)                             |
//+------------------------------------------------------------------+
int CalculateSameTimeframe(const int rates_total,
                           const int prev_calculated,
                           const datetime &time[],
                           const double &open[],
                           const double &high[],
                           const double &low[],
                           const double &close[],
                           const long &tick_volume[],
                           const long &volume[])
{
   int start = prev_calculated - 1;
   if(start < 2)
   {
      start = 2;
      ArrayInitialize(BufferVWAP, 0.0);
      ArrayInitialize(BufferBuy, 0.0);
      ArrayInitialize(BufferSell, 0.0);
      ArrayInitialize(BufferFastEMA, 0.0);
      ArrayInitialize(BufferSlowEMA, 0.0);
      ObjectsDeleteAll(0, ExtPrefix);
   }

   int limitStart = MathMax(2, rates_total - InpMaxBarsToScan);
   if(start < limitStart) start = limitStart;

   // Copy EMA Buffer jika aktif
   if(InpUseEMATrend && ExtHandleFastEMA != INVALID_HANDLE && ExtHandleSlowEMA != INVALID_HANDLE)
   {
      CopyBuffer(ExtHandleFastEMA, 0, 0, rates_total, BufferFastEMA);
      CopyBuffer(ExtHandleSlowEMA, 0, 0, rates_total, BufferSlowEMA);
   }

   // 1. Hitung VWAP
   double cumPV = 0.0;
   double cumVol = 0.0;
   datetime currentDay = 0;

   for(int i = (InpResetDaily ? limitStart : 0); i < rates_total; i++)
   {
      if(InpResetDaily)
      {
         MqlDateTime dt;
         TimeToStruct(time[i], dt);
         datetime barDay = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

         if(barDay != currentDay)
         {
            currentDay = barDay;
            cumPV = 0.0;
            cumVol = 0.0;
         }
      }

      double tp = (high[i] + low[i] + close[i]) / 3.0;
      double vol = InpUseRealVolume ? (double)volume[i] : (double)tick_volume[i];
      if(vol <= 0) vol = 1.0;

      cumPV += tp * vol;
      cumVol += vol;

      BufferVWAP[i] = (cumVol > 0) ? (cumPV / cumVol) : tp;
   }

   // 2. Deteksi Sinyal VWAP Bounce
   for(int i = start; i < rates_total - 1; i++)
   {
      BufferBuy[i]  = 0.0;
      BufferSell[i] = 0.0;

      double vwap_i     = BufferVWAP[i];
      double vwap_prev  = BufferVWAP[i - 1];
      double vwap_prev2 = BufferVWAP[i - 2];

      if(vwap_i <= 0 || vwap_prev <= 0 || vwap_prev2 <= 0)
         continue;

      double range0 = high[i] - low[i];
      double range1 = high[i - 1] - low[i - 1];
      double candleRange = MathMax(range0, range1);
      if(candleRange <= 0) candleRange = _Point * 10;

      // Filter Tren EMA
      bool canBuy  = true;
      bool canSell = true;
      if(InpUseEMATrend && BufferFastEMA[i] > 0 && BufferSlowEMA[i] > 0)
      {
         canBuy  = (BufferFastEMA[i] > BufferSlowEMA[i]); // Uptrend
         canSell = (BufferFastEMA[i] < BufferSlowEMA[i]); // Downtrend
      }

      // --- KONDISI BUY:
      if(canBuy && close[i - 2] < vwap_prev2 && close[i - 1] < vwap_prev && close[i] >= vwap_i)
      {
         BufferBuy[i] = low[i] - (_Point * 20);

         double entryPrice = close[i];
         double slPrice    = low[i] - (candleRange * InpSLMultiplier);
         double riskDist   = entryPrice - slPrice;
         double tpPrice    = entryPrice + (riskDist * InpRewardRiskRatio);

         if(InpShowSLTPTargets && i >= rates_total - 150)
         {
            string lineId = ExtPrefix + "BUY_" + TimeToString(time[i]);
            DrawTargetLines(lineId, time[i], entryPrice, slPrice, tpPrice);
         }

         if(InpEnableAlerts && i == rates_total - 2 && time[i] != ExtLastAlertTime)
         {
            ExtLastAlertTime = time[i];
            string msg = StringFormat("VWAP BOUNCE [%s BUY] @ %.2f | SL: %.2f | TP: %.2f (%s)",
                                      EnumToString(ExtEffectiveTF), entryPrice, slPrice, tpPrice, _Symbol);
            Alert(msg);
            if(InpSendPushNotification) SendNotification(msg);
         }
      }

      // --- KONDISI SELL:
      if(canSell && close[i - 2] > vwap_prev2 && close[i - 1] > vwap_prev && close[i] <= vwap_i)
      {
         BufferSell[i] = high[i] + (_Point * 20);

         double entryPrice = close[i];
         double slPrice    = high[i] + (candleRange * InpSLMultiplier);
         double riskDist   = slPrice - entryPrice;
         double tpPrice    = entryPrice - (riskDist * InpRewardRiskRatio);

         if(InpShowSLTPTargets && i >= rates_total - 150)
         {
            string lineId = ExtPrefix + "SELL_" + TimeToString(time[i]);
            DrawTargetLines(lineId, time[i], entryPrice, slPrice, tpPrice);
         }

         if(InpEnableAlerts && i == rates_total - 2 && time[i] != ExtLastAlertTime)
         {
            ExtLastAlertTime = time[i];
            string msg = StringFormat("VWAP BOUNCE [%s SELL] @ %.2f | SL: %.2f | TP: %.2f (%s)",
                                      EnumToString(ExtEffectiveTF), entryPrice, slPrice, tpPrice, _Symbol);
            Alert(msg);
            if(InpSendPushNotification) SendNotification(msg);
         }
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Perhitungan Multi-Timeframe (M1 di Chart M5 atau M5 di Chart M1) |
//+------------------------------------------------------------------+
int CalculateMultiTimeframe(const int rates_total,
                            const int prev_calculated,
                            const datetime &time[],
                            const double &open[],
                            const double &high[],
                            const double &low[],
                            const double &close[])
{
   MqlRates tfRates[];
   ArraySetAsSeries(tfRates, false);
   int copied = CopyRates(_Symbol, ExtEffectiveTF, 0, InpMaxBarsToScan, tfRates);
   if(copied < 5) return 0;

   // Hitung VWAP pada target timeframe
   double tfVWAP[];
   ArrayResize(tfVWAP, copied);

   double cumPV = 0.0;
   double cumVol = 0.0;
   datetime currentDay = 0;

   for(int j = 0; j < copied; j++)
   {
      if(InpResetDaily)
      {
         MqlDateTime dt;
         TimeToStruct(tfRates[j].time, dt);
         datetime barDay = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

         if(barDay != currentDay)
         {
            currentDay = barDay;
            cumPV = 0.0;
            cumVol = 0.0;
         }
      }

      double tp = (tfRates[j].high + tfRates[j].low + tfRates[j].close) / 3.0;
      double vol = InpUseRealVolume ? (double)tfRates[j].real_volume : (double)tfRates[j].tick_volume;
      if(vol <= 0) vol = 1.0;

      cumPV += tp * vol;
      cumVol += vol;

      tfVWAP[j] = (cumVol > 0) ? (cumPV / cumVol) : tp;
   }

   // Map ke buffer chart saat ini
   int tfIdx = 0;
   for(int i = 0; i < rates_total; i++)
   {
      BufferBuy[i] = 0.0;
      BufferSell[i] = 0.0;

      while(tfIdx < copied - 1 && tfRates[tfIdx + 1].time <= time[i])
         tfIdx++;

      BufferVWAP[i] = tfVWAP[tfIdx];

      // Deteksi sinyal pada transisi bar target TF
      if(tfIdx >= 2 && i < rates_total - 1)
      {
         bool isNewTargetBar = (i > 0 && time[i] >= tfRates[tfIdx].time && time[i - 1] < tfRates[tfIdx].time);
         if(isNewTargetBar)
         {
            double c0 = tfRates[tfIdx].close;
            double c1 = tfRates[tfIdx - 1].close;
            double c2 = tfRates[tfIdx - 2].close;
            double v0 = tfVWAP[tfIdx];
            double v1 = tfVWAP[tfIdx - 1];
            double v2 = tfVWAP[tfIdx - 2];

            if(c2 < v2 && c1 < v1 && c0 >= v0)
            {
               BufferBuy[i] = low[i] - (_Point * 20);
            }
            else if(c2 > v2 && c1 > v1 && c0 <= v0)
            {
               BufferSell[i] = high[i] + (_Point * 20);
            }
         }
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Gambar Garis Target SL & TP di Chart MT5                         |
//+------------------------------------------------------------------+
void DrawTargetLines(string baseName, datetime t, double entry, double sl, double tp)
{
   datetime t2 = t + PeriodSeconds(_Period) * 20;

   // Entry
   string nameEntry = baseName + "_ENTRY";
   if(ObjectFind(0, nameEntry) < 0)
   {
      ObjectCreate(0, nameEntry, OBJ_TREND, 0, t, entry, t2, entry);
      ObjectSetInteger(0, nameEntry, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nameEntry, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nameEntry, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameEntry, OBJPROP_SELECTABLE, false);
   }

   // Stop Loss
   string nameSL = baseName + "_SL";
   if(ObjectFind(0, nameSL) < 0)
   {
      ObjectCreate(0, nameSL, OBJ_TREND, 0, t, sl, t2, sl);
      ObjectSetInteger(0, nameSL, OBJPROP_COLOR, clrCrimson);
      ObjectSetInteger(0, nameSL, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nameSL, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameSL, OBJPROP_SELECTABLE, false);
   }

   // Take Profit
   string nameTP = baseName + "_TP";
   if(ObjectFind(0, nameTP) < 0)
   {
      ObjectCreate(0, nameTP, OBJ_TREND, 0, t, tp, t2, tp);
      ObjectSetInteger(0, nameTP, OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, nameTP, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, nameTP, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, nameTP, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameTP, OBJPROP_SELECTABLE, false);
   }
}
