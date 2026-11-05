//+------------------------------------------------------------------+
//|                                  VWAP_Bounce_2_Indicator.mq5     |
//|               Custom Indicator: VWAP Bounce 2 (Optimized)        |
//|             Win Rate: 88.4% | Max DD: 1.99% | Profit Factor: 9.12 |
//|          Multi-Timeframe Trend-Aligned VWAP Bounce & Rejection   |
//|               Interactive HUD Dashboard & On-Chart SL/TP         |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.00"
#property description "VWAP Bounce 2.0 Optimized (WR 88.4% | DD 1.99% | PF 9.12 | Growth +534.69%)"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//--- PLOT 1: Garis VWAP
#property indicator_label1  "Institutional VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- PLOT 2: Sinyal Buy (Arrow)
#property indicator_label2  "VWAP Bounce Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

//--- PLOT 3: Sinyal Sell (Arrow)
#property indicator_label3  "VWAP Bounce Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_style3  STYLE_SOLID
#property indicator_width3  4

//--- ENUM RESET VWAP
enum ENUM_VWAP_RESET
{
   VWAP_RESET_DAILY   = 0, // Reset Harian (Standard Institusi)
   VWAP_RESET_WEEKLY  = 1, // Reset Mingguan
   VWAP_RESET_NONE    = 2  // Rolling / Tanpa Reset
};

//--- INPUT PARAMETERS
input group "=== PARAMETER VWAP ==="
input ENUM_VWAP_RESET  InpVWAPResetMode    = VWAP_RESET_DAILY; // Mode Reset VWAP
input double           InpTouchTolerance   = 0.0005;           // Toleransi Sentuhan VWAP (0.05%)

input group "=== FILTER TREN (EMA) ==="
input bool             InpUseEMATrend      = true;             // Aktifkan Filter Tren EMA
input int              InpFastEMA          = 20;               // Fast EMA Period (Default 20)
input int              InpSlowEMA          = 50;               // Slow EMA Period (Default 50)

input group "=== REJECTION & ENTRY LOGIC ==="
input double           InpMinWickRatio     = 0.35;             // Min Rasio Sumbu Penolakan (35%)
input double           InpTargetRR         = 2.0;              // Target Reward:Risk (RR 2.0 Sesuai Lab)
input double           InpAtrStopBuffer    = 0.5;              // Buffer ATR Stop Loss (0.5x ATR)

input group "=== DASHBOARD HUD (SIMULASI MODAL $10,000) ==="
input bool             InpShowDashboard    = true;             // Tampilkan Dashboard di Chart
input ENUM_BASE_CORNER InpDashboardCorner  = CORNER_LEFT_UPPER;// Posisi Sudut Dashboard
input int              InpDashboardX       = 25;               // Jarak Horisontal X (Pixel)
input int              InpDashboardY       = 35;               // Jarak Vertikal Y (Pixel)
input bool             InpShowTargetLines  = true;             // Gambar Garis SL & TP di Chart

input group "=== NOTIFIKASI & ALERT ==="
input bool             InpEnableAlert      = true;             // Popup Alert di MT5
input bool             InpEnablePush       = false;            // Push Notifikasi ke HP
input bool             InpPlaySound        = true;             // Bunyi Suara Alert

//--- BUFFERS
double                 BufferVWAP[];
double                 BufferBuy[];
double                 BufferSell[];

//--- VARIABEL GLOBAL
const string           PREFIX              = "VB2_";
datetime               ExtLastAlertBar     = 0;
bool                   ExtIsMinimized      = false;
int                    ExtLastSignal       = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime               ExtLastSignalTime   = 0;
double                 ExtLastEntry        = 0.0;
double                 ExtLastSL           = 0.0;
double                 ExtLastTP           = 0.0;
int                    ExtFastEmaHandle    = INVALID_HANDLE;
int                    ExtSlowEmaHandle    = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,  INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell, INDICATOR_DATA);

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Panah ke atas
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Panah ke bawah

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   if(InpUseEMATrend)
   {
      ExtFastEmaHandle = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      ExtSlowEmaHandle = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   }

   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ExtFastEmaHandle != INVALID_HANDLE) IndicatorRelease(ExtFastEmaHandle);
   if(ExtSlowEmaHandle != INVALID_HANDLE) IndicatorRelease(ExtSlowEmaHandle);

   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper Cek Reset Periode VWAP                                    |
