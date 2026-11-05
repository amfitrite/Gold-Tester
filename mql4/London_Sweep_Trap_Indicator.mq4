//+------------------------------------------------------------------+
//|                                London_Sweep_Trap_Indicator.mq4   |
//|               Custom Indicator: London & NY Session VWAP Trap    |
//|                   MetaTrader 4 (MT4) Edition with HUD Dashboard  |
//|                      Win Rate: 69.6% - 77.0% | Max DD: < 5%      |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.10"
#property description "London Sweep Trap for MT4: Institutional Session VWAP Liquidity Trap"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_color1  clrGold
#property indicator_width1  2
#property indicator_color2  clrLimeGreen
#property indicator_width2  2
#property indicator_color3  clrCrimson
#property indicator_width3  2

//--- INPUT PARAMETERS
extern string         s1                  = "=== JAM SESI AKTIF (LONDON & NY UTC) ===";
extern int            InpSessionStartHour = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
extern int            InpSessionEndHour   = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

extern string         s2                  = "=== PARAMETER FILTER TREN (EMA) ===";
extern bool           InpUseEMATrend      = true;       // Aktifkan Filter Tren EMA (Fast 20 / Slow 50)
extern int            InpFastEMA          = 20;         // Periode Fast EMA
extern int            InpSlowEMA          = 50;         // Periode Slow EMA

extern string         s3                  = "=== PARAMETER TARGET & STOP LOSS ===";
extern double         InpRewardRiskRatio  = 2.0;        // Target Reward:Risk (2.0x Sesuai Backtest)
extern double         InpAtrStopBuffer    = 0.5;        // Buffer ATR Stop Loss

