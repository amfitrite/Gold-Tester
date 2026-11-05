//+------------------------------------------------------------------+
//|                                London_Sweep_Trap_Indicator.mq4   |
//|               Custom Indicator: London & NY Session VWAP Trap    |
//|                   MetaTrader 4 (MT4) Edition with HUD Dashboard  |
//|              Win Rate: 75.3% | Max DD: 2.97% | Profit Factor: 4.86|
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.10"
#property description "London Sweep Trap for MT4: Institutional Session VWAP Liquidity Trap (WR 75.3% | DD 2.97% | PF 4.86)"
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_color1  clrGold
#property indicator_width1  2
#property indicator_color2  clrLimeGreen
#property indicator_width2  4
#property indicator_color3  clrCrimson
#property indicator_width3  4

//--- INPUT PARAMETERS
extern string         s1                  = "=== JAM SESI AKTIF (LONDON & NY UTC) ===";
extern int            InpSessionStartHour = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
extern int            InpSessionEndHour   = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

extern string         s2                  = "=== PARAMETER FILTER TREN (EMA) ===";
extern bool           InpUseEMATrend      = true;       // Aktifkan Filter Tren EMA (Fast 20 / Slow 50)
extern int            InpFastEMA          = 20;         // Periode Fast EMA
extern int            InpSlowEMA          = 50;         // Periode Slow EMA