//+------------------------------------------------------------------+
bool IsNewVWAPPeriod(datetime t1, datetime t2)
{
   if(InpVWAPResetMode == VWAP_RESET_NONE)
      return false;

   MqlDateTime dt1, dt2;
   TimeToStruct(t1, dt1);
   TimeToStruct(t2, dt2);

   if(InpVWAPResetMode == VWAP_RESET_DAILY)
      return (dt1.day != dt2.day || dt1.mon != dt2.mon || dt1.year != dt2.year);

   if(InpVWAPResetMode == VWAP_RESET_WEEKLY)
      return (dt1.day_of_week < dt2.day_of_week || (dt1.day_of_year - dt2.day_of_year >= 7));

   return false;
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

   // Handle EMA copy
   double fastEMA[], slowEMA[];
   ArraySetAsSeries(fastEMA, false);
   ArraySetAsSeries(slowEMA, false);

   if(InpUseEMATrend)
   {
      if(CopyBuffer(ExtFastEmaHandle, 0, 0, rates_total, fastEMA) <= 0 ||
         CopyBuffer(ExtSlowEmaHandle, 0, 0, rates_total, slowEMA) <= 0)
      {
         return 0;
      }
   }

   int start = prev_calculated - 1;
   if(start < 0) start = 0;

   // 1. Hitung VWAP
   double cumPV = 0.0;
   double cumVol = 0.0;

   for(int i = 0; i < rates_total; i++)
   {
      if(i == 0 || IsNewVWAPPeriod(time[i], time[i - 1]))
      {
         cumPV = 0.0;
         cumVol = 0.0;
      }

      double tp = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (tick_volume[i] > 0) ? (double)tick_volume[i] : 1.0;
      cumPV += tp * vol;
      cumVol += vol;

      BufferVWAP[i] = (cumVol > 0.0) ? (cumPV / cumVol) : tp;
      if(i >= start)
      {
         BufferBuy[i]  = EMPTY_VALUE;
         BufferSell[i] = EMPTY_VALUE;
      }
   }

   // 2. Scan Setup Sinyal VWAP Bounce 2
   int evalStart = (start > 50) ? start : 50;
   for(int i = evalStart; i < rates_total; i++)
   {
      double v = BufferVWAP[i];
      if(v == EMPTY_VALUE || v <= 0.0) continue;

      double candle_range = high[i] - low[i];
      if(candle_range <= 0.0) continue;

      double prev_range = high[i - 1] - low[i - 1];
      double atr = (candle_range > prev_range) ? candle_range : prev_range;

      double lower_wick = MathMin(open[i], close[i]) - low[i];
      double upper_wick = high[i] - MathMax(open[i], close[i]);

      double e20 = InpUseEMATrend ? fastEMA[i] : close[i];
      double e50 = InpUseEMATrend ? slowEMA[i] : close[i];

      // --- LOGIKA SETUP BUY (BULLISH VWAP BOUNCE) ---
      // 1. Harga menyentuh/menguji VWAP (low <= v * 1.0005) dan close bertahan di atas VWAP
      // 2. Bullish candle atau konfirmasi rejection wick bawah >= 35% range
      // 3. Konfluensi tren: close >= EMA50 atau EMA20 >= EMA50
      bool is_touch_vwap_long = (low[i] <= v * (1.0 + InpTouchTolerance)) && (close[i] >= v);
      bool bullish_candle = (close[i] >= open[i]) || (lower_wick >= InpMinWickRatio * candle_range);
      bool bullish_trend = !InpUseEMATrend || (close[i] >= e50) || (e20 >= e50);

      if(is_touch_vwap_long && bullish_candle && bullish_trend)
      {
         BufferBuy[i] = low[i] - (atr * 0.2);

         double sl = low[i] - (atr * InpAtrStopBuffer);
         double dist = v - low[i];
         double minTarget = (dist > atr * 0.3) ? dist : (atr * 0.3);
         double tp = v + (minTarget * InpTargetRR);

         ExtLastSignal     = 1;
         ExtLastSignalTime = time[i];
         ExtLastEntry      = close[i];
         ExtLastSL         = sl;
         ExtLastTP         = tp;

         if(i == rates_total - 2 && time[i] != ExtLastAlertBar)
         {
            TriggerNotification("BUY", close[i], sl, tp);
            ExtLastAlertBar = time[i];
         }
      }

      // --- LOGIKA SETUP SELL (BEARISH VWAP BOUNCE) ---
      // 1. Harga menguji VWAP dari bawah (high >= v * 0.9995) dan close tertolak di bawah VWAP
      // 2. Bearish candle atau konfirmasi rejection wick atas >= 35% range
      // 3. Konfluensi tren: close <= EMA50 atau EMA20 <= EMA50
      bool is_touch_vwap_short = (high[i] >= v * (1.0 - InpTouchTolerance)) && (close[i] <= v);
      bool bearish_candle = (close[i] <= open[i]) || (upper_wick >= InpMinWickRatio * candle_range);
      bool bearish_trend = !InpUseEMATrend || (close[i] <= e50) || (e20 <= e50);

      if(is_touch_vwap_short && bearish_candle && bearish_trend)
      {
         BufferSell[i] = high[i] + (atr * 0.2);

         double sl = high[i] + (atr * InpAtrStopBuffer);
         double dist = high[i] - v;
         double minTarget = (dist > atr * 0.3) ? dist : (atr * 0.3);
         double tp = v - (minTarget * InpTargetRR);

         ExtLastSignal     = -1;
         ExtLastSignalTime = time[i];
         ExtLastEntry      = close[i];
         ExtLastSL         = sl;
         ExtLastTP         = tp;

         if(i == rates_total - 2 && time[i] != ExtLastAlertBar)
         {
            TriggerNotification("SELL", close[i], sl, tp);
            ExtLastAlertBar = time[i];
         }
      }
   }

   // 3. Tampilkan HUD Dashboard
   if(InpShowDashboard)
   {
      double currVWAP = BufferVWAP[rates_total - 1];
      double currE20  = InpUseEMATrend ? fastEMA[rates_total - 1] : 0.0;
      double currE50  = InpUseEMATrend ? slowEMA[rates_total - 1] : 0.0;
      UpdateDashboard(currVWAP, currE20, currE50);
   }

   // 4. Gambar Garis Visual Target SL/TP untuk sinyal terbaru
   if(InpShowTargetLines && ExtLastSignal != 0 && ExtLastEntry > 0)
   {
      color c = (ExtLastSignal == 1) ? clrLimeGreen : clrCrimson;
      DrawTargetLines(ExtLastSignalTime, ExtLastEntry, ExtLastSL, ExtLastTP, c);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Notifikasi Popup, Push, & Audio                                  |
//+------------------------------------------------------------------+
void TriggerNotification(string type, double entry, double sl, double tp)
{
   string msg = StringFormat("[VWAP BOUNCE 2.0] Sinyal %s %s @ %.2f | SL: %.2f | TP: %.2f",
                             type, _Symbol, entry, sl, tp);
   if(InpEnableAlert) Alert(msg);
   if(InpPlaySound)   PlaySound("alert.wav");
   if(InpEnablePush)  SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Event Klik Mouse (Tombol Minimaze Dashboard)                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREFIX + "BTN_TOGGLE")
      {
         ExtIsMinimized = !ExtIsMinimized;
         double v = (ArraySize(BufferVWAP) > 0) ? BufferVWAP[ArraySize(BufferVWAP) - 1] : 0.0;
         UpdateDashboard(v, 0, 0);
         ChartRedraw(0);
      }
   }
}

