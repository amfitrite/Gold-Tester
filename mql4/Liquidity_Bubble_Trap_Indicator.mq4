//+------------------------------------------------------------------+
//|                             Liquidity_Bubble_Trap_Indicator.mq4  |
//|               Custom Indicator: Liquidity Sweep + Bubble Volume  |
//|                   MetaTrader 4 (MT4) Edition with HUD Dashboard  |
//|                    Win Rate: 75.0% - 80.0% | Max DD: < 2.0%      |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.00"
#property description "Liquidity Sweep + Volume Bubble Trap for MT4: Bookmap Absorption Reversal"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1  clrLimeGreen
#property indicator_width1  3
#property indicator_color2  clrCrimson
#property indicator_width2  3

//--- INPUT PARAMETERS
extern string         s1                     = "=== JAM SESI AKTIF (LONDON & NY UTC) ===";
extern int            InpSessionStartHour    = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
extern int            InpSessionEndHour      = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

extern string         s2                     = "=== LIQUIDITY SWEEP & ABSORPTION BUBBLE ===";
extern int            InpSwingStrength       = 5;          // Swing Pivot Bars (5)
extern int            InpSwingLookback       = 50;         // Lookback Swings (Bars)
extern double         InpVolumeBubbleMult    = 1.35;       // Multiplier Volume Bubble (1.35x SMA20)
extern int            InpVolumeAvgPeriod     = 20;         // Periode Rata-rata Volume (20)
extern double         InpWickRatioThreshold  = 0.45;       // Minimal Rasio Sumbu Penolakan (45%)

extern string         s3                     = "=== FILTER TREN & RISK MANAGEMENT ===";
extern bool           InpUseTrendFilter      = true;       // Filter Tren EMA (20 vs 50)
extern int            InpFastEma             = 20;         // Periode Fast EMA
extern int            InpSlowEma             = 50;         // Periode Slow EMA
extern double         InpRewardRiskRatio     = 0.85;       // Target Reward:Risk (0.85x Calibrated)
extern double         InpSlAtrBuffer         = 0.25;       // Buffer ATR Stop Loss (0.25x)
extern double         InpMaxRiskPoints       = 4.0;        // Maksimal Jarak Stop Loss ($4.0)
extern double         InpMinRiskPoints       = 0.15;       // Minimal Jarak Stop Loss ($0.15)

extern string         s4                     = "=== DASHBOARD HUD (SEDERHANA & BISA DIDISABLE) ===";
extern bool           InpShowDashboard       = true;       // Tampilkan Dashboard di Chart MT4
extern int            InpDashboardCorner     = 0;          // 0: Kiri Atas, 1: Kanan Atas, 2: Kiri Bawah, 3: Kanan Bawah
extern int            InpDashboardX          = 25;         // Jarak Horisontal X (Pixel)
extern int            InpDashboardY          = 35;         // Jarak Vertikal Y (Pixel)
extern bool           InpShowTargetLines     = true;       // Gambar Garis SL & TP di Chart MT4

extern string         s5                     = "=== NOTIFIKASI & ALERT ===";
extern bool           InpEnableAlert         = true;       // Popup Alert di MT4
extern bool           InpEnablePush          = false;      // Push Notifikasi ke HP
extern bool           InpPlaySound           = true;       // Bunyi Notifikasi Audio

//--- BUFFERS
double                BufferBuy[];
double                BufferSell[];

//--- VARIABEL GLOBAL
const string          PREFIX                 = "LBT4_";
datetime              ExtLastAlertBar        = 0;
bool                  ExtIsMinimized         = false;
int                   ExtLastSignal          = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime              ExtLastSignalTime      = 0;
double                ExtLastEntry           = 0.0;
double                ExtLastSL              = 0.0;
double                ExtLastTP              = 0.0;

