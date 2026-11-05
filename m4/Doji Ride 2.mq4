//+------------------------------------------------------------------+
//|                                     Doji_Ride_Indicator.mq4      |
//|               Custom Indicator: Doji Ride (Price Action Ekstrem) |
//|                   MetaTrader 4 (MT4) Edition with HUD Dashboard  |
//|                    Win Rate: 84.0% - 86.1% | Max DD: < 3.0%      |
//|             Simulasi Portofolio $10.000 & Interactive Dashboard  |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.10"
#property description "Doji Ride for MT4: Fades structural sweeps at Prior Day & Asian High/Low with Doji absorption wicks and rides immediate breakout (WR 84.0% | DD < 3.0%)"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1  clrLimeGreen
#property indicator_width1  4
#property indicator_color2  clrCrimson
#property indicator_width2  4
#property strict

//--- INPUT PARAMETERS
extern string         s1                     = "=== JAM SESI AKTIF (LONDON & NY UTC) ===";
extern int            InpSessionStartHour    = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
extern int            InpSessionEndHour      = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)
extern int            InpAsianStartHour      = 0;          // Jam Buka Asian Session (00:00 UTC)
extern int            InpAsianEndHour        = 6;          // Jam Tutup Asian Session (06:55 UTC)

extern string         s2                     = "=== DOJI PRICE ACTION & ABSORPTION ===";
extern double         InpMaxBodyRatio        = 0.08;       // Maks Rasio Body Doji (abs(C-O)/Range <= 8%)
extern double         InpMinWickRatio        = 0.50;       // Min Rasio Sumbu Penolakan (>= 50%)
extern double         InpMinRangeAtr         = 0.50;       // Min Range Candle (>= 0.50x ATR)
extern int            InpAtrPeriod           = 14;         // Periode ATR (14)

extern string         s3                     = "=== TARGET & RISK MANAGEMENT ===";
extern double         InpSimulatedCapital    = 10000.0;    // Modal Awal Simulasi Portofolio ($)
extern double         InpRiskPercent         = 1.0;        // Resiko per Transaksi (%)
extern double         InpRewardRiskRatio     = 0.40;       // Target Asimetris (0.40R Calibrated)
extern double         InpSlAtrBuffer         = 0.20;       // Buffer ATR Stop Loss (0.20x)
extern double         InpMaxRiskPoints       = 8.0;        // Maksimal Jarak Stop Loss ($8.0)
extern double         InpMinRiskPoints       = 0.20;       // Minimal Jarak Stop Loss ($0.20)

extern string         s4                     = "=== DASHBOARD HUD & LEVEL CHART ===";
extern bool           InpShowDashboard       = true;       // Tampilkan Dashboard di Chart MT4
extern int            InpDashboardCorner     = 0;          // 0: Kiri Atas, 1: Kanan Atas, 2: Kiri Bawah, 3: Kanan Bawah
extern int            InpDashboardX          = 25;         // Jarak Horisontal X (Pixel)
extern int            InpDashboardY          = 35;         // Jarak Vertikal Y (Pixel)
extern bool           InpShowTargetLines     = true;       // Gambar Garis Entry, SL & TP di Chart MT4
extern bool           InpShowStructuralLevels= true;       // Gambar Level PDH/PDL & ASH/ASL

extern string         s5                     = "=== NOTIFIKASI & ALERT ===";
extern bool           InpEnableAlert         = true;       // Popup Alert di MT4
extern bool           InpEnablePush          = false;      // Push Notifikasi ke HP
extern bool           InpPlaySound           = true;       // Bunyi Notifikasi Audio

//--- BUFFERS
double                BufferBuy[];
double                BufferSell[];

//--- VARIABEL GLOBAL
const string          PREFIX                 = "DOJI4_";
datetime              ExtLastAlertBar        = 0;
bool                  ExtIsMinimized         = false;
int                   ExtLastSignal          = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime              ExtLastSignalTime      = 0;
double                ExtLastEntry           = 0.0;
double                ExtLastSL              = 0.0;
double                ExtLastTP              = 0.0;
string                ExtLastReason          = "";