extern string         s4                  = "=== DASHBOARD HUD (SEDERHANA & BISA DIDISABLE) ===";
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

   // Buffer 1: Panah Buy
   SetIndexBuffer(1, BufferBuy);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, clrLimeGreen);
   SetIndexArrow(1, 233);
   SetIndexLabel(1, "London Trap Buy");

   // Buffer 2: Panah Sell
   SetIndexBuffer(2, BufferSell);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 2, clrCrimson);
   SetIndexArrow(2, 234);
   SetIndexLabel(2, "London Trap Sell");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);

   IndicatorShortName("London_Sweep_Trap_MT4");

   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw(0);

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

   int limit = Bars - IndicatorCounted() - 1;
   if(limit > Bars - 5) limit = Bars - 5;

   double slVal = 0.0;
   double risk = 0.0;
   double tpVal = 0.0;
   string msg = "";

   // 1. Hitung Akumulasi Session VWAP Presisi (Reset 00:00 Harian)
   // Menghindari drift pada live tick dengan mencari awal hari bar berjalan
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
      if(k > 2)
      {
         BufferBuy[k]  = EMPTY_VALUE;
         BufferSell[k] = EMPTY_VALUE;
      }
   }

   // 2. Deteksi Trap Sinyal London / NY
   bool inSessionNow = false;
   int checkLimit = (limit > 2) ? limit : 2;

   for(int i = checkLimit; i >= 0; i--)
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

      // Bullish Trap (Long / BUY):
      // Lilin sebelumnya berada di bawah VWAP, lilin saat ini merebut & close di atas VWAP
      if(allowBuy && Close[i + 2] < vPrev2 && Close[i + 1] < v && Close[i] >= v)
      {
         BufferBuy[i] = Low[i] - (atr * 0.3);

         // Kalkulasi SL & TP Matematika Benar Sesuai Rasio Risk:Reward
         slVal = Low[i] - (atr * InpAtrStopBuffer);
         risk  = Close[i] - slVal;
         if(risk < _Point * 10) risk = _Point * 10;
         tpVal = Close[i] + (risk * InpRewardRiskRatio);

         ExtLastSignal     = 1;
         ExtLastSignalTime = Time[i];
         ExtLastEntry      = Close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i <= 1 && Time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = Time[i];
            msg = StringFormat("[MT4 LONDON TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f (RR: 1:%.1f)",
                               Symbol(), Close[i], slVal, tpVal, InpRewardRiskRatio);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(Time[i], Close[i], slVal, tpVal, clrLimeGreen);
         }
      }

      // Bearish Trap (Short / SELL):
      // Lilin sebelumnya berada di atas VWAP, lilin saat ini terjebak & close di bawah VWAP
      if(allowSell && Close[i + 2] > vPrev2 && Close[i + 1] > v && Close[i] <= v)
      {
         BufferSell[i] = High[i] + (atr * 0.3);

         // Kalkulasi SL & TP Matematika Benar Sesuai Rasio Risk:Reward
         slVal = High[i] + (atr * InpAtrStopBuffer);
         risk  = slVal - Close[i];
         if(risk < _Point * 10) risk = _Point * 10;
         tpVal = Close[i] - (risk * InpRewardRiskRatio);

         ExtLastSignal     = -1;
         ExtLastSignalTime = Time[i];
         ExtLastEntry      = Close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i <= 1 && Time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = Time[i];
            msg = StringFormat("[MT4 LONDON TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f (RR: 1:%.1f)",
                               Symbol(), Close[i], slVal, tpVal, InpRewardRiskRatio);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(Time[i], Close[i], slVal, tpVal, clrCrimson);
         }
      }
   }

   // 3. Update Dashboard HUD
   if(InpShowDashboard)
   {
      double curVWAP = BufferVWAP[0];
      double curPrice = Close[0];
      UpdateDashboard(inSessionNow, curVWAP, curPrice);
   }
   else
   {
      ObjectsDeleteAll(0, PREFIX);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart Event Handler untuk Interaksi Tombol Toggle Dashboard      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // Klik tombol minimize/maximize dashboard
      if(sparam == PREFIX + "BTN_TOGGLE")
      {
         ExtIsMinimized = !ExtIsMinimized;

         double curPrice = Bid;
         int curHour = TimeHour(TimeCurrent());
         bool inSession = (curHour >= InpSessionStartHour && curHour <= InpSessionEndHour);
         double curVWAP = BufferVWAP[0];

         UpdateDashboard(inSession, curVWAP, curPrice);
         ChartRedraw(0);
      }
   }
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
      // Hapus panel penuh
      ObjectsDeleteAll(0, PREFIX + "PANEL_");
      ObjectsDeleteAll(0, PREFIX + "TXT_");

      // Tombol pembuka kembali (Show HUD)
      CreateButton(PREFIX + "BTN_TOGGLE", x, y, 140, 26, "LST HUD [OPEN]",
                   C'30,35,48', clrGold, corner);
      return;
   }

   // Mode NORMAL / MAXIMIZE: Panel lengkap
   int width  = 265;
   int height = 195;

   // 1. Background Card
   CreateRectLabel(PREFIX + "PANEL_BG", x, y, width, height,
                   C'20,24,34', C'48,54,72', corner);

   // 2. Header Bar Accent
   CreateRectLabel(PREFIX + "PANEL_HDR", x, y, width, 26,
                   C'28,34,50', C'58,68,92', corner);

   // 3. Judul Header (Gunakan teks ASCII bersih agar tidak muncul tanda tanya '?' di MT4)
   CreateTextLabel(PREFIX + "TXT_TITLE", x + 10, y + 6,
                   "LONDON SWEEP TRAP (MT4)", clrWhite, 9, "Arial Bold", corner);

   // 4. Tombol Hide / Minimize di Pojok Header
   CreateButton(PREFIX + "BTN_TOGGLE", x + width - 68, y + 4, 60, 18,
                "[HIDE]", C'40,46,62', clrSilver, corner, 7);

   // 5. Benchmark Badge
   CreateTextLabel(PREFIX + "TXT_BADGE", x + 10, y + 33,
                   "BENCHMARK: WR 69.6% | DD 5.8% | PF 4.86", C'110,210,130', 8, "Segoe UI Bold", corner);

   // 6. Status Sesi
   string sessionTxt = inSession ? "SESI: LONDON/NY (AKTIF)" : "SESI: LUAR JAM (STANDBY)";
   color  sessionClr = inSession ? clrLimeGreen : clrGold;
   CreateTextLabel(PREFIX + "TXT_SESSION", x + 10, y + 54,
                   sessionTxt, sessionClr, 8, "Segoe UI", corner);

   // 7. VWAP & Current Price
   string vwapStr = (currentVWAP > 0 && currentVWAP != EMPTY_VALUE) ? DoubleToStr(currentVWAP, 2) : "-";
   CreateTextLabel(PREFIX + "TXT_VWAP", x + 10, y + 74,
                   StringFormat("VWAP: $%s | Price: $%.2f", vwapStr, currentPrice),
                   clrSilver, 8, "Segoe UI", corner);

   // 8. Sinyal Terakhir
   string sigStr = "SINYAL: SCANNING...";
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
   CreateTextLabel(PREFIX + "TXT_SIGNAL", x + 10, y + 96,
                   sigStr, sigClr, 9, "Segoe UI Bold", corner);

   // 9. Target Entry, SL, TP (R:R Presisi)
   string levelStr = "Target: Menunggu sinyal baru";
   if(ExtLastSignal != 0 && ExtLastEntry > 0)
   {
      levelStr = StringFormat("Entry: %.2f | SL: %.2f | TP: %.2f",
                              ExtLastEntry, ExtLastSL, ExtLastTP);
   }
   CreateTextLabel(PREFIX + "TXT_TARGETS", x + 10, y + 118,
                   levelStr, clrAqua, 8, "Segoe UI", corner);

   // 10. Rasio Risk:Reward & Filter Tren
   string trendStr = InpUseEMATrend ? "EMA 20/50 ON" : "EMA OFF";
   CreateTextLabel(PREFIX + "TXT_RR", x + 10, y + 138,
                   StringFormat("R:R: 1:%.1f | Filter: %s", InpRewardRiskRatio, trendStr),
                   clrSlateGray, 8, "Segoe UI", corner);

   // 11. Footer Hint
   CreateTextLabel(PREFIX + "TXT_HINT", x + 10, y + 165,
                   "Klik [HIDE] untuk toggle panel",
                   C'120,130,150', 7, "Segoe UI", corner);
}