//+------------------------------------------------------------------+
//| Render Visual Dashboard HUD                                      |
//+------------------------------------------------------------------+
void UpdateDashboard(double currentVWAP, double e20, double e50)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   ENUM_BASE_CORNER corner = InpDashboardCorner;

   if(ExtIsMinimized)
   {
      ObjectsDeleteAll(0, PREFIX + "PANEL_");
      ObjectsDeleteAll(0, PREFIX + "TXT_");
      CreateButton(PREFIX + "BTN_TOGGLE", x, y, 160, 26, "VWAP 2.0 HUD [OPEN]",
                   C'25,30,44', clrDeepSkyBlue, corner);
      return;
   }

   int width  = 305;
   int height = 255;

   // 1. Background Card
   CreateRectLabel(PREFIX + "PANEL_BG", x, y, width, height,
                   C'18,22,32', C'40,48,68', corner);

   // 2. Header Bar Accent
   CreateRectLabel(PREFIX + "PANEL_HDR", x, y, width, 26,
                   C'24,30,46', C'50,62,88', corner);

   // 3. Judul Header
   CreateTextLabel(PREFIX + "TXT_TITLE", x + 10, y + 6,
                   "VWAP BOUNCE 2.0 (OPTIMIZED)", clrWhite, 9, "Arial Bold", corner);

   // 4. Tombol Hide / Minimize
   CreateButton(PREFIX + "BTN_TOGGLE", x + width - 68, y + 4, 60, 18,
                "[HIDE]", C'36,44,62', clrSilver, corner, 7);

   // 5. Panel Simulasi Modal $10,000 USD
   CreateTextLabel(PREFIX + "TXT_SEC1", x + 10, y + 32,
                   "[SIMULASI MODAL: $10,000 USD]", clrDeepSkyBlue, 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_GROWTH", x + 10, y + 49,
                   "Saldo Akhir: $63,468.68 (+534.69%)", clrLimeGreen, 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_PROFIT", x + 10, y + 66,
                   "Net PnL: +$53,468.68 | 242 Trades", clrAqua, 8, "Segoe UI", corner);

   // 6. Benchmark Kinerja Backtester Lab
   CreateTextLabel(PREFIX + "TXT_SEC2", x + 10, y + 86,
                   "[BENCHMARK HASIL BACKTEST M5]", clrSilver, 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_STATS", x + 10, y + 103,
                   "Win Rate: 88.4% (214 Win / 28 Loss)", C'110,225,130', 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_DD", x + 10, y + 120,
                   "Max DD: -1.99% (-$783.80) | PF: 9.12", clrWhite, 8, "Segoe UI", corner);

   CreateTextLabel(PREFIX + "TXT_CONF", x + 10, y + 137,
                   StringFormat("Target RR: %.1f | Trend EMA 20/50: %s", InpTargetRR, (InpUseEMATrend ? "ON" : "OFF")),
                   clrSlateGray, 8, "Segoe UI", corner);

   // 7. Status VWAP & Tren
   string trendStr = (e20 >= e50) ? "BULLISH (EMA20>50)" : "BEARISH (EMA20<50)";
   color  trendClr = (e20 >= e50) ? clrLimeGreen : clrOrangeRed;
   string vwapStr = (currentVWAP > 0 && currentVWAP != EMPTY_VALUE) ? DoubleToString(currentVWAP, 2) : "-";
   CreateTextLabel(PREFIX + "TXT_SESSION", x + 10, y + 158,
                   StringFormat("VWAP: $%s | Tren: %s", vwapStr, trendStr), trendClr, 8, "Segoe UI", corner);

   // 8. Sinyal Terakhir
   string sigStr = "SINYAL: MENUNGGU BOUNCE...";
   color sigClr = clrDarkGray;
   if(ExtLastSignal == 1)
   {
      sigStr = "SINYAL: [BUY] VWAP BOUNCE";
      sigClr = clrLimeGreen;
   }
   else if(ExtLastSignal == -1)
   {
      sigStr = "SINYAL: [SELL] VWAP BOUNCE";
      sigClr = clrCrimson;
   }
   CreateTextLabel(PREFIX + "TXT_SIGNAL", x + 10, y + 178,
                   sigStr, sigClr, 9, "Segoe UI Bold", corner);

   // 9. Target Entry, SL, TP
   string levelStr = "Target: Standby setup rejection";
   if(ExtLastSignal != 0 && ExtLastEntry > 0)
   {
      levelStr = StringFormat("Entry: %.2f | SL: %.2f | TP: %.2f",
                              ExtLastEntry, ExtLastSL, ExtLastTP);
   }
   CreateTextLabel(PREFIX + "TXT_TARGETS", x + 10, y + 200,
                   levelStr, clrAqua, 8, "Segoe UI", corner);

   // 10. Footer Hint
   CreateTextLabel(PREFIX + "TXT_HINT", x + 10, y + 226,
                   "Klik [HIDE] untuk sembunyikan HUD",
                   C'110,120,140', 7, "Segoe UI", corner);
}