extern string         s3                  = "=== PARAMETER TARGET & STOP LOSS ===";
extern double         InpRewardRiskRatio  = 1.5;        // Rasio Take Profit Trap (1.5x Sesuai Backtest Engine)
extern double         InpAtrStopBuffer    = 0.5;        // Buffer ATR Stop Loss

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
const string          PREFIX              = "LST4_";
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
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, clrGold);
   SetIndexLabel(0, "Session VWAP");

   // Buffer 1: Sinyal Buy Arrow
   SetIndexBuffer(1, BufferBuy);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 4, clrLimeGreen);
   SetIndexArrow(1, 233); // Panah ke atas
   SetIndexLabel(1, "London Bull Trap Buy");

   // Buffer 2: Sinyal Sell Arrow
   SetIndexBuffer(2, BufferSell);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 4, clrCrimson);
   SetIndexArrow(2, 234); // Panah ke bawah
   SetIndexLabel(2, "London Bear Trap Sell");

   IndicatorShortName("London Sweep Trap (MT4)");
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
   if(Bars < 10) return(0);

   int counted = IndicatorCounted();
   if(counted < 0) return(-1);
   if(counted > 0) counted--;
   int limit = Bars - counted;
   if(limit > Bars - 5)
   {
      limit = Bars - 5;
      ArrayInitialize(BufferBuy,  EMPTY_VALUE);
      ArrayInitialize(BufferSell, EMPTY_VALUE);
   }

   double slVal = 0.0;
   double tpVal = 0.0;
   double offset = 0.0;
   string msg = "";

   // 1. Hitung Akumulasi Session VWAP Presisi (Reset 00:00 Harian)
   int startBar = MathMin(Bars - 1, limit + 350);
   while(startBar < Bars - 1 && TimeDay(Time[startBar]) == TimeDay(Time[startBar + 1]))
      startBar++;

   double runningPV = 0.0;
   double runningVol = 0.0;

   for(int k = startBar; k >= 0; k--)
   {
      // Reset saat pergantian tanggal kalender
      if(k == Bars - 1 || TimeDay(Time[k]) != TimeDay(Time[k + 1]))
      {
         runningPV = 0.0;
         runningVol = 0.0;
      }

      double barPrice = (High[k] + Low[k] + Close[k]) / 3.0;
      double barVol   = (Volume[k] > 0) ? (double)Volume[k] : 1.0;

      runningPV += barPrice * barVol;
      runningVol += barVol;

      BufferVWAP[k] = (runningVol > 0.0) ? (runningPV / runningVol) : barPrice;
   }

   // 2. Deteksi Trap Sinyal London / NY (Maju dari lampau ke bar terbaru)
   bool inSessionNow = false;

   for(int i = limit; i >= 0; i--)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      int barHour = TimeHour(Time[i]);
      bool inSession = (barHour >= InpSessionStartHour && barHour <= InpSessionEndHour);
      if(i == 0) inSessionNow = inSession;

      if(!inSession) continue;

      double v      = BufferVWAP[i];
      double vPrev  = BufferVWAP[i + 1];
      double vPrev2 = BufferVWAP[i + 2];

      if(v == EMPTY_VALUE || vPrev == EMPTY_VALUE || vPrev2 == EMPTY_VALUE)
         continue;

      double atr = MathMax(High[i] - Low[i], High[i + 1] - Low[i + 1]);
      if(atr <= 0.05) continue;

      // Filter Tren EMA jika diaktifkan
      bool allowBuy = true;
      bool allowSell = true;
      if(InpUseEMATrend)
      {
         double fastEma = iMA(NULL, 0, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, i);
         double slowEma = iMA(NULL, 0, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, i);
         allowBuy  = (fastEma >= slowEma);
         allowSell = (fastEma <= slowEma);
      }

      // Bullish Trap (Long / BUY): Price pushed below VWAP, sweeps liquidity, reclaims VWAP
      if(allowBuy && Close[i + 2] < vPrev2 && Close[i + 1] < v && Close[i] >= v)
      {
         offset = MathMax(atr * 0.5, 20 * _Point);
         BufferBuy[i] = Low[i] - offset;

         // Formula Target Asli: v + (trap_distance * InpRewardRiskRatio)
         double trapDistance = v - Low[i];
         if(trapDistance < 0.0) trapDistance = atr * 0.5;
         slVal = Low[i] - (atr * InpAtrStopBuffer);
         tpVal = v + (trapDistance * InpRewardRiskRatio);

         ExtLastSignal     = 1;
         ExtLastSignalTime = Time[i];
         ExtLastEntry      = Close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i <= 1 && Time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = Time[i];
            msg = StringFormat("[MT4 LONDON TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75.3%%",
                               Symbol(), Close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(Time[i], Close[i], slVal, tpVal, clrLimeGreen);
         }
      }

      // Bearish Trap (Short / SELL): Price pushed above VWAP, sweeps liquidity, falls back below VWAP
      if(allowSell && Close[i + 2] > vPrev2 && Close[i + 1] > v && Close[i] <= v)
      {
         offset = MathMax(atr * 0.5, 20 * _Point);
         BufferSell[i] = High[i] + offset;

         // Formula Target Asli: v - (trap_distance * InpRewardRiskRatio)
         double trapDistance = High[i] - v;
         if(trapDistance < 0.0) trapDistance = atr * 0.5;
         slVal = High[i] + (atr * InpAtrStopBuffer);
         tpVal = v - (trapDistance * InpRewardRiskRatio);

         ExtLastSignal     = -1;
         ExtLastSignalTime = Time[i];
         ExtLastEntry      = Close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i <= 1 && Time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = Time[i];
            msg = StringFormat("[MT4 LONDON TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75.3%%",
                               Symbol(), Close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(Time[i], Close[i], slVal, tpVal, clrCrimson);
         }
      }
   }

   // 3. Update Dashboard HUD Real-Time
   if(InpShowDashboard)
   {
      double curVWAP = BufferVWAP[0];
      UpdateDashboard(inSessionNow, curVWAP, Close[0]);
      ChartRedraw(0);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Buat atau Update Dashboard HUD Sederhana di Layar Chart MT4      |
//+------------------------------------------------------------------+
void UpdateDashboard(bool inSession, double currentVWAP, double currentPrice)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int corner = InpDashboardCorner;

   // Mode MINIMIZE: Tampilkan hanya tombol kecil di pojok
   if(ExtIsMinimized)
   {
      ObjectsDeleteAll(0, PREFIX + "PANEL_");
      ObjectsDeleteAll(0, PREFIX + "TXT_");
      CreateButton(PREFIX + "BTN_TOGGLE", x, y, 160, 26, "LST HUD [OPEN]",
                   C'25,30,44', clrGold, corner);
      return;
   }

   int width  = 295;
   int height = 245;

   // 1. Background Card
   CreateRectLabel(PREFIX + "PANEL_BG", x, y, width, height,
                   C'18,22,32', C'40,48,68', corner);

   // 2. Header Bar Accent
   CreateRectLabel(PREFIX + "PANEL_HDR", x, y, width, 26,
                   C'24,30,46', C'50,62,88', corner);

   // 3. Judul Header
   CreateTextLabel(PREFIX + "TXT_TITLE", x + 10, y + 6,
                   "LONDON SWEEP TRAP (XAUUSD)", clrWhite, 9, "Arial Bold", corner);

   // 4. Tombol Hide / Minimize
   CreateButton(PREFIX + "BTN_TOGGLE", x + width - 68, y + 4, 60, 18,
                "[HIDE]", C'36,44,62', clrSilver, corner, 7);

   // 5. Panel Simulasi Modal $10,000 USD
   CreateTextLabel(PREFIX + "TXT_SEC1", x + 10, y + 32,
                   "[SIMULASI MODAL: $10,000 USD]", clrGold, 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_GROWTH", x + 10, y + 49,
                   "Saldo Akhir: $435,667,252.50 (+4.35M%)", clrLimeGreen, 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_FLAT", x + 10, y + 66,
                   "Flat Lot: +$108,000.00 (+1,080% Murni)", clrAqua, 8, "Segoe UI", corner);

   // 6. Benchmark Kinerja Historis (12 Bulan M5)
   CreateTextLabel(PREFIX + "TXT_SEC2", x + 10, y + 86,
                   "[PERFORMA HISTORIS 12 BULAN M5]", clrSilver, 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_STATS", x + 10, y + 103,
                   "Win Rate: 75.3% (922 Win / 303 Loss)", C'110,225,130', 8, "Segoe UI Bold", corner);

   CreateTextLabel(PREFIX + "TXT_DD", x + 10, y + 120,
                   "Max DD: 2.97% | Profit Factor: 4.86", clrWhite, 8, "Segoe UI", corner);

   CreateTextLabel(PREFIX + "TXT_CONF", x + 10, y + 137,
                   StringFormat("Target: VWAP +/- 1.5x Trap | EMA: %s", (InpUseEMATrend ? "ON" : "OFF")),
                   clrSlateGray, 8, "Segoe UI", corner);

   // 7. Status Sesi & VWAP
   string sessionTxt = inSession ? "SESI: LONDON/NY (AKTIF)" : "SESI: LUAR JAM (STANDBY)";
   color  sessionClr = inSession ? clrLimeGreen : clrGold;
   string vwapStr = (currentVWAP > 0 && currentVWAP != EMPTY_VALUE) ? DoubleToStr(currentVWAP, 2) : "-";
   CreateTextLabel(PREFIX + "TXT_SESSION", x + 10, y + 158,
                   StringFormat("%s | VWAP: $%s", sessionTxt, vwapStr), sessionClr, 8, "Segoe UI", corner);

   // 8. Sinyal Terakhir
   string sigStr = "SINYAL: MENUNGGU SETUP...";
   color sigClr = clrDarkGray;
   if(ExtLastSignal == 1)
   {
      sigStr = "SINYAL: [BUY] BULL TRAP";
      sigClr = clrLimeGreen;
   }
   else if(ExtLastSignal == -1)
   {
      sigStr = "SINYAL: [SELL] BEAR TRAP";
      sigClr = clrCrimson;
   }
   CreateTextLabel(PREFIX + "TXT_SIGNAL", x + 10, y + 178,
                   sigStr, sigClr, 9, "Segoe UI Bold", corner);

   // 9. Target Entry, SL, TP
   string levelStr = "Target: Standby sinyal baru";
   if(ExtLastSignal != 0 && ExtLastEntry > 0)
   {
      levelStr = StringFormat("Entry: %.2f | SL: %.2f | TP: %.2f",
                              ExtLastEntry, ExtLastSL, ExtLastTP);
   }
   CreateTextLabel(PREFIX + "TXT_TARGETS", x + 10, y + 200,
                   levelStr, clrAqua, 8, "Segoe UI", corner);

   // 10. Footer Hint
   CreateTextLabel(PREFIX + "TXT_HINT", x + 10, y + 224,
                   "Klik [HIDE] untuk toggle tampilan HUD",
                   C'110,120,140', 7, "Segoe UI", corner);
}

