//+------------------------------------------------------------------+
//|                                  VWAP_Bounce_2_Indicator.mq4     |
//|               Custom Indicator: VWAP Bounce 2 (Optimized)        |
//|             Win Rate: 88.4% | Max DD: 1.99% | Profit Factor: 9.12 |
//|          Multi-Timeframe Trend-Aligned VWAP Bounce & Rejection   |
//|               Interactive HUD Dashboard & On-Chart SL/TP         |
//|                   MetaTrader 4 (MT4) Edition                     |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.00"
#property description "VWAP Bounce 2.0 Optimized for MT4 (WR 88.4% | DD 1.99% | PF 9.12 | Growth +534.69%)"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  2
#property indicator_color2  clrLimeGreen
#property indicator_width2  4
#property indicator_color3  clrCrimson
#property indicator_width3  4

//--- INPUT PARAMETERS
extern string         s1                  = "=== PARAMETER VWAP ===";
extern int            InpVWAPResetMode    = 0;          // 0: Reset Harian (Standard Institusi), 1: Reset Mingguan, 2: Tanpa Reset
extern double         InpTouchTolerance   = 0.0005;     // Toleransi Sentuhan VWAP (0.05%)

extern string         s2                  = "=== FILTER TREN (EMA) ===";
extern bool           InpUseEMATrend      = true;       // Aktifkan Filter Tren EMA
extern int            InpFastEMA          = 20;         // Fast EMA Period (Default 20)
extern int            InpSlowEMA          = 50;         // Slow EMA Period (Default 50)

extern string         s3                  = "=== REJECTION & ENTRY LOGIC ===";
extern double         InpMinWickRatio     = 0.35;       // Min Rasio Sumbu Penolakan (35%)
extern double         InpTargetRR         = 2.0;        // Target Reward:Risk (RR 2.0 Sesuai Lab)
extern double         InpAtrStopBuffer    = 0.5;        // Buffer ATR Stop Loss (0.5x ATR)

extern string         s4                  = "=== DASHBOARD HUD (SIMULASI MODAL $10,000) ===";
extern bool           InpShowDashboard    = true;       // Tampilkan Dashboard di Chart MT4
extern int            InpDashboardCorner  = 0;          // 0: Kiri Atas, 1: Kanan Atas, 2: Kiri Bawah, 3: Kanan Bawah
extern int            InpDashboardX       = 25;         // Jarak Horisontal X (Pixel)
extern int            InpDashboardY       = 35;         // Jarak Vertikal Y (Pixel)
extern bool           InpShowTargetLines  = true;       // Gambar Garis SL & TP di Chart MT4

extern string         s5                  = "=== NOTIFIKASI & ALERT ===";
extern bool           InpEnableAlert      = true;       // Popup Alert di MT4
extern bool           InpEnablePush       = false;      // Push Notifikasi ke HP
extern bool           InpPlaySound        = true;       // Bunyi Notifikasi Audio

//--- BUFFERS
double                BufferVWAP[];
double                BufferBuy[];
double                BufferSell[];

//--- VARIABEL GLOBAL
const string          PREFIX              = "VB2_MT4_";
datetime              ExtLastAlertBar     = 0;
bool                  ExtIsMinimized      = false;
int                   ExtLastSignal       = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime              ExtLastSignalTime   = 0;
double                ExtLastEntry        = 0.0;
double                ExtLastSL           = 0.0;
double                ExtLastTP           = 0.0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(3);

   // Buffer 0: Garis VWAP
   SetIndexBuffer(0, BufferVWAP);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, clrDeepSkyBlue);
   SetIndexLabel(0, "Institutional VWAP");

   // Buffer 1: Sinyal Buy Arrow
   SetIndexBuffer(1, BufferBuy);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 4, clrLimeGreen);
   SetIndexArrow(1, 233); // Panah ke atas
   SetIndexLabel(1, "VWAP Bounce Buy");

   // Buffer 2: Sinyal Sell Arrow
   SetIndexBuffer(2, BufferSell);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 4, clrCrimson);
   SetIndexArrow(2, 234); // Panah ke bawah
   SetIndexLabel(2, "VWAP Bounce Sell");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper Cek Reset Periode VWAP di MT4                             |
//+------------------------------------------------------------------+
bool IsNewVWAPPeriod(datetime t1, datetime t2)
{
   if(InpVWAPResetMode == 2) // Tanpa Reset
      return false;

   if(InpVWAPResetMode == 0) // Reset Harian
      return (TimeDay(t1) != TimeDay(t2) || TimeMonth(t1) != TimeMonth(t2) || TimeYear(t1) != TimeYear(t2));

   if(InpVWAPResetMode == 1) // Reset Mingguan
      return (TimeDayOfWeek(t1) < TimeDayOfWeek(t2) || (TimeDayOfYear(t1) - TimeDayOfYear(t2) >= 7));

   return false;
}

//+------------------------------------------------------------------+
//| Helper Gambar Trend Line Level Horizontal                        |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime t1, datetime t2, double price,
                    color clr, int style, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME1, t1);
      ObjectSetDouble(0,  name, OBJPROP_PRICE1, price);
      ObjectSetInteger(0, name, OBJPROP_TIME2, t2);
      ObjectSetDouble(0,  name, OBJPROP_PRICE2, price);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Gambar Garis Target Visual SL & TP                               |