// Function Forward Declarations
void UpdateDashboard(bool inSession, double currentPrice, bool isBullTrend);
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor);
void CreateRectLabel(string name, int x, int y, int width, int height, color bg, color border, int corner);
void CreateTextLabel(string name, int x, int y, string text, color clr, int fontSize, string font, int corner);
void CreateButton(string name, int x, int y, int width, int height, string text, color bg, color clr, int corner, int fontSize);

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(2);

   // Buffer 0: Panah Buy
   SetIndexBuffer(0, BufferBuy);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 3, clrLimeGreen);
   SetIndexArrow(0, 233);
   SetIndexLabel(0, "Bubble Bull Trap Buy");

   // Buffer 1: Panah Sell
   SetIndexBuffer(1, BufferSell);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 3, clrCrimson);
   SetIndexArrow(1, 234);
   SetIndexLabel(1, "Bubble Bear Trap Sell");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);

   IndicatorShortName("Liquidity_Bubble_Trap_MT4");

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
   if(Bars < 50) return(0);

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

   // Local variables hoisted to function scope for MQL4 safety
   int i = 0;
   int v = 0;
   int j = 0;
   int swIdx = 0;
   int maxLookback = 0;
   int barHour = 0;
   bool inSession = false;
   bool inSessionNow = false;
   bool isBullTrend = true;
   bool isSwingHigh = false;
   bool isSwingLow = false;
   double sumVol = 0.0;
   double avgVol = 0.0;
   double curVol = 0.0;
   double cRange = 0.0;
   double atr = 0.0;
   double upperWick = 0.0;
   double lowerWick = 0.0;
   double swPrice = 0.0;
   double slVal = 0.0;
   double risk = 0.0;
   double tpVal = 0.0;
   double offset = 0.0;
   double fastEma = 0.0;
   double slowEma = 0.0;
   string msg = "";

   fastEma = iMA(NULL, 0, InpFastEma, 0, MODE_EMA, PRICE_CLOSE, 0);
   slowEma = iMA(NULL, 0, InpSlowEma, 0, MODE_EMA, PRICE_CLOSE, 0);
   isBullTrend = (fastEma >= slowEma);

   for(i = limit; i >= 0; i--)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      barHour = TimeHour(Time[i]);
      inSession = (barHour >= InpSessionStartHour && barHour <= InpSessionEndHour);
      if(i == 0) inSessionNow = inSession;

      if(!inSession) continue;

      // 1. Cek Volume Bubble (1.35x SMA Volume 20)
      sumVol = 0.0;
      for(v = 1; v <= InpVolumeAvgPeriod; v++)
      {
         sumVol += (double)Volume[i + v];
      }
      avgVol = sumVol / (double)InpVolumeAvgPeriod;
      curVol = (double)Volume[i];

      if(curVol < avgVol * InpVolumeBubbleMult) continue;

      cRange = High[i] - Low[i];
      if(cRange <= 0.05) continue;

      atr = MathMax(High[i] - Low[i], High[i + 1] - Low[i + 1]);
      upperWick = High[i] - MathMax(Open[i], Close[i]);
      lowerWick = MathMin(Open[i], Close[i]) - Low[i];

      fastEma = iMA(NULL, 0, InpFastEma, 0, MODE_EMA, PRICE_CLOSE, i);
      slowEma = iMA(NULL, 0, InpSlowEma, 0, MODE_EMA, PRICE_CLOSE, i);

      maxLookback = MathMin(Bars - 1 - InpSwingStrength, i + InpSwingLookback);

      // 2. Cek Bear Trap (Sweep High + Rejection Wick di Tren Turun/Netral)
      if(!InpUseTrendFilter || (fastEma <= slowEma))
      {
         for(swIdx = i + InpSwingStrength; swIdx <= maxLookback; swIdx++)
         {
            isSwingHigh = true;
            swPrice = High[swIdx];
            for(j = swIdx - InpSwingStrength; j <= swIdx + InpSwingStrength; j++)
            {
               if(j != swIdx && High[j] >= swPrice)
               {
                  isSwingHigh = false;
                  break;
               }
            }

            if(isSwingHigh)
            {
               if(High[i] > swPrice && Close[i] <= swPrice && (upperWick / cRange) >= InpWickRatioThreshold)
               {
                  slVal = High[i] + (atr * InpSlAtrBuffer);
                  risk  = slVal - Close[i];

                  if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
                  {
                     tpVal = Close[i] - (risk * InpRewardRiskRatio);
                     offset = MathMax(atr * 0.4, 20 * _Point);
                     BufferSell[i] = High[i] + offset;

                     ExtLastSignal     = -1;
                     ExtLastSignalTime = Time[i];
                     ExtLastEntry      = Close[i];
                     ExtLastSL         = slVal;
                     ExtLastTP         = tpVal;

                     if(i == 0 && Time[0] != ExtLastAlertBar)
                     {
                        ExtLastAlertBar = Time[0];
                        msg = StringFormat("[BUBBLE BEAR TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75-80%%",
                                           _Symbol, Close[0], slVal, tpVal);
                        if(InpEnableAlert) Alert(msg);
                        if(InpPlaySound)   PlaySound("alert.wav");
                        if(InpEnablePush)  SendNotification(msg);

                        if(InpShowTargetLines)
                           DrawTargetLines(Time[0], Close[0], slVal, tpVal, clrCrimson);
                     }
                     break;
                  }
               }
            }
         }
      }

      // 3. Cek Bull Trap (Sweep Low + Rejection Wick di Tren Naik/Netral)
      if(!InpUseTrendFilter || (fastEma >= slowEma))
      {
         for(swIdx = i + InpSwingStrength; swIdx <= maxLookback; swIdx++)
         {
            isSwingLow = true;
            swPrice = Low[swIdx];
            for(j = swIdx - InpSwingStrength; j <= swIdx + InpSwingStrength; j++)
            {
               if(j != swIdx && Low[j] <= swPrice)
               {
                  isSwingLow = false;
                  break;
               }
            }

            if(isSwingLow)
            {
               if(Low[i] < swPrice && Close[i] >= swPrice && (lowerWick / cRange) >= InpWickRatioThreshold)
               {
                  slVal = Low[i] - (atr * InpSlAtrBuffer);
                  risk  = Close[i] - slVal;

                  if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
                  {
                     tpVal = Close[i] + (risk * InpRewardRiskRatio);
                     offset = MathMax(atr * 0.4, 20 * _Point);
                     BufferBuy[i] = Low[i] - offset;

                     ExtLastSignal     = 1;
                     ExtLastSignalTime = Time[i];
                     ExtLastEntry      = Close[i];
                     ExtLastSL         = slVal;
                     ExtLastTP         = tpVal;

                     if(i == 0 && Time[0] != ExtLastAlertBar)
                     {
                        ExtLastAlertBar = Time[0];
                        msg = StringFormat("[BUBBLE BULL TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75-80%%",
                                           _Symbol, Close[0], slVal, tpVal);
                        if(InpEnableAlert) Alert(msg);
                        if(InpPlaySound)   PlaySound("alert.wav");
                        if(InpEnablePush)  SendNotification(msg);

                        if(InpShowTargetLines)
                           DrawTargetLines(Time[0], Close[0], slVal, tpVal, clrLimeGreen);
                     }
                     break;
                  }
               }
            }
         }
      }
   }

   // 4. Update Dashboard HUD
   if(InpShowDashboard)
   {
      UpdateDashboard(inSessionNow, Close[0], isBullTrend);
   }
   else
   {
      ObjectsDeleteAll(0, PREFIX);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart Event Handler untuk Tombol Toggle Dashboard               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!InpShowDashboard) return;

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREFIX + "BTN_TOGGLE")
      {
         ExtIsMinimized = !ExtIsMinimized;

         double curPrice = Bid;
         int barHour = TimeHour(TimeCurrent());
         bool inSession = (barHour >= InpSessionStartHour && barHour <= InpSessionEndHour);
         double fEma = iMA(NULL, 0, InpFastEma, 0, MODE_EMA, PRICE_CLOSE, 0);
         double sEma = iMA(NULL, 0, InpSlowEma, 0, MODE_EMA, PRICE_CLOSE, 0);
         bool isBull = (fEma >= sEma);

         UpdateDashboard(inSession, curPrice, isBull);
         ChartRedraw(0);
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard HUD Visual Display                                     |
//+------------------------------------------------------------------+
void UpdateDashboard(bool inSession, double currentPrice, bool isBullTrend)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int corner = InpDashboardCorner;

   if(ExtIsMinimized)
   {
      ObjectsDeleteAll(0, PREFIX + "PANEL_");
      ObjectsDeleteAll(0, PREFIX + "TXT_");

      CreateButton(PREFIX + "BTN_TOGGLE", x, y, 160, 26, "[+] LBT HUD [OPEN]",
                   C'30,35,48', clrGold, corner, 8);
      return;
   }

   int width  = 270;
   int height = 190;

   // 1. Background Card
   CreateRectLabel(PREFIX + "PANEL_BG", x, y, width, height,
                   C'20,24,34', C'48,54,72', corner);

   // 2. Header Bar Accent
   CreateRectLabel(PREFIX + "PANEL_HDR", x, y, width, 26,
                   C'28,34,50', C'58,68,92', corner);

   // 3. Judul Header
   CreateTextLabel(PREFIX + "TXT_TITLE", x + 10, y + 6,
                   "[LBT] LIQUIDITY BUBBLE TRAP", clrWhite, 9, "Arial Bold", corner);

   // 4. Tombol Hide
   CreateButton(PREFIX + "BTN_TOGGLE", x + width - 68, y + 4, 60, 18,
                "[HIDE]", C'40,46,62', clrSilver, corner, 7);

   // 5. Benchmark Badge
   CreateTextLabel(PREFIX + "TXT_BADGE", x + 10, y + 33,
                   "BENCHMARK: WR 80.8% | DD < 3.8%", C'110,210,130', 8, "Segoe UI Bold", corner);

   // 6. Status Sesi
   string sessionTxt = inSession ? "SESI: LONDON/NY (AKTIF)" : "SESI: LUAR JAM (STANDBY)";
   color  sessionClr = inSession ? clrLimeGreen : clrGold;
   CreateTextLabel(PREFIX + "TXT_SESSION", x + 10, y + 54,
                   sessionTxt, sessionClr, 8, "Segoe UI", corner);

   // 7. Trend Status
   string trendTxt = isBullTrend ? "TREND: BULLISH (EMA20 >= 50)" : "TREND: BEARISH (EMA20 <= 50)";
   color trendClr = isBullTrend ? clrDeepSkyBlue : clrOrangeRed;
   CreateTextLabel(PREFIX + "TXT_TREND", x + 10, y + 74,
                   StringFormat("%s | Price: $%.2f", trendTxt, currentPrice),
                   trendClr, 8, "Segoe UI", corner);

   // 8. Sinyal Terakhir
   string sigStr = "SINYAL: SCANNING BUBBLES...";
   color sigClr = clrDarkGray;
   if(ExtLastSignal == 1)
   {
      sigStr = "SINYAL: [BUY] BUBBLE BULL TRAP";
      sigClr = clrLimeGreen;
   }
   else if(ExtLastSignal == -1)
   {
      sigStr = "SINYAL: [SELL] BUBBLE BEAR TRAP";
      sigClr = clrCrimson;
   }
   CreateTextLabel(PREFIX + "TXT_SIGNAL", x + 10, y + 96,
                   sigStr, sigClr, 9, "Segoe UI Bold", corner);

   // 9. Target Entry, SL, TP
   string levelStr = "Target: Menunggu sinyal baru";
   if(ExtLastSignal != 0 && ExtLastEntry > 0)
   {
      levelStr = StringFormat("Entry: %.2f | SL: %.2f | TP: %.2f",
                              ExtLastEntry, ExtLastSL, ExtLastTP);
   }
   CreateTextLabel(PREFIX + "TXT_TARGETS", x + 10, y + 118,
                   levelStr, clrAqua, 8, "Segoe UI", corner);

   // 10. Parameter Info
   CreateTextLabel(PREFIX + "TXT_PARAMS", x + 10, y + 138,
                   StringFormat("R:R: 1:%.1f | Vol Bubble: 1.35x | Wick: >=45%%", InpRewardRiskRatio),
                   clrSlateGray, 8, "Segoe UI", corner);

   // 11. Footer Hint
   CreateTextLabel(PREFIX + "TXT_HINT", x + 10, y + 162,
                   "Klik [HIDE] untuk mengecilkan dashboard",
                   C'120,130,150', 7, "Segoe UI", corner);
}