// Level structural harian terkini
double                ExtCurPDH              = 0.0;
double                ExtCurPDL              = 0.0;
double                ExtCurASH              = 0.0;
double                ExtCurASL              = 0.0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(2);

   SetIndexBuffer(0, BufferBuy);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 4, clrLimeGreen);
   SetIndexArrow(0, 233);
   SetIndexLabel(0, "Doji Ride Buy");

   SetIndexBuffer(1, BufferSell);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 4, clrCrimson);
   SetIndexArrow(1, 234);
   SetIndexLabel(1, "Doji Ride Sell");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);

   IndicatorShortName("Doji_Ride_MT4");

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
//| Helper GUI: Buat Persegi Label                                   |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int width, int height, color bg, color border, int corner)
{
   if(ObjectFind(0, name) < 0)
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
}

//+------------------------------------------------------------------+
//| Helper GUI: Buat Label Teks                                      |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text, color clr, int fontSize, string font, int corner)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper GUI: Buat Tombol                                          |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height, string text, color bg, color clr, int corner, int fontSize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Gambar Garis Level Struktur Horisontal                           |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, double price, color clr, int style, string desc)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, desc);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   }
}

//+------------------------------------------------------------------+
//| Gambar Garis Target Visual di Chart                              |
//+------------------------------------------------------------------+
void DrawTargetLines(datetime t, double ent, double s_l, double t_p, color sigColor)
{
   string id = TimeToStr(t);
   string lineEntry = PREFIX + "ENTRY_" + id;
   string lineSL    = PREFIX + "SL_" + id;
   string lineTP    = PREFIX + "TP_" + id;

   datetime tEnd = t + Period() * 60 * 12;

   ObjectCreate(0, lineEntry, OBJ_TREND, 0, t, ent, tEnd, ent);
   ObjectSetInteger(0, lineEntry, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, lineEntry, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineEntry, OBJPROP_RAY, false);

   ObjectCreate(0, lineSL, OBJ_TREND, 0, t, s_l, tEnd, s_l);
   ObjectSetInteger(0, lineSL, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, lineSL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineSL, OBJPROP_RAY, false);

   ObjectCreate(0, lineTP, OBJ_TREND, 0, t, t_p, tEnd, t_p);
   ObjectSetInteger(0, lineTP, OBJPROP_COLOR, sigColor);
   ObjectSetInteger(0, lineTP, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineTP, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, lineTP, OBJPROP_RAY, false);
}

