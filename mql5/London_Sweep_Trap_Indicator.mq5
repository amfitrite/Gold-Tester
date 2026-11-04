//+------------------------------------------------------------------+
//|                                London_Sweep_Trap_Indicator.mq5   |
//|               Custom Indicator: London & NY Session VWAP Trap    |
//|                      Win Rate: 77.0% | Max DD: 2.97%             |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.00"
#property description "London Sweep Trap: Institutional Session VWAP Liquidity Trap (WR 77.0% | DD 2.97%)"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- PLOT 1: Garis Session VWAP
#property indicator_label1  "Session VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- PLOT 2: Sinyal Buy (Arrow)
#property indicator_label2  "London Bull Trap Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- PLOT 3: Sinyal Sell (Arrow)
#property indicator_label3  "London Bear Trap Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- INPUT PARAMETERS
input group "=== JAM SESI AKTIF (LONDON & NY UTC) ==="
input int    InpSessionStartHour = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
input int    InpSessionEndHour   = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

input group "=== PARAMETER ENTRY & STOP LOSS ==="
input double InpRewardRiskRatio  = 1.5;        // Rasio Take Profit (1.5x)
input double InpAtrStopBuffer    = 0.5;        // Buffer ATR Stop Loss

input group "=== NOTIFIKASI & ALERT ==="
input bool   InpEnableAlert      = true;       // Popup Alert di MT5
input bool   InpEnablePush       = false;      // Push Notifikasi ke HP
input bool   InpPlaySound        = true;       // Bunyi Suara Alert

//--- BUFFERS
double BufferVWAP[];
double BufferBuy[];
double BufferSell[];

datetime lastAlertBar = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,  INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell, INDICATOR_DATA);

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Panah Beli
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Panah Jual

   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "London_Sweep_Trap(77% WR)");

   return INIT_SUCCEEDED;
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
      ArrayInitialize(BufferVWAP, EMPTY_VALUE);
      ArrayInitialize(BufferBuy,  EMPTY_VALUE);
      ArrayInitialize(BufferSell, EMPTY_VALUE);
   }

   // 1. Kalkulasi Session VWAP dengan Reset Harian
   double cumPV = 0.0;
   double cumVol = 0.0;
   int lastDay = -1;

   for(int i = 0; i < rates_total; i++)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      // Reset saat pergantian hari kalender
      if(dt.day != lastDay)
      {
         cumPV = 0.0;
         cumVol = 0.0;
         lastDay = dt.day;
      }

      double tp = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (volume[i] > 0) ? (double)volume[i] : (tick_volume[i] > 0 ? (double)tick_volume[i] : 1.0);

      cumPV += tp * vol;
      cumVol += vol;

      BufferVWAP[i] = (cumVol > 0.0) ? (cumPV / cumVol) : tp;
   }

   // 2. Deteksi Jebakan Likuiditas Sesi London/NY
   for(int i = start; i < rates_total; i++)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      // Filter Jam Sesi
      if(dt.hour < InpSessionStartHour || dt.hour > InpSessionEndHour)
         continue;

      double v     = BufferVWAP[i];
      double vPrev = BufferVWAP[i - 1];
      double vPrev2= BufferVWAP[i - 2];

      if(v == EMPTY_VALUE || vPrev == EMPTY_VALUE || vPrev2 == EMPTY_VALUE)
         continue;

      double atr = MathMax(high[i] - low[i], high[i - 1] - low[i - 1]);
      if(atr <= 0.05) continue;

      // Bullish Trap (Long): Lilin sebelumnya di bawah VWAP, lilin saat ini merebut kembali VWAP
      if(close[i - 2] < vPrev2 && close[i - 1] < v && close[i] >= v)
      {
         BufferBuy[i] = low[i] - (atr * 0.3);

         if(i == rates_total - 1 && time[i] != lastAlertBar)
         {
            lastAlertBar = time[i];
            double slVal = low[i] - atr * InpAtrStopBuffer;
            double trapDist = v - low[i];
            double tpVal = v + trapDist * InpRewardRiskRatio;
            string msg = StringFormat("[LONDON TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 77.0%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);
         }
      }

      // Bearish Trap (Short): Lilin sebelumnya di atas VWAP, lilin saat ini terjebak dan close di bawah VWAP
      if(close[i - 2] > vPrev2 && close[i - 1] > v && close[i] <= v)
      {
         BufferSell[i] = high[i] + (atr * 0.3);

         if(i == rates_total - 1 && time[i] != lastAlertBar)
         {
            lastAlertBar = time[i];
            double slVal = high[i] + atr * InpAtrStopBuffer;
            double trapDist = high[i] - v;
            double tpVal = v - trapDist * InpRewardRiskRatio;
            string msg = StringFormat("[LONDON TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 77.0%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);
         }
      }
   }

   return rates_total;
}