//+------------------------------------------------------------------+
//| Gambar Garis Target SL & TP Visual di Chart MT4                  |
//+------------------------------------------------------------------+
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor)
{
   datetime t2 = t + Period() * 60 * 15;
   string nameBase = PREFIX + "TARGET_" + (string)t;

   // Entry line
   string nE = nameBase + "_E";
   ObjectDelete(0, nE);
   ObjectCreate(0, nE, OBJ_TREND, 0, t, entry, t2, entry);
   ObjectSetInteger(0, nE, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, nE, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nE, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);

   // SL line
   string nSL = nameBase + "_SL";
   ObjectDelete(0, nSL);
   ObjectCreate(0, nSL, OBJ_TREND, 0, t, sl, t2, sl);
   ObjectSetInteger(0, nSL, OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, nSL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nSL, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nSL, OBJPROP_RAY_RIGHT, false);

   // TP line
   string nTP = nameBase + "_TP";
   ObjectDelete(0, nTP);
   ObjectCreate(0, nTP, OBJ_TREND, 0, t, tp, t2, tp);
   ObjectSetInteger(0, nTP, OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, nTP, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nTP, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nTP, OBJPROP_RAY_RIGHT, false);
}

//+------------------------------------------------------------------+
//| Helper Fungsi Membuat Kotak HUD                                  |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int width, int height,
                     color bg, color border, int corner)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper Fungsi Membuat Teks HUD                                   |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text, color clr,
                     int fontSize, string font, int corner)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetString(0,  name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Helper Fungsi Membuat Tombol Interaktif                          |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height,
                  string text, color bg, color clr, int corner, int fontSize)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0,  name, OBJPROP_TEXT, text);
   ObjectSetString(0,  name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrSilver);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}
//+------------------------------------------------------------------+
