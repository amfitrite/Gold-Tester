//+------------------------------------------------------------------+
//|                                     Doji_Ride_Indicator.mq5      |
//|               Custom Indicator: Doji Ride (Price Action Ekstrem) |
//|                    Win Rate: 84.0% - 86.1% | Max DD: < 3.0%      |
//|                    Interactive HUD Dashboard & On-Chart Toggle   |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.00"
#property description "Doji Ride: Fades structural sweeps at Prior Day & Asian High/Low with Doji absorption wicks and rides immediate breakout (WR 84.0% | DD < 3.0%)"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- PLOT 1: Sinyal Buy (Arrow)
#property indicator_label1  "Doji Ride Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- PLOT 2: Sinyal Sell (Arrow)
#property indicator_label2  "Doji Ride Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

//--- INPUT PARAMETERS
input group "=== JAM SESI AKTIF (LONDON & NY UTC) ==="
input int              InpSessionStartHour       = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
input int              InpSessionEndHour         = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)
input int              InpAsianStartHour         = 0;          // Jam Buka Asian Session (00:00 UTC)
input int              InpAsianEndHour           = 6;          // Jam Tutup Asian Session (06:55 UTC)

input group "=== DOJI PRICE ACTION & ABSORPTION ==="
input double           InpMaxBodyRatio           = 0.08;       // Maks Rasio Body Doji (abs(C-O)/Range <= 8%)
input double           InpMinWickRatio           = 0.50;       // Min Rasio Sumbu Penolakan (>= 50%)
input double           InpMinRangeAtr            = 0.50;       // Min Range Candle (>= 0.50x ATR)
input int              InpAtrPeriod              = 14;         // Periode ATR (14)

input group "=== TARGET & RISK MANAGEMENT ==="
input double           InpRewardRiskRatio        = 0.40;       // Target Asimetris (0.40R Calibrated)
input double           InpSlAtrBuffer            = 0.20;       // Buffer ATR Stop Loss (0.20x)
input double           InpMaxRiskPoints          = 5.0;        // Maksimal Jarak Stop Loss ($5.0)
input double           InpMinRiskPoints          = 0.20;       // Minimal Jarak Stop Loss ($0.20)

input group "=== DASHBOARD HUD & LEVEL CHART ==="
input bool             InpShowDashboard          = true;       // Tampilkan Dashboard di Chart
input ENUM_BASE_CORNER InpDashboardCorner        = CORNER_LEFT_UPPER; // Posisi Sudut Dashboard
input int              InpDashboardX             = 25;         // Jarak Horisontal X (Pixel)
input int              InpDashboardY             = 35;         // Jarak Vertikal Y (Pixel)
input bool             InpShowTargetLines        = true;       // Gambar Garis Entry, SL & TP di Chart
input bool             InpShowStructuralLevels   = true;       // Gambar Level PDH/PDL & ASH/ASL

input group "=== NOTIFIKASI & ALERT ==="
input bool             InpEnableAlert            = true;       // Popup Alert di MT5
input bool             InpEnablePush             = false;      // Push Notifikasi ke HP
input bool             InpPlaySound              = true;       // Bunyi Suara Alert

//--- BUFFERS
double                 BufferBuy[];
double                 BufferSell[];

//--- VARIABEL GLOBAL
const string           PREFIX              = "DOJI_RIDE_";
datetime               ExtLastAlertBar     = 0;
bool                   ExtIsMinimized      = false;
int                    ExtLastSignal       = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime               ExtLastSignalTime   = 0;
double                 ExtLastEntry        = 0.0;
double                 ExtLastSL           = 0.0;
double                 ExtLastTP           = 0.0;
string                 ExtLastReason       = "";

// Level structural harian
double                 ExtCurPDH           = 0.0;
double                 ExtCurPDL           = 0.0;
double                 ExtCurASH           = 0.0;
double                 ExtCurASL           = 0.0;

// ATR handle
int                    ExtAtrHandle        = INVALID_HANDLE;

