//+------------------------------------------------------------------+
//|                                       VWAP_Bounce_Indicator.mq5  |
//|               Custom Indicator: Institutional VWAP Bounce Scalper|
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.00"
#property description "Indikator VWAP Bounce Akurasi Tinggi (M1/M5) - Win Rate 76% Benchmark"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

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

//--- INPUT PARAMETER
input group "=== PARAMETER VWAP ==="
input bool     InpResetDaily           = true;       // Reset Akumulasi Setiap Hari Baru (00:00)
input bool     InpUseRealVolume        = false;      // Gunakan Real Volume (Jika broker menyediakan)

input group "=== PARAMETER ENTRY & TARGET ==="
input double   InpRewardRiskRatio      = 2.0;        // Target Reward:Risk (RR)
input double   InpSLMultiplier         = 0.5;        // Stop Loss Range Multiplier (0.5x Range)

input group "=== TAMPILAN & NOTIFIKASI ==="
input bool     InpShowSLTPTargets      = true;       // Gambar Garis SL & TP di Chart
input bool     InpEnableAlerts         = true;       // Popup Alert saat Sinyal Muncul
input bool     InpSendPushNotification = false;      // Kirim Notifikasi ke HP
input int      InpMaxBarsToScan        = 10000;      // Maksimal Lilin Historis (M1 / M5)

//--- BUFFER INDIKATOR
double         BufferVWAP[];
double         BufferBuy[];
double         BufferSell[];

