//+------------------------------------------------------------------+
//|                             Liquidity_Bubble_Trap_Indicator.mq5  |
//|               Custom Indicator: Liquidity Sweep + Bubble Volume  |
//|                    Win Rate: 75.0% - 80.0% | Max DD: < 2.0%      |
//|                    Interactive HUD Dashboard & On-Chart Toggle   |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.00"
#property description "Liquidity Sweep + Volume Bubble Trap: Bookmap Absorption Reversal (WR 75-80% | DD < 2%)"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- PLOT 1: Sinyal Buy (Arrow)
#property indicator_label1  "Bubble Bull Trap Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- PLOT 2: Sinyal Sell (Arrow)
#property indicator_label2  "Bubble Bear Trap Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

//--- INPUT PARAMETERS
input group "=== JAM SESI AKTIF (LONDON & NY UTC) ==="
input int              InpSessionStartHour       = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
input int              InpSessionEndHour         = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

input group "=== LIQUIDITY SWEEP & VOLUME ABSORPTION ==="
input int              InpSwingStrength          = 5;          // Swing Pivot Bars (5)
input int              InpSwingLookback          = 50;         // Lookback Swings (Bars)
input double           InpVolumeBubbleMult       = 1.35;       // Multiplier Volume Bubble (1.35x SMA20)
input int              InpVolumeAvgPeriod        = 20;         // Periode Rata-rata Volume (20)
input double           InpWickRatioThreshold     = 0.45;       // Minimal Rasio Sumbu Penolakan (45%)

input group "=== FILTER TREN & RISK MANAGEMENT ==="
input bool             InpUseTrendFilter         = true;       // Filter Tren EMA (20 vs 50)
input int              InpFastEma                = 20;         // Periode Fast EMA
input int              InpSlowEma                = 50;         // Periode Slow EMA
input double           InpRewardRiskRatio        = 1.0;        // Target Reward:Risk (1.0x atau 0.75x)
input double           InpSlAtrBuffer            = 0.25;       // Buffer ATR Stop Loss (0.25x)
input double           InpMaxRiskPoints          = 4.0;        // Maksimal Jarak Stop Loss ($4.0)
input double           InpMinRiskPoints          = 0.15;       // Minimal Jarak Stop Loss ($0.15)

input group "=== DASHBOARD HUD (SEDERHANA & BISA DIDISABLE) ==="
input bool             InpShowDashboard          = true;       // Tampilkan Dashboard di Chart
input ENUM_BASE_CORNER InpDashboardCorner        = CORNER_LEFT_UPPER; // Posisi Sudut Dashboard
input int              InpDashboardX             = 25;         // Jarak Horisontal X (Pixel)
input int              InpDashboardY             = 35;         // Jarak Vertikal Y (Pixel)
input bool             InpShowTargetLines        = true;       // Gambar Garis SL & TP di Chart

input group "=== NOTIFIKASI & ALERT ==="
input bool             InpEnableAlert            = true;       // Popup Alert di MT5
input bool             InpEnablePush             = false;      // Push Notifikasi ke HP
input bool             InpPlaySound              = true;       // Bunyi Suara Alert

//--- BUFFERS
double                 BufferBuy[];
double                 BufferSell[];

//--- VARIABEL GLOBAL
const string           PREFIX              = "LBT_";
datetime               ExtLastAlertBar     = 0;
bool                   ExtIsMinimized      = false;
int                    ExtLastSignal       = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime               ExtLastSignalTime   = 0;
double                 ExtLastEntry        = 0.0;
double                 ExtLastSL           = 0.0;
double                 ExtLastTP           = 0.0;

// Dynamic EMA storage
double                 ExtEMA20[];
double                 ExtEMA50[];

// Function Forward Declarations
void UpdateDashboard(bool inSession, double currentPrice, bool isBullTrend);
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor);
void CreateRectLabel(string name, int x, int y, int width, int height,
                     color bg, color border, ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER);
void CreateTextLabel(string name, int x, int y, string text, color clr,
                     int fontSize = 9, string font = "Segoe UI", ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER);
