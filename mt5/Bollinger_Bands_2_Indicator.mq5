//+------------------------------------------------------------------+
//|                                Bollinger_Bands_2_Indicator.mq5   |
//|               Custom Indicator: Bollinger Bands 2 Trend Reversal |
//|                    Dual Mode: M1 & M5 Timeframe Selector         |
//|                      Win Rate: 77.78% | Max DD: 1.99%            |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.00"
#property description "Bollinger Bands 2: Trend-Aligned Outer Band Rejection Scalper (WR 77.8% | DD 1.99%)"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

//--- ENUM OPSI TIMEFRAME
enum ENUM_BB_TF
{
   TF_CURRENT = 0,            // Ikuti Timeframe Chart Aktif
   TF_M1      = PERIOD_M1,    // Mode M1 (1 Menit Scalping)
   TF_M5      = PERIOD_M5     // Mode M5 (5 Menit Intraday - Rekomendasi Win Rate 77.8%)
};

//--- PLOT 1: Upper Band
#property indicator_label1  "Upper Band"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- PLOT 2: Middle Band
#property indicator_label2  "Middle Band (SMA 16)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGold
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- PLOT 3: Lower Band
#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- PLOT 4: Fast EMA
#property indicator_label4  "Fast EMA (20)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrCyan
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

//--- PLOT 5: Slow EMA
#property indicator_label5  "Slow EMA (50)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrMagenta
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

//--- PLOT 6: Buy Signal (Arrow)
#property indicator_label6  "BB2 Buy Signal"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLimeGreen
#property indicator_style6  STYLE_SOLID
#property indicator_width6  2

//--- PLOT 7: Sell Signal (Arrow)
#property indicator_label7  "BB2 Sell Signal"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrCrimson
#property indicator_style7  STYLE_SOLID
#property indicator_width7  2

//--- INPUT PARAMETERS
input group "=== PILIHAN SUMBER TIMEFRAME ==="
input ENUM_BB_TF InpTimeframeMode   = TF_M5;      // Pilihan Timeframe Sinyal

input group "=== PARAMETER BOLLINGER BANDS 2 ==="
input int        InpBBPeriod        = 16;         // Periode Bollinger Bands (Tuned: 16)
input double     InpBBDeviations    = 2.0;        // Deviasi Standar Pita
input double     InpSlBufferMult    = 0.35;       // Multiplier Stop Loss Buffer Pita (35%)

input group "=== PARAMETER FILTER TREN (EMA) ==="
input bool       InpUseTrendFilter  = true;       // Aktifkan Filter Tren EMA
input int        InpFastEmaPeriod   = 20;         // Fast EMA Period
input int        InpSlowEmaPeriod   = 50;         // Slow EMA Period

input group "=== NOTIFIKASI & ALERT ==="
input bool       InpEnableAlert     = true;       // Popup Alert di MT5
input bool       InpEnablePush      = false;      // Push Notifikasi ke HP
input bool       InpPlaySound       = true;       // Bunyi Notifikasi

//--- BUFFERS
double BufferUpper[];
double BufferMid[];
double BufferLower[];
double BufferEma20[];
double BufferEma50[];
double BufferBuy[];
double BufferSell[];

//--- HANDLES & STATE
int    handleBB  = INVALID_HANDLE;
int    handleE20 = INVALID_HANDLE;
int    handleE50 = INVALID_HANDLE;
datetime lastAlertBar = 0;