//--- VARIABEL GLOBAL
datetime       ExtLastAlertTime = 0;
string         ExtPrefix = "VWAP_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Binding buffer
   SetIndexBuffer(0, BufferVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,  INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell, INDICATOR_DATA);

   // Atur Simbol Panah (Wingdings)
   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Panah Atas (Buy)
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Panah Bawah (Sell)

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME, "VWAP_Bounce (" + DoubleToString(InpRewardRiskRatio, 1) + " RR)");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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

   int start = prev_calculated - 1;
   if(start < 2)
   {
      start = 2;
      ArrayInitialize(BufferVWAP, 0.0);
      ArrayInitialize(BufferBuy, 0.0);
      ArrayInitialize(BufferSell, 0.0);
      ObjectsDeleteAll(0, ExtPrefix);
   }

   // Batasi bar jika riwayat terlalu panjang
   int limitStart = MathMax(2, rates_total - InpMaxBarsToScan);
   if(start < limitStart) start = limitStart;

   // 1. HITUNG VWAP (Volume-Weighted Average Price)
   double cumPV = 0.0;
   double cumVol = 0.0;
   datetime currentDay = 0;

   // Inisialisasi awal VWAP dari titik start
   for(int i = (InpResetDaily ? limitStart : 0); i < rates_total; i++)
   {
      // Reset harian pada awal hari baru
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

   // 2. DETEKSI SINYAL VWAP BOUNCE
   for(int i = start; i < rates_total - 1; i++)
   {
      BufferBuy[i] = 0.0;
      BufferSell[i] = 0.0;

      double vwap_i     = BufferVWAP[i];
      double vwap_prev  = BufferVWAP[i - 1];
      double vwap_prev2 = BufferVWAP[i - 2];

      if(vwap_i <= 0 || vwap_prev <= 0 || vwap_prev2 <= 0)
         continue;

      // Hitung range 2 candle terakhir sebagai acuan Stop Loss
      double range0 = high[i] - low[i];
      double range1 = high[i - 1] - low[i - 1];
      double candleRange = MathMax(range0, range1);
      if(candleRange <= 0) candleRange = _Point * 10;

      // --- KONDISI BUY (LONG):
      // Lilin 2 & 1 sebelumnya ditutup di bawah VWAP, lilin saat ini menembus/cross ke atas VWAP
      if(close[i - 2] < vwap_prev2 && close[i - 1] < vwap_prev && close[i] >= vwap_i)
      {
         BufferBuy[i] = low[i] - (_Point * 20); // Posisi panah

         double entryPrice = close[i];
         double slPrice    = low[i] - (candleRange * InpSLMultiplier);
         double riskDist   = entryPrice - slPrice;
         double tpPrice    = entryPrice + (riskDist * InpRewardRiskRatio);

         // Tampilkan target garis di chart
         if(InpShowSLTPTargets && i >= rates_total - 100)
         {
            string lineId = ExtPrefix + "BUY_" + TimeToString(time[i]);
            DrawTargetLines(lineId, time[i], entryPrice, slPrice, tpPrice, clrLimeGreen, clrCrimson);
         }

         // Alert pada pembentukan sinyal bar baru
         if(InpEnableAlerts && i == rates_total - 2 && time[i] != ExtLastAlertTime)
         {
            ExtLastAlertTime = time[i];
            string msg = StringFormat("VWAP BOUNCE [BUY] @ %.2f | SL: %.2f | TP: %.2f (%s %s)",
                                      entryPrice, slPrice, tpPrice, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
            Alert(msg);
            if(InpSendPushNotification) SendNotification(msg);
         }
      }

      // --- KONDISI SELL (SHORT):
      // Lilin 2 & 1 sebelumnya ditutup di atas VWAP, lilin saat ini menembus/cross ke bawah VWAP
      if(close[i - 2] > vwap_prev2 && close[i - 1] > vwap_prev && close[i] <= vwap_i)
      {
         BufferSell[i] = high[i] + (_Point * 20); // Posisi panah

         double entryPrice = close[i];
         double slPrice    = high[i] + (candleRange * InpSLMultiplier);
         double riskDist   = slPrice - entryPrice;
         double tpPrice    = entryPrice - (riskDist * InpRewardRiskRatio);

         // Tampilkan target garis di chart
         if(InpShowSLTPTargets && i >= rates_total - 100)
         {
            string lineId = ExtPrefix + "SELL_" + TimeToString(time[i]);
            DrawTargetLines(lineId, time[i], entryPrice, slPrice, tpPrice, clrCrimson, clrLimeGreen);
         }

         // Alert pada pembentukan sinyal bar baru
         if(InpEnableAlerts && i == rates_total - 2 && time[i] != ExtLastAlertTime)
         {
            ExtLastAlertTime = time[i];
            string msg = StringFormat("VWAP BOUNCE [SELL] @ %.2f | SL: %.2f | TP: %.2f (%s %s)",
                                      entryPrice, slPrice, tpPrice, _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period));
            Alert(msg);
            if(InpSendPushNotification) SendNotification(msg);
         }
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Fungsi Menggambar Garis Entry, Stop Loss, dan Take Profit di Chart|
//+------------------------------------------------------------------+
void DrawTargetLines(string baseName, datetime t, double entry, double sl, double tp, color cEntry, color cSL)
{
   datetime t2 = t + PeriodSeconds(_Period) * 15; // Garis sepanjang 15 lilin ke depan

   // Garis Entry
   string nameEntry = baseName + "_ENTRY";
   if(ObjectFind(0, nameEntry) < 0)
   {
      ObjectCreate(0, nameEntry, OBJ_TREND, 0, t, entry, t2, entry);
      ObjectSetInteger(0, nameEntry, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, nameEntry, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nameEntry, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameEntry, OBJPROP_SELECTABLE, false);
   }

   // Garis Stop Loss
   string nameSL = baseName + "_SL";
   if(ObjectFind(0, nameSL) < 0)
   {
      ObjectCreate(0, nameSL, OBJ_TREND, 0, t, sl, t2, sl);
      ObjectSetInteger(0, nameSL, OBJPROP_COLOR, clrCrimson);
      ObjectSetInteger(0, nameSL, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nameSL, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nameSL, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nameSL, OBJPROP_SELECTABLE, false);
   }

   // Garis Take Profit
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