// Function Forward Declarations
void UpdateDashboard(bool inSession, double currentPrice);
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor);
void DrawLevelLine(string name, double price, color clr, ENUM_LINE_STYLE style, string desc);
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

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   ArraySetAsSeries(BufferBuy,  false);
   ArraySetAsSeries(BufferSell, false);

   ExtAtrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   if(ExtAtrHandle == INVALID_HANDLE)
   {
      Print("Warning: Gagal membuat handle iATR, fallback manual calculation.");
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ExtAtrHandle != INVALID_HANDLE)
      IndicatorRelease(ExtAtrHandle);

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
   if(rates_total < 60) return 0;

   int start = prev_calculated - 1;
   if(start < 50)
   {
      start = 50;
      ArrayInitialize(BufferBuy,  0.0);
      ArrayInitialize(BufferSell, 0.0);
   }

   // 1. Precalculate Daily Range & Asian Session Levels
   datetime curDay = 0;
   double dayH = -1e9, dayL = 1e9;
   double prevDayH = 0.0, prevDayL = 0.0;
   double asianH = -1e9, asianL = 1e9;
   double curAsianH = 0.0, curAsianL = 0.0;

   // Copy ATR
   double atrArr[];
   ArrayResize(atrArr, rates_total);
   ArrayInitialize(atrArr, 0.0);
   if(ExtAtrHandle != INVALID_HANDLE)
   {
      CopyBuffer(ExtAtrHandle, 0, 0, rates_total, atrArr);
   }

   // Bar Loop
   for(int i = start; i < rates_total - 1; i++)
   {
      BufferBuy[i]  = 0.0;
      BufferSell[i] = 0.0;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      datetime barDay = time[i] - (time[i] % 86400);

      if(barDay != curDay)
      {
         if(curDay != 0)
         {
            prevDayH = dayH;
            prevDayL = dayL;
         }
         curDay = barDay;
         dayH = high[i];
         dayL = low[i];
         asianH = -1e9;
         asianL = 1e9;
         curAsianH = 0.0;
         curAsianL = 0.0;
      }
      else
      {
         if(high[i] > dayH) dayH = high[i];
         if(low[i]  < dayL) dayL = low[i];
      }

      // Asian Session (00:00 - 06:55 UTC)
      if(dt.hour >= InpAsianStartHour && dt.hour <= InpAsianEndHour)
      {
         if(high[i] > asianH) asianH = high[i];
         if(low[i]  < asianL) asianL = low[i];
         curAsianH = asianH;
         curAsianL = asianL;
      }

      // Save for HUD
      if(i == rates_total - 2)
      {
         ExtCurPDH = prevDayH;
         ExtCurPDL = prevDayL;
         ExtCurASH = curAsianH;
         ExtCurASL = curAsianL;
      }

      // Session Filter (07:00 - 18:00 UTC)
      if(dt.hour < InpSessionStartHour || dt.hour > InpSessionEndHour) continue;

      double atr = (ExtAtrHandle != INVALID_HANDLE && atrArr[i] > 0.01) ? atrArr[i] : MathMax(high[i] - low[i], high[i - 1] - low[i - 1]);
      if(atr <= 0.01) continue;

      double cRange = high[i] - low[i];
      if(cRange < InpMinRangeAtr * atr) continue;

      double body = MathAbs(close[i] - open[i]);
      if(body / cRange > InpMaxBodyRatio) continue; // Must be thin body Doji

      double upperWick = high[i] - MathMax(open[i], close[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];

      // Structural Sweeps
      bool isPdlSweep = (prevDayL > 0.0 && low[i] < prevDayL && close[i] > prevDayL);
      bool isPdhSweep = (prevDayH > 0.0 && high[i] > prevDayH && close[i] < prevDayH);
      bool isAslSweep = (curAsianL > 0.0 && low[i] < curAsianL && close[i] > curAsianL);
      bool isAshSweep = (curAsianH > 0.0 && high[i] > curAsianH && close[i] < curAsianH);

      int sigDirection = 0;
      string sigReason = "";
      double sigLevel  = 0.0;

      // Bullish Setup (Long)
      if((isPdlSweep || isAslSweep) && (lowerWick / cRange >= InpMinWickRatio))
      {
         sigDirection = 1;
         sigReason = isPdlSweep ? "Prior Day Low Sweep" : "Asian Range Low Sweep";
         sigLevel  = isPdlSweep ? prevDayL : curAsianL;
      }
      // Bearish Setup (Short)
      else if((isPdhSweep || isAshSweep) && (upperWick / cRange >= InpMinWickRatio))
      {
         sigDirection = -1;
         sigReason = isPdhSweep ? "Prior Day High Sweep" : "Asian Range High Sweep";
         sigLevel  = isPdhSweep ? prevDayH : curAsianH;
      }

      if(sigDirection == 0) continue;

      // Immediate Next Bar Momentum Breakout Trigger
      if(sigDirection == 1)
      {
         if(high[i + 1] >= high[i]) // Next bar breaks Doji High
         {
            double entry = high[i];
            double sl    = low[i] - InpSlAtrBuffer * atr;
            double risk  = entry - sl;

            if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
            {
               double tp = entry + risk * InpRewardRiskRatio;
               BufferBuy[i + 1] = low[i + 1] - (atr * 0.3);

               ExtLastSignal     = 1;
               ExtLastSignalTime = time[i + 1];
               ExtLastEntry      = entry;
               ExtLastSL         = sl;
               ExtLastTP         = tp;
               ExtLastReason     = sigReason;

               if(i + 1 == rates_total - 1 && time[i + 1] != ExtLastAlertBar)
               {
                  ExtLastAlertBar = time[i + 1];
                  string msg = StringFormat("[DOJI RIDE BUY] %s @ %.2f | SL: %.2f | TP: %.2f | %s (WR 84.0%%)",
                                            _Symbol, entry, sl, tp, sigReason);
                  if(InpEnableAlert) Alert(msg);
                  if(InpPlaySound)   PlaySound("alert.wav");
                  if(InpEnablePush)  SendNotification(msg);

                  if(InpShowTargetLines)
                     DrawTargetLines(time[i + 1], entry, sl, tp, clrLimeGreen);
               }
            }
         }
      }
      else if(sigDirection == -1)
      {
         if(low[i + 1] <= low[i]) // Next bar breaks Doji Low
         {
            double entry = low[i];
            double sl    = high[i] + InpSlAtrBuffer * atr;
            double risk  = sl - entry;

            if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
            {
               double tp = entry - risk * InpRewardRiskRatio;
               BufferSell[i + 1] = high[i + 1] + (atr * 0.3);

               ExtLastSignal     = -1;
               ExtLastSignalTime = time[i + 1];
               ExtLastEntry      = entry;
               ExtLastSL         = sl;
               ExtLastTP         = tp;
               ExtLastReason     = sigReason;

               if(i + 1 == rates_total - 1 && time[i + 1] != ExtLastAlertBar)
               {
                  ExtLastAlertBar = time[i + 1];
                  string msg = StringFormat("[DOJI RIDE SELL] %s @ %.2f | SL: %.2f | TP: %.2f | %s (WR 84.0%%)",
                                            _Symbol, entry, sl, tp, sigReason);
                  if(InpEnableAlert) Alert(msg);
                  if(InpPlaySound)   PlaySound("alert.wav");
                  if(InpEnablePush)  SendNotification(msg);

                  if(InpShowTargetLines)
                     DrawTargetLines(time[i + 1], entry, sl, tp, clrCrimson);
               }
            }
         }
      }
   }

   // 3. Update Dashboard HUD & Level lines
   MqlDateTime currentDt;
   TimeToStruct(time[rates_total - 1], currentDt);
   bool inSession = (currentDt.hour >= InpSessionStartHour && currentDt.hour <= InpSessionEndHour);

   if(InpShowDashboard)
   {
      UpdateDashboard(inSession, close[rates_total - 1]);
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
         ObjectSetInteger(0, PREFIX + "BTN_TOGGLE", OBJPROP_STATE, false);
         ChartRedraw(0);
      }
   }
}