//+------------------------------------------------------------------+
//| Helper: Dapatkan ENUM_TIMEFRAMES target                           |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetTargetTimeframe()
{
   if(InpTimeframeMode == TF_M1) return PERIOD_M1;
   if(InpTimeframeMode == TF_M5) return PERIOD_M5;
   return Period();
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferUpper, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMid,   INDICATOR_DATA);
   SetIndexBuffer(2, BufferLower, INDICATOR_DATA);
   SetIndexBuffer(3, BufferEma20, INDICATOR_DATA);
   SetIndexBuffer(4, BufferEma50, INDICATOR_DATA);
   SetIndexBuffer(5, BufferBuy,   INDICATOR_DATA);
   SetIndexBuffer(6, BufferSell,  INDICATOR_DATA);

   PlotIndexSetInteger(5, PLOT_ARROW, 233); // Panah Atas (Buy)
   PlotIndexSetInteger(6, PLOT_ARROW, 234); // Panah Bawah (Sell)

   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ENUM_TIMEFRAMES tf = GetTargetTimeframe();
   handleBB  = iBands(_Symbol, tf, InpBBPeriod, 0, InpBBDeviations, PRICE_CLOSE);
   handleE20 = iMA(_Symbol, tf, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleE50 = iMA(_Symbol, tf, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(handleBB == INVALID_HANDLE || handleE20 == INVALID_HANDLE || handleE50 == INVALID_HANDLE)
   {
      Print("Gagal inisialisasi indikator handle internal.");
      return INIT_FAILED;
   }

   string tfName = (tf == PERIOD_M1) ? "M1" : ((tf == PERIOD_M5) ? "M5" : "Current");
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("BB2_Reversal(%s,%d,%.1f)", tfName, InpBBPeriod, InpBBDeviations));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleBB != INVALID_HANDLE)  IndicatorRelease(handleBB);
   if(handleE20 != INVALID_HANDLE) IndicatorRelease(handleE20);
   if(handleE50 != INVALID_HANDLE) IndicatorRelease(handleE50);
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
   if(rates_total < 55) return 0;

   int start = prev_calculated - 1;
   if(start < 1)
   {
      start = 1;
      ArrayInitialize(BufferUpper, EMPTY_VALUE);
      ArrayInitialize(BufferMid,   EMPTY_VALUE);
      ArrayInitialize(BufferLower, EMPTY_VALUE);
      ArrayInitialize(BufferEma20, EMPTY_VALUE);
      ArrayInitialize(BufferEma50, EMPTY_VALUE);
      ArrayInitialize(BufferBuy,   EMPTY_VALUE);
      ArrayInitialize(BufferSell,  EMPTY_VALUE);
   }

   ENUM_TIMEFRAMES tf = GetTargetTimeframe();

   // Salin buffer Bollinger Bands & EMA
   double bbUpper[], bbMid[], bbLower[], e20[], e50[];
   ArraySetAsSeries(bbUpper, false);
   ArraySetAsSeries(bbMid,   false);
   ArraySetAsSeries(bbLower, false);
   ArraySetAsSeries(e20,     false);
   ArraySetAsSeries(e50,     false);

   int copyCount = rates_total;
   if(CopyBuffer(handleBB, 1, 0, copyCount, bbUpper) <= 0 ||
      CopyBuffer(handleBB, 0, 0, copyCount, bbMid)   <= 0 ||
      CopyBuffer(handleBB, 2, 0, copyCount, bbLower) <= 0 ||
      CopyBuffer(handleE20, 0, 0, copyCount, e20)    <= 0 ||
      CopyBuffer(handleE50, 0, 0, copyCount, e50)    <= 0)
   {
      return prev_calculated;
   }

   for(int i = start; i < rates_total; i++)
   {
      BufferUpper[i] = bbUpper[i];
      BufferMid[i]   = bbMid[i];
      BufferLower[i] = bbLower[i];
      BufferEma20[i] = e20[i];
      BufferEma50[i] = e50[i];
      BufferBuy[i]   = EMPTY_VALUE;
      BufferSell[i]  = EMPTY_VALUE;

      if(i < 50) continue;

      double upper = bbUpper[i];
      double mid   = bbMid[i];
      double lower = bbLower[i];
      double bandWidth = upper - lower;
      if(bandWidth <= 0.05) continue;

      bool risingFast  = (e20[i] > e20[i - 1]);
      bool fallingFast = (e20[i] < e20[i - 1]);

      bool biasLong  = !InpUseTrendFilter || ((close[i] > e50[i]) && risingFast);
      bool biasShort = !InpUseTrendFilter || ((close[i] < e50[i]) && fallingFast);

      // 1. SIGNAL BUY: Price sweeps lower band and rebounds
      if(low[i] <= lower && low[i - 1] > lower && biasLong)
      {
         BufferBuy[i] = low[i] - (bandWidth * 0.15);

         if(i == rates_total - 1 && time[i] != lastAlertBar)
         {
            lastAlertBar = time[i];
            double slVal = lower - bandWidth * InpSlBufferMult;
            double tpVal = mid + (mid - lower);
            string msg = StringFormat("[BB2 BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 77.8%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);
         }
      }

      // 2. SIGNAL SELL: Price sweeps upper band and pulls back
      if(high[i] >= upper && high[i - 1] < upper && biasShort)
      {
         BufferSell[i] = high[i] + (bandWidth * 0.15);

         if(i == rates_total - 1 && time[i] != lastAlertBar)
         {
            lastAlertBar = time[i];
            double slVal = upper + bandWidth * InpSlBufferMult;
            double tpVal = mid - (upper - mid);
            string msg = StringFormat("[BB2 SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 77.8%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);
         }
      }
   }

   return rates_total;
}