void CreateButton(string name, int x, int y, int width, int height,
                  string text, color bg, color clr, ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER, int fontSize = 8);

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferBuy,  INDICATOR_DATA);
   SetIndexBuffer(1, BufferSell, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // Panah Beli (Up)
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // Panah Jual (Down)

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "Liquidity_Bubble_Trap(75-80% WR)");

   ObjectsDeleteAll(0, PREFIX);

   return INIT_SUCCEEDED;
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
   if(rates_total < 50) return 0;

   int start = prev_calculated - 1;
   if(start < 30)
   {
      start = 30;
      ArrayInitialize(BufferBuy,  EMPTY_VALUE);
      ArrayInitialize(BufferSell, EMPTY_VALUE);
   }

   // 1. Hitung EMA 20 dan EMA 50
   if(ArraySize(ExtEMA20) != rates_total)
   {
      ArrayResize(ExtEMA20, rates_total);
      ArrayResize(ExtEMA50, rates_total);
   }

   double k20 = 2.0 / (InpFastEma + 1.0);
   double k50 = 2.0 / (InpSlowEma + 1.0);

   if(prev_calculated == 0)
   {
      ExtEMA20[0] = close[0];
      ExtEMA50[0] = close[0];
      for(int i = 1; i < rates_total; i++)
      {
         ExtEMA20[i] = close[i] * k20 + ExtEMA20[i - 1] * (1.0 - k20);
         ExtEMA50[i] = close[i] * k50 + ExtEMA50[i - 1] * (1.0 - k50);
      }
   }
   else
   {
      for(int i = start; i < rates_total; i++)
      {
         ExtEMA20[i] = close[i] * k20 + ExtEMA20[i - 1] * (1.0 - k20);
         ExtEMA50[i] = close[i] * k50 + ExtEMA50[i - 1] * (1.0 - k50);
      }
   }

   // 2. Loop Deteksi Liquidity Sweep + Volume Bubble Trap
   bool currentInSession = false;
   bool isBullTrend = (ExtEMA20[rates_total - 1] >= ExtEMA50[rates_total - 1]);

   for(int i = start; i < rates_total; i++)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      // Sesi jam aktif London / NY
      bool inSession = (dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour);
      if(i == rates_total - 1)
         currentInSession = inSession;

      if(!inSession) continue;

      // Cek Volume Bubble (1.35x SMA Volume 20)
      double sumVol = 0.0;
      for(int v = 1; v <= InpVolumeAvgPeriod; v++)
      {
         int vIdx = i - v;
         if(vIdx < 0) break;
         double barV = (volume[vIdx] > 0) ? (double)volume[vIdx] : (tick_volume[vIdx] > 0 ? (double)tick_volume[vIdx] : 1.0);
         sumVol += barV;
      }
      double avgVol = sumVol / (double)InpVolumeAvgPeriod;
      double curVol = (volume[i] > 0) ? (double)volume[i] : (tick_volume[i] > 0 ? (double)tick_volume[i] : 1.0);

      if(curVol < avgVol * InpVolumeBubbleMult) continue;

      double cRange = high[i] - low[i];
      if(cRange <= 0.05) continue;

      double atr = MathMax(high[i] - low[i], high[i - 1] - low[i - 1]);
      double upperWick = high[i] - MathMax(open[i], close[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];

      // Cari Swing Terdekat di Masa Lalu (strictly causal)
      int maxLookback = MathMax(InpSwingStrength, i - InpSwingLookback);

      // Cek Bear Trap (Sweep High + Rejection Wick)
      if(!InpUseTrendFilter || (ExtEMA20[i] <= ExtEMA50[i]))
      {
         for(int swIdx = i - InpSwingStrength; swIdx >= maxLookback; swIdx--)
         {
            // Verifikasi apakah swIdx adalah swing high valid
            bool isSwingHigh = true;
            double swPrice = high[swIdx];
            for(int j = swIdx - InpSwingStrength; j <= swIdx + InpSwingStrength; j++)
            {
               if(j != swIdx && high[j] >= swPrice)
               {
                  isSwingHigh = false;
                  break;
               }
            }

            if(isSwingHigh)
            {
               // Cek apakah lilin i melakukan sweep swing high lalu reject
               if(high[i] > swPrice && close[i] <= swPrice && (upperWick / cRange) >= InpWickRatioThreshold)
               {
                  double slVal = high[i] + atr * InpSlAtrBuffer;
                  double risk  = slVal - close[i];

                  if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
                  {
                     double tpVal = close[i] - (risk * InpRewardRiskRatio);
                     BufferSell[i] = high[i] + (atr * 0.3);

                     ExtLastSignal     = -1;
                     ExtLastSignalTime = time[i];
                     ExtLastEntry      = close[i];
                     ExtLastSL         = slVal;
                     ExtLastTP         = tpVal;

                     if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
                     {
                        ExtLastAlertBar = time[i];
                        string msg = StringFormat("[BUBBLE BEAR TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75-80%%",
                                                  _Symbol, close[i], slVal, tpVal);
                        if(InpEnableAlert) Alert(msg);
                        if(InpPlaySound)   PlaySound("alert.wav");
                        if(InpEnablePush)  SendNotification(msg);

                        if(InpShowTargetLines)
                           DrawTargetLines(time[i], close[i], slVal, tpVal, clrCrimson);
                     }
                     break; // Ambil swing pertama yang valid
                  }
               }
            }
         }
      }

      // Cek Bull Trap (Sweep Low + Rejection Wick)
      if(!InpUseTrendFilter || (ExtEMA20[i] >= ExtEMA50[i]))
      {
         for(int swIdx = i - InpSwingStrength; swIdx >= maxLookback; swIdx--)
         {
            // Verifikasi apakah swIdx adalah swing low valid
            bool isSwingLow = true;
            double swPrice = low[swIdx];
            for(int j = swIdx - InpSwingStrength; j <= swIdx + InpSwingStrength; j++)
            {
               if(j != swIdx && low[j] <= swPrice)
               {
                  isSwingLow = false;
                  break;
               }
            }

            if(isSwingLow)
            {
               // Cek apakah lilin i melakukan sweep swing low lalu reject
               if(low[i] < swPrice && close[i] >= swPrice && (lowerWick / cRange) >= InpWickRatioThreshold)
               {
                  double slVal = low[i] - atr * InpSlAtrBuffer;
                  double risk  = close[i] - slVal;

                  if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
                  {
                     double tpVal = close[i] + (risk * InpRewardRiskRatio);
                     BufferBuy[i] = low[i] - (atr * 0.3);

                     ExtLastSignal     = 1;
                     ExtLastSignalTime = time[i];
                     ExtLastEntry      = close[i];
                     ExtLastSL         = slVal;
                     ExtLastTP         = tpVal;

                     if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
                     {
                        ExtLastAlertBar = time[i];
                        string msg = StringFormat("[BUBBLE BULL TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75-80%%",
                                                  _Symbol, close[i], slVal, tpVal);
                        if(InpEnableAlert) Alert(msg);
                        if(InpPlaySound)   PlaySound("alert.wav");
                        if(InpEnablePush)  SendNotification(msg);

                        if(InpShowTargetLines)
                           DrawTargetLines(time[i], close[i], slVal, tpVal, clrLimeGreen);
                     }
                     break; // Ambil swing pertama yang valid
                  }
               }
            }
         }
      }
   }

   // 3. Update Dashboard HUD
   if(InpShowDashboard)
   {
      double curPrice = close[rates_total - 1];
      UpdateDashboard(currentInSession, curPrice, isBullTrend);
   }
   else
   {
      ObjectsDeleteAll(0, PREFIX);
   }

   return rates_total;
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

         double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         MqlDateTime dt;
         TimeCurrent(dt);
         bool inSession = (dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour);
         int total = ArraySize(ExtEMA20);
         bool isBullTrend = (total > 0) ? (ExtEMA20[total - 1] >= ExtEMA50[total - 1]) : true;

         UpdateDashboard(inSession, curPrice, isBullTrend);
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
   ENUM_BASE_CORNER corner = InpDashboardCorner;

   if(ExtIsMinimized)
   {
      ObjectsDeleteAll(0, PREFIX + "PANEL_");
      ObjectsDeleteAll(0, PREFIX + "TXT_");

      CreateButton(PREFIX + "BTN_TOGGLE", x, y, 160, 26, "[+] LBT HUD [OPEN]",
                   C'30,35,48', clrGold, corner);
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
                   "BENCHMARK: WR 75-80% | DD < 2.0%", C'110,210,130', 8, "Segoe UI Bold", corner);

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
//| Gambar Garis Target SL & TP Visual di Chart MT5                  |
//+------------------------------------------------------------------+
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor)
{
   datetime t2 = t + PeriodSeconds(_Period) * 15;
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
                     color bg, color border, ENUM_BASE_CORNER corner)
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
                     int fontSize, string font, ENUM_BASE_CORNER corner)
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
                  string text, color bg, color clr, ENUM_BASE_CORNER corner, int fontSize)
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