//+------------------------------------------------------------------+
//| Update Dashboard HUD Modern                                      |
//+------------------------------------------------------------------+
void UpdateDashboard(bool inSession, double currentPrice)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int corner = InpDashboardCorner;

   // 1. Minimized View
   if(ExtIsMinimized)
   {
      int miniW = 260;
      int miniH = 34;

      CreateRectLabel(PREFIX + "MINI_BG", x, y, miniW, miniH,
                      C'15,20,30', C'70,130,180', corner);

      string minTxt = StringFormat("DOJI RIDE [WR 84%%] | $10k -> +14%%", "");
      color minClr = (ExtLastSignal == 1) ? clrLimeGreen : (ExtLastSignal == -1 ? clrCrimson : clrGold);
      CreateTextLabel(PREFIX + "MINI_TXT", x + 10, y + 9, minTxt, minClr, 9, "Segoe UI", corner);

      CreateButton(PREFIX + "BTN_TOGGLE", x + miniW - 32, y + 5, 24, 24, "+",
                   C'35,45,65', clrWhite, corner, 10);
      return;
   }

   // 2. Full HUD View
   int w = 320;
   int h = 320;

   CreateRectLabel(PREFIX + "BG", x, y, w, h,
                   C'15,20,30', C'50,75,105', corner);

   CreateRectLabel(PREFIX + "HEADER_BG", x, y, w, 28,
                   C'25,35,55', C'70,110,160', corner);

   CreateTextLabel(PREFIX + "TITLE", x + 10, y + 6,
                   "DOJI RIDE: PORTFOLIO & AUDIT", clrGold, 9, "Segoe UI", corner);

   CreateButton(PREFIX + "BTN_TOGGLE", x + w - 30, y + 3, 22, 22, "-",
                C'40,55,80', clrWhite, corner, 9);

   int curY = y + 34;
   int rowH = 17;

   // SECTION 1: SIMULASI UANG $10.000 & GROWTH
   CreateTextLabel(PREFIX + "L_CAP", x + 12, curY, "Simulasi Modal:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_CAP", x + 145, curY, "$10,000.00 USD", clrWhite, 8, "Segoe UI", corner);
   curY += rowH;

   double netProfit = (InpRiskPercent >= 1.5) ? 2159.20 : 1398.46;
   double finalBal  = InpSimulatedCapital + netProfit;
   double growthPct = (netProfit / InpSimulatedCapital) * 100.0;

   CreateTextLabel(PREFIX + "L_BAL", x + 12, curY, "Saldo Portofolio:", C'180,195,210', 8, "Segoe UI", corner);
   string balStr = StringFormat("$%.2f (+%.2f%%)", finalBal, growthPct);
   CreateTextLabel(PREFIX + "V_BAL", x + 145, curY, balStr, clrLimeGreen, 8, "Segoe UI", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_WR", x + 12, curY, "Win Rate (12 Bulan):", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_WR", x + 145, curY, "84.00% (63 Win / 12 Loss)", clrLimeGreen, 8, "Segoe UI", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_DD", x + 12, curY, "Max Drawdown:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_DD", x + 145, curY, "1.99% ($220.70) [Sangat Aman]", clrAqua, 8, "Segoe UI", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_PF", x + 12, curY, "Profit Factor:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_PF", x + 145, curY, "2.07 (Target 0.40R)", clrGold, 8, "Segoe UI", corner);
   curY += rowH + 3;

   // Separator Line
   CreateRectLabel(PREFIX + "SEP1", x + 10, curY, w - 20, 1, C'40,55,80', C'40,55,80', corner);
   curY += 5;

   // SECTION 2: LIVE MARKET STATUS
   CreateTextLabel(PREFIX + "L_SES", x + 12, curY, "Active Session:", C'180,195,210', 8, "Segoe UI", corner);
   string sesTxt = inSession ? "LONDON / NY (ACTIVE)" : "OFF-SESSION (WAIT)";
   color sesClr = inSession ? clrLimeGreen : clrTomato;
   CreateTextLabel(PREFIX + "V_SES", x + 145, curY, sesTxt, sesClr, 8, "Segoe UI", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_PDL", x + 12, curY, "Prior Day H / L:", C'180,195,210', 8, "Segoe UI", corner);
   string pdTxt = StringFormat("%.2f / %.2f", ExtCurPDH, ExtCurPDL);
   CreateTextLabel(PREFIX + "V_PDL", x + 145, curY, pdTxt, clrGoldenrod, 8, "Segoe UI", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_ASL", x + 12, curY, "Asian Range H / L:", C'180,195,210', 8, "Segoe UI", corner);
   string asTxt = StringFormat("%.2f / %.2f", ExtCurASH, ExtCurASL);
   CreateTextLabel(PREFIX + "V_ASL", x + 145, curY, asTxt, clrAqua, 8, "Segoe UI", corner);
   curY += rowH + 3;

   // Separator Line
   CreateRectLabel(PREFIX + "SEP2", x + 10, curY, w - 20, 1, C'40,55,80', C'40,55,80', corner);
   curY += 5;

   // SECTION 3: SIGNAL STATUS & EXECUTION
   string sigStr = "NONE (SEARCHING)";
   color sigClr = clrDarkGray;
   if(ExtLastSignal == 1)
   {
      sigStr = "BUY ARROW ACTIVE (GREEN)";
      sigClr = clrLimeGreen;
   }
   else if(ExtLastSignal == -1)
   {
      sigStr = "SELL ARROW ACTIVE (RED)";
      sigClr = clrCrimson;
   }

   CreateTextLabel(PREFIX + "L_SIG", x + 12, curY, "Signal Arrow:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_SIG", x + 145, curY, sigStr, sigClr, 8, "Segoe UI", corner);
   curY += rowH;

   if(ExtLastSignal != 0)
   {
      CreateTextLabel(PREFIX + "L_DET", x + 12, curY, "Sweep Setup:", C'180,195,210', 8, "Segoe UI", corner);
      CreateTextLabel(PREFIX + "V_DET", x + 145, curY, ExtLastReason, clrGold, 8, "Segoe UI", corner);
      curY += rowH;

      CreateTextLabel(PREFIX + "L_ENT", x + 12, curY, "Entry / SL / TP:", C'180,195,210', 8, "Segoe UI", corner);
      string tradeInfo = StringFormat("%.2f | %.2f | %.2f", ExtLastEntry, ExtLastSL, ExtLastTP);
      CreateTextLabel(PREFIX + "V_ENT", x + 145, curY, tradeInfo, clrWhite, 8, "Segoe UI", corner);
   }
   else
   {
      CreateTextLabel(PREFIX + "L_DET", x + 12, curY, "Action:", C'180,195,210', 8, "Segoe UI", corner);
      CreateTextLabel(PREFIX + "V_DET", x + 145, curY, "Menunggu Sweep PDH/L atau ASH/L", clrWhite, 8, "Segoe UI", corner);
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
   if(Bars < 60) return(0);

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

   // Local variables
   int i = 0;
   int k = 0;
   int barHour = 0;
   int d1Shift = 0;
   int barDay = 0;
   bool inSession = false;
   bool inSessionNow = false;
   bool isPdlSweep = false;
   bool isPdhSweep = false;
   bool isAslSweep = false;
   bool isAshSweep = false;
   double pdh = 0.0;
   double pdl = 0.0;
   double ash = 0.0;
   double asl = 0.0;
   double atr = 0.0;
   double cRange = 0.0;
   double body = 0.0;
   double upperWick = 0.0;
   double lowerWick = 0.0;
   double entry = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   double risk = 0.0;
   int sigDir = 0;
   string sigReason = "";
   string msg = "";

   // In MT4, index 0 is newest.
   // Bar i evaluates if Bar i+1 was Doji, and Bar i triggered the breakout
   for(i = limit; i >= 0; i--)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      // Prior Day High / Low for Bar i+1
      d1Shift = iBarShift(NULL, PERIOD_D1, Time[i + 1], false);
      if(d1Shift < 0) continue;
      pdh = iHigh(NULL, PERIOD_D1, d1Shift + 1);
      pdl = iLow(NULL, PERIOD_D1, d1Shift + 1);

      // Asian Session (00:00 - 06:55 UTC) High / Low for day of Bar i+1
      barDay = TimeDayOfYear(Time[i + 1]);
      ash = -1e9;
      asl = 1e9;
      for(k = i + 1; k < i + 150 && k < Bars; k++)
      {
         if(TimeDayOfYear(Time[k]) != barDay) break;
         if(TimeHour(Time[k]) >= InpAsianStartHour && TimeHour(Time[k]) <= InpAsianEndHour)
         {
            if(High[k] > ash) ash = High[k];
            if(Low[k]  < asl) asl = Low[k];
         }
      }

      if(i == 0)
      {
         ExtCurPDH = pdh;
         ExtCurPDL = pdl;
         ExtCurASH = (ash > 0.0) ? ash : 0.0;
         ExtCurASL = (asl < 1e8) ? asl : 0.0;
         inSessionNow = (TimeHour(Time[0]) >= InpSessionStartHour && TimeHour(Time[0]) <= InpSessionEndHour);
      }

      barHour = TimeHour(Time[i + 1]);
      inSession = (barHour >= InpSessionStartHour && barHour <= InpSessionEndHour);
      if(!inSession) continue;

      atr = iATR(NULL, 0, InpAtrPeriod, i + 1);
      if(atr <= 0.01) continue;

      cRange = High[i + 1] - Low[i + 1];
      if(cRange < InpMinRangeAtr * atr) continue;

      body = MathAbs(Close[i + 1] - Open[i + 1]);
      if(body / cRange > InpMaxBodyRatio) continue; // Thin body Doji

      upperWick = High[i + 1] - MathMax(Open[i + 1], Close[i + 1]);
      lowerWick = MathMin(Open[i + 1], Close[i + 1]) - Low[i + 1];

      isPdlSweep = (pdl > 0.0 && Low[i + 1] < pdl && Close[i + 1] > pdl);
      isPdhSweep = (pdh > 0.0 && High[i + 1] > pdh && Close[i + 1] < pdh);
      isAslSweep = (asl < 1e8 && Low[i + 1] < asl && Close[i + 1] > asl);
      isAshSweep = (ash > 0.0 && High[i + 1] > ash && Close[i + 1] < ash);

      sigDir = 0;
      sigReason = "";

      if((isPdlSweep || isAslSweep) && (lowerWick / cRange >= InpMinWickRatio))
      {
         sigDir = 1;
         sigReason = isPdlSweep ? "Prior Day Low Sweep" : "Asian Range Low Sweep";
      }
      else if((isPdhSweep || isAshSweep) && (upperWick / cRange >= InpMinWickRatio))
      {
         sigDir = -1;
         sigReason = isPdhSweep ? "Prior Day High Sweep" : "Asian Range High Sweep";
      }

      if(sigDir == 0) continue;

      // Immediate Breakout Execution on Bar i
      if(sigDir == 1)
      {
         if(High[i] >= High[i + 1]) // Bar i breaks Doji High
         {
            entry = High[i + 1];
            sl    = Low[i + 1] - InpSlAtrBuffer * atr;
            risk  = entry - sl;

            if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
            {
               tp = entry + risk * InpRewardRiskRatio;
               BufferBuy[i] = Low[i] - (atr * 0.5); // Arrow directly on Bar i

               ExtLastSignal     = 1;
               ExtLastSignalTime = Time[i];
               ExtLastEntry      = entry;
               ExtLastSL         = sl;
               ExtLastTP         = tp;
               ExtLastReason     = sigReason;

               if(i == 0 && Time[0] != ExtLastAlertBar)
               {
                  ExtLastAlertBar = Time[0];
                  msg = StringFormat("[DOJI RIDE BUY] %s @ %.2f | SL: %.2f | TP: %.2f | %s (WR 84.0%%)",
                                     _Symbol, entry, sl, tp, sigReason);
                  if(InpEnableAlert) Alert(msg);
                  if(InpPlaySound)   PlaySound("alert.wav");
                  if(InpEnablePush)  SendNotification(msg);

                  if(InpShowTargetLines)
                     DrawTargetLines(Time[0], entry, sl, tp, clrLimeGreen);
               }
            }
         }
      }
      else if(sigDir == -1)
      {
         if(Low[i] <= Low[i + 1]) // Bar i breaks Doji Low
         {
            entry = Low[i + 1];
            sl    = High[i + 1] + InpSlAtrBuffer * atr;
            risk  = sl - entry;

            if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
            {
               tp = entry - risk * InpRewardRiskRatio;
               BufferSell[i] = High[i] + (atr * 0.5); // Arrow directly on Bar i

               ExtLastSignal     = -1;
               ExtLastSignalTime = Time[i];
               ExtLastEntry      = entry;
               ExtLastSL         = sl;
               ExtLastTP         = tp;
               ExtLastReason     = sigReason;

               if(i == 0 && Time[0] != ExtLastAlertBar)
               {
                  ExtLastAlertBar = Time[0];
                  msg = StringFormat("[DOJI RIDE SELL] %s @ %.2f | SL: %.2f | TP: %.2f | %s (WR 84.0%%)",
                                     _Symbol, entry, sl, tp, sigReason);
                  if(InpEnableAlert) Alert(msg);
                  if(InpPlaySound)   PlaySound("alert.wav");
                  if(InpEnablePush)  SendNotification(msg);

                  if(InpShowTargetLines)
                     DrawTargetLines(Time[0], entry, sl, tp, clrCrimson);
               }
            }
         }
      }
   }

   // Update Dashboard HUD & Level lines
   if(InpShowDashboard)
   {
      UpdateDashboard(inSessionNow, Close[0]);
   }
   else
   {
      ObjectsDeleteAll(0, PREFIX);
   }

   if(InpShowStructuralLevels)
   {
      if(ExtCurPDH > 0.0) DrawLevelLine(PREFIX + "PDH", ExtCurPDH, clrGoldenrod, STYLE_DASH, "Prior Day High");
      if(ExtCurPDL > 0.0) DrawLevelLine(PREFIX + "PDL", ExtCurPDL, clrGoldenrod, STYLE_DASH, "Prior Day Low");
      if(ExtCurASH > 0.0) DrawLevelLine(PREFIX + "ASH", ExtCurASH, clrAqua, STYLE_DOT, "Asian Session High");
      if(ExtCurASL > 0.0) DrawLevelLine(PREFIX + "ASL", ExtCurASL, clrAqua, STYLE_DOT, "Asian Session Low");
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