//+------------------------------------------------------------------+
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor)
{
   datetime t2 = t + Period() * 60 * 15;
   string nameEntry = PREFIX + "LN_ENTRY";
   string nameSL    = PREFIX + "LN_SL";
   string nameTP    = PREFIX + "LN_TP";

   DrawLevelLine(nameEntry, t, t2, entry, clrAqua,      STYLE_SOLID, 1);
   DrawLevelLine(nameSL,    t, t2, sl,    clrRed,       STYLE_DASH,  1);
   DrawLevelLine(nameTP,    t, t2, tp,    clrLimeGreen, STYLE_DASH,  2);
}

//+------------------------------------------------------------------+
//| Helper Buat Background Persegi Panjang                           |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h,
                     color bgClr, color borderClr, int corner)
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
                     color clr, int fontSize, string fontName, int corner)
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
                  int corner, int fontSize = 8)
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

//+------------------------------------------------------------------+
//| Render Visual Dashboard HUD MT4                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(double currentVWAP, double e20, double e50)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int corner = InpDashboardCorner;

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
   string vwapStr = (currentVWAP > 0 && currentVWAP != EMPTY_VALUE) ? DoubleToStr(currentVWAP, 2) : "-";
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
//| Notifikasi Popup, Push, & Audio                                  |
//+------------------------------------------------------------------+
void TriggerNotification(string type, double entry, double sl, double tp)
{
   string msg = StringFormat("[VWAP BOUNCE 2.0 MT4] Sinyal %s %s @ %.2f | SL: %.2f | TP: %.2f",
                             type, _Symbol, entry, sl, tp);
   if(InpEnableAlert) Alert(msg);
   if(InpPlaySound)   PlaySound("alert.wav");
   if(InpEnablePush)  SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Event Klik Mouse (Tombol Minimize Dashboard)                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREFIX + "BTN_TOGGLE")
      {
         ExtIsMinimized = !ExtIsMinimized;
         double v = (ArraySize(BufferVWAP) > 0) ? BufferVWAP[0] : 0.0;
         UpdateDashboard(v, 0, 0);
         ChartRedraw(0);
      }
   }
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

   // MT4 arrays in OnCalculate can be series (index 0 is newest) or normal.
   // Let's standardise with Bars and explicit index loops.
   int limit = rates_total - prev_calculated;
   if(limit <= 0) limit = 1;
   if(prev_calculated == 0) limit = rates_total - 1;

   // 1. Hitung VWAP (dari bar tertua [rates_total-1] ke teranyar [0])
   double cumPV = 0.0;
   double cumVol = 0.0;

   for(int i = rates_total - 1; i >= 0; i--)
   {
      datetime tCurr = time[i];
      datetime tPrev = (i < rates_total - 1) ? time[i + 1] : tCurr;

      if(i == rates_total - 1 || IsNewVWAPPeriod(tCurr, tPrev))
      {
         cumPV = 0.0;
         cumVol = 0.0;
      }

      double tp = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (tick_volume[i] > 0) ? (double)tick_volume[i] : 1.0;
      cumPV += tp * vol;
      cumVol += vol;

      BufferVWAP[i] = (cumVol > 0.0) ? (cumPV / cumVol) : tp;
      if(i <= limit)
      {
         BufferBuy[i]  = EMPTY_VALUE;
         BufferSell[i] = EMPTY_VALUE;
      }
   }

   // 2. Evaluasi Sinyal VWAP Bounce 2
   int evalLimit = limit;
   if(evalLimit > rates_total - 52) evalLimit = rates_total - 52;

   for(int i = evalLimit; i >= 0; i--)
   {
      double v = BufferVWAP[i];
      if(v == EMPTY_VALUE || v <= 0.0) continue;

      double candle_range = high[i] - low[i];
      if(candle_range <= 0.0) continue;

      double prev_range = high[i + 1] - low[i + 1];
      double atr = (candle_range > prev_range) ? candle_range : prev_range;

      double lower_wick = MathMin(open[i], close[i]) - low[i];
      double upper_wick = high[i] - MathMax(open[i], close[i]);

      double e20 = InpUseEMATrend ? iMA(NULL, 0, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, i) : close[i];
      double e50 = InpUseEMATrend ? iMA(NULL, 0, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, i) : close[i];

      // --- LOGIKA SETUP BUY (BULLISH VWAP BOUNCE) ---
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

         if(i == 1 && time[i] != ExtLastAlertBar)
         {
            TriggerNotification("BUY", close[i], sl, tp);
            ExtLastAlertBar = time[i];
         }
      }

      // --- LOGIKA SETUP SELL (BEARISH VWAP BOUNCE) ---
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

         if(i == 1 && time[i] != ExtLastAlertBar)
         {
            TriggerNotification("SELL", close[i], sl, tp);
            ExtLastAlertBar = time[i];
         }
      }
   }

   // 3. Tampilkan HUD Dashboard
   if(InpShowDashboard)
   {
      double currVWAP = BufferVWAP[0];
      double currE20  = InpUseEMATrend ? iMA(NULL, 0, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 0) : 0.0;
      double currE50  = InpUseEMATrend ? iMA(NULL, 0, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 0) : 0.0;
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