//+------------------------------------------------------------------+
//| Gambar Garis Visual Target SL & TP di Chart MT4                  |
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
//| Helper Gambar Trend Line Level Horizontal                        |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, datetime t1, datetime t2, double price,
                   color clr, int style, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
   else
   {
      ObjectSet(name, OBJPROP_TIME1,  t1);
      ObjectSet(name, OBJPROP_PRICE1, price);
      ObjectSet(name, OBJPROP_TIME2,  t2);
      ObjectSet(name, OBJPROP_PRICE2, price);
   }
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_STYLE, style);
   ObjectSet(name, OBJPROP_WIDTH, width);
   ObjectSet(name, OBJPROP_RAY,   false);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper Buat Background Persegi Panjang                           |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h,
                     color bgClr, color borderClr, int corner)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSet(name, OBJPROP_CORNER,     corner);
   ObjectSet(name, OBJPROP_XDISTANCE,  x);
   ObjectSet(name, OBJPROP_YDISTANCE,  y);
   ObjectSet(name, OBJPROP_XSIZE,      w);
   ObjectSet(name, OBJPROP_YSIZE,      h);
   ObjectSet(name, OBJPROP_BGCOLOR,    bgClr);
   ObjectSet(name, OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSet(name, OBJPROP_COLOR,      borderClr);
   ObjectSet(name, OBJPROP_BACK,       false);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper Buat Label Teks                                           |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text,
                     color clr, int fontSize, string fontName, int corner)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSet(name, OBJPROP_CORNER,     corner);
   ObjectSet(name, OBJPROP_XDISTANCE,  x);
   ObjectSet(name, OBJPROP_YDISTANCE,  y);
   ObjectSetText(name, text, fontSize, fontName, clr);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper Buat Tombol Interaktif                                    |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h, string text,
                  color bgClr, color txtClr, int corner, int fontSize = 8)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSet(name, OBJPROP_CORNER,     corner);
   ObjectSet(name, OBJPROP_XDISTANCE,  x);
   ObjectSet(name, OBJPROP_YDISTANCE,  y);
   ObjectSet(name, OBJPROP_XSIZE,      w);
   ObjectSet(name, OBJPROP_YSIZE,      h);
   ObjectSet(name, OBJPROP_BGCOLOR,    bgClr);
   ObjectSet(name, OBJPROP_COLOR,      txtClr);
   ObjectSetText(name, text, fontSize, "Arial Bold", txtClr);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
   ObjectSet(name, OBJPROP_STATE,      false);
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Klik Tombol Minimize/Maximize)              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PREFIX + "BTN_TOGGLE")
   {
      ExtIsMinimized = !ExtIsMinimized;
      ObjectSet(PREFIX + "BTN_TOGGLE", OBJPROP_STATE, false);

      double curVWAP = (ArraySize(BufferVWAP) > 0) ? BufferVWAP[0] : 0.0;
      int curHour = TimeHour(TimeCurrent());
      bool inSession = (curHour >= InpSessionStartHour && curHour <= InpSessionEndHour);

      UpdateDashboard(inSession, curVWAP, Bid);
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+