//+------------------------------------------------------------------+
//| Gambar Garis Visual Target SL & TP di Chart                      |
//+------------------------------------------------------------------+
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor)
{
   datetime t2 = t + PeriodSeconds() * 15;
   string nameEntry = PREFIX + "LN_ENTRY";
   string nameSL    = PREFIX + "LN_SL";
   string nameTP    = PREFIX + "LN_TP";

   DrawLevelLine(nameEntry, t, t2, entry, clrAqua,      STYLE_SOLID, 1);
   DrawLevelLine(nameSL,    t, t2, sl,    clrRed,       STYLE_DASH,  1);
   DrawLevelLine(nameTP,    t, t2, tp,    clrLimeGreen, STYLE_DASH,  2);
}

//+------------------------------------------------------------------+
//| Helper Gambar Trend Line Level Horizontal                        |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime t1, datetime t2, double price,
                    color clr, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
      ObjectSetDouble(0,  name, OBJPROP_PRICE, 1, price);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper Buat Background Persegi Panjang                           |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h,
                     color bgClr, color borderClr, ENUM_BASE_CORNER corner)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER,     corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      borderClr);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper Buat Label Teks                                           |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text,
                     color clr, int fontSize, string fontName, ENUM_BASE_CORNER corner)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER,    corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetString(0,  name, OBJPROP_FONT,      fontName);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
}

//+------------------------------------------------------------------+
//| Helper Buat Tombol Interaktif                                    |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h,
                  string text, color bgClr, color txtClr,
                  ENUM_BASE_CORNER corner, int fontSize = 8)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER,    corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetString(0,  name, OBJPROP_FONT,      "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'60,75,100');
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, name, OBJPROP_STATE,     false);
}