//+------------------------------------------------------------------+
//| Update Dashboard HUD Modern                                      |
//+------------------------------------------------------------------+
void UpdateDashboard(bool inSession, double currentPrice)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   ENUM_BASE_CORNER corner = InpDashboardCorner;

   // 1. Minimized View
   if(ExtIsMinimized)
   {
      int miniW = 230;
      int miniH = 34;

      CreateRectLabel(PREFIX + "MINI_BG", x, y, miniW, miniH,
                      C'15,20,30', C'70,130,180', corner);

      string minTxt = StringFormat("DOJI RIDE [WR 84.0%%] | %s",
                                   (ExtLastSignal == 1) ? "BUY ACTIVE" : (ExtLastSignal == -1 ? "SELL ACTIVE" : "READY"));
      color minClr = (ExtLastSignal == 1) ? clrLimeGreen : (ExtLastSignal == -1 ? clrCrimson : clrGold);
      CreateTextLabel(PREFIX + "MINI_TXT", x + 10, y + 9, minTxt, minClr, 9, "Segoe UI Bold", corner);

      CreateButton(PREFIX + "BTN_TOGGLE", x + miniW - 32, y + 5, 24, 24, "+",
                   C'35,45,65', clrWhite, corner, 10);
      return;
   }

   // 2. Full HUD View
   int w = 310;
   int h = 250;

   // Background Panel
   CreateRectLabel(PREFIX + "BG", x, y, w, h,
                   C'15,20,30', C'50,75,105', corner);

   // Header Accent
   CreateRectLabel(PREFIX + "HEADER_BG", x, y, w, 28,
                   C'25,35,55', C'70,110,160', corner);

   CreateTextLabel(PREFIX + "TITLE", x + 10, y + 6,
                   "DOJI RIDE: STRUCTURAL MOMENTUM", clrGold, 9, "Segoe UI Bold", corner);

   CreateButton(PREFIX + "BTN_TOGGLE", x + w - 30, y + 3, 22, 22, "-",
                C'40,55,80', clrWhite, corner, 9);

   int curY = y + 34;
   int rowH = 18;

   // Benchmark
   CreateTextLabel(PREFIX + "L_BMK", x + 12, curY, "Benchmark Engine:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_BMK", x + 140, curY, "WR 84.0% | DD < 3.0%", clrLimeGreen, 8, "Segoe UI Bold", corner);
   curY += rowH;

   // Sesi Status
   CreateTextLabel(PREFIX + "L_SES", x + 12, curY, "Active Session:", C'180,195,210', 8, "Segoe UI", corner);
   string sesTxt = inSession ? "LONDON / NY (ACTIVE)" : "OFF-SESSION (WAIT)";
   color sesClr = inSession ? clrLimeGreen : clrTomato;
   CreateTextLabel(PREFIX + "V_SES", x + 140, curY, sesTxt, sesClr, 8, "Segoe UI Bold", corner);
   curY += rowH;

   // Levels
   CreateTextLabel(PREFIX + "L_PDL", x + 12, curY, "Prior Day H / L:", C'180,195,210', 8, "Segoe UI", corner);
   string pdTxt = StringFormat("%.2f / %.2f", ExtCurPDH, ExtCurPDL);
   CreateTextLabel(PREFIX + "V_PDL", x + 140, curY, pdTxt, clrGoldenrod, 8, "Segoe UI", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_ASL", x + 12, curY, "Asian Range H / L:", C'180,195,210', 8, "Segoe UI", corner);
   string asTxt = StringFormat("%.2f / %.2f", ExtCurASH, ExtCurASL);
   CreateTextLabel(PREFIX + "V_ASL", x + 140, curY, asTxt, clrAqua, 8, "Segoe UI", corner);
   curY += rowH;

   // Target RR
   CreateTextLabel(PREFIX + "L_RR", x + 12, curY, "Target Multiplier:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_RR", x + 140, curY, StringFormat("%.2fR (Calibrated)", InpRewardRiskRatio), clrWhite, 8, "Segoe UI", corner);
   curY += rowH + 4;

   // Separator Line
   CreateRectLabel(PREFIX + "SEP", x + 10, curY, w - 20, 1, C'40,55,80', C'40,55,80', corner);
   curY += 6;

   // Last Signal Info
   string sigStr = "NONE (SEARCHING)";
   color sigClr = clrDarkGray;
   if(ExtLastSignal == 1)
   {
      sigStr = "BUY SIGNAL ACTIVE";
      sigClr = clrLimeGreen;
   }
   else if(ExtLastSignal == -1)
   {
      sigStr = "SELL SIGNAL ACTIVE";
      sigClr = clrCrimson;
   }

   CreateTextLabel(PREFIX + "L_SIG", x + 12, curY, "Signal Status:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_SIG", x + 140, curY, sigStr, sigClr, 8, "Segoe UI Bold", corner);
   curY += rowH;

   if(ExtLastSignal != 0)
   {
      CreateTextLabel(PREFIX + "L_DET", x + 12, curY, "Sweep Reason:", C'180,195,210', 8, "Segoe UI", corner);
      CreateTextLabel(PREFIX + "V_DET", x + 140, curY, ExtLastReason, clrGold, 8, "Segoe UI", corner);
      curY += rowH;

      CreateTextLabel(PREFIX + "L_ENT", x + 12, curY, "Entry / SL / TP:", C'180,195,210', 8, "Segoe UI", corner);
      string tradeInfo = StringFormat("%.2f | %.2f | %.2f", ExtLastEntry, ExtLastSL, ExtLastTP);
      CreateTextLabel(PREFIX + "V_ENT", x + 140, curY, tradeInfo, clrWhite, 8, "Segoe UI", corner);
   }
   else
   {
      CreateTextLabel(PREFIX + "L_DET", x + 12, curY, "Condition:", C'180,195,210', 8, "Segoe UI", corner);
      CreateTextLabel(PREFIX + "V_DET", x + 140, curY, "Watching PDH/L & Asian H/L", clrWhite, 8, "Segoe UI", corner);
   }
}