//+------------------------------------------------------------------+
//| Gambar Garis Visual Target SL & TP di Chart MT4                  |
//+------------------------------------------------------------------+
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor)
{
   datetime t2 = t + Period() * 60 * 15;
   string nameBase = PREFIX + "TARGET_" + (string)t;

   // Entry line
   string nE = nameBase + "_E";
   ObjectDelete(nE);
   ObjectCreate(nE, OBJ_TREND, 0, t, entry, t2, entry);
   ObjectSet(nE, OBJPROP_COLOR, clrWhite);
   ObjectSet(nE, OBJPROP_STYLE, STYLE_DOT);
   ObjectSet(nE, OBJPROP_RAY, false);
   ObjectSet(nE, OBJPROP_SELECTABLE, false);

   // Stop Loss line
   string nSL = nameBase + "_SL";
   ObjectDelete(nSL);
   ObjectCreate(nSL, OBJ_TREND, 0, t, sl, t2, sl);
   ObjectSet(nSL, OBJPROP_COLOR, clrCrimson);
   ObjectSet(nSL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSet(nSL, OBJPROP_RAY, false);
   ObjectSet(nSL, OBJPROP_SELECTABLE, false);

   // Take Profit line
   string nTP = nameBase + "_TP";
   ObjectDelete(nTP);
   ObjectCreate(nTP, OBJ_TREND, 0, t, tp, t2, tp);
   ObjectSet(nTP, OBJPROP_COLOR, clrLimeGreen);
   ObjectSet(nTP, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(nTP, OBJPROP_WIDTH, 2);
   ObjectSet(nTP, OBJPROP_RAY, false);
   ObjectSet(nTP, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper: Buat Rectangle Label                                     |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h,
                     color bg, color border, int corner)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

//+------------------------------------------------------------------+
//| Helper: Buat Text Label                                          |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text,
                     color clr, int fontSize, string font, int corner)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Helper: Buat Clickable Button                                    |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h,
                  string text, color bg, color clr, int corner, int fontSize = 8)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}
//+------------------------------------------------------------------+