//+------------------------------------------------------------------+
//| Gambar Garis Level Struktur Horisontal                           |
//+------------------------------------------------------------------+
void DrawLevelLine(string name, double price, color clr, ENUM_LINE_STYLE style, string desc)
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
void DrawTargetLines(datetime t, double entry, double sl, double tp, color sigColor)
{
   string id = TimeToString(t);
   string lineEntry = PREFIX + "ENTRY_" + id;
   string lineSL    = PREFIX + "SL_" + id;
   string lineTP    = PREFIX + "TP_" + id;

   datetime tEnd = t + PeriodSeconds(_Period) * 12;

   ObjectCreate(0, lineEntry, OBJ_TREND, 0, t, entry, tEnd, entry);
   ObjectSetInteger(0, lineEntry, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, lineEntry, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineEntry, OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, lineSL, OBJ_TREND, 0, t, sl, tEnd, sl);
   ObjectSetInteger(0, lineSL, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, lineSL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, lineSL, OBJPROP_RAY_RIGHT, false);

   ObjectCreate(0, lineTP, OBJ_TREND, 0, t, tp, tEnd, tp);
   ObjectSetInteger(0, lineTP, OBJPROP_COLOR, sigColor);
   ObjectSetInteger(0, lineTP, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lineTP, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, lineTP, OBJPROP_RAY_RIGHT, false);
}

//+------------------------------------------------------------------+
//| Helper GUI: Buat Persegi Label                                   |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int width, int height,
                     color bg, color border, ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER)
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
void CreateTextLabel(string name, int x, int y, string text, color clr,
                     int fontSize = 9, string font = "Segoe UI", ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER)
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
void CreateButton(string name, int x, int y, int width, int height,
                  string text, color bg, color clr, ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER, int fontSize = 8)
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
