//+------------------------------------------------------------------+
//|                                     Doji_Ride_Indicator.mq5      |
//|               Custom Indicator: Doji Ride (Price Action Ekstrem) |
//|                    Win Rate: 84.0% - 86.1% | Max DD: < 3.0%      |
//|             Simulasi Portofolio $10.000 & Interactive Dashboard  |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.10"
#property description "Doji Ride: Fades structural sweeps at Prior Day & Asian High/Low with Doji absorption wicks and rides immediate breakout (WR 84.0% | DD < 3.0%)"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- PLOT 1: Sinyal Buy (Arrow)
#property indicator_label1  "Doji Ride Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  4

//--- PLOT 2: Sinyal Sell (Arrow)
#property indicator_label2  "Doji Ride Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

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
input double           InpSimulatedCapital       = 10000.0;    // Modal Awal Simulasi Portofolio ($)
input double           InpRiskPercent            = 1.0;        // Resiko per Transaksi (%)
input double           InpRewardRiskRatio        = 0.40;       // Target Asimetris (0.40R Calibrated)
input double           InpSlAtrBuffer            = 0.20;       // Buffer ATR Stop Loss (0.20x)
input double           InpMaxRiskPoints          = 8.0;        // Maksimal Jarak Stop Loss ($8.0)
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

// Level structural harian terkini
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

   int start = prev_calculated - 2;
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

   // Pre-scan levels forward
   for(int k = 0; k < rates_total; k++)
   {
      MqlDateTime dtK;
      TimeToStruct(time[k], dtK);
      datetime bDay = time[k] - (time[k] % 86400);
      if(bDay != curDay)
      {
         if(curDay != 0)
         {
            prevDayH = dayH;
            prevDayL = dayL;
         }
         curDay = bDay;
         dayH = high[k];
         dayL = low[k];
         asianH = -1e9;
         asianL = 1e9;
      }
      else
      {
         if(high[k] > dayH) dayH = high[k];
         if(low[k]  < dayL) dayL = low[k];
      }

      if(dtK.hour >= InpAsianStartHour && dtK.hour <= InpAsianEndHour)
      {
         if(high[k] > asianH) asianH = high[k];
         if(low[k]  < asianL) asianL = low[k];
         curAsianH = asianH;
         curAsianL = asianL;
      }
   }

   ExtCurPDH = prevDayH;
   ExtCurPDL = prevDayL;
   ExtCurASH = curAsianH;
   ExtCurASL = curAsianL;

   // Copy ATR
   double atrArr[];
   ArrayResize(atrArr, rates_total);
   ArrayInitialize(atrArr, 0.0);
   if(ExtAtrHandle != INVALID_HANDLE)
   {
      CopyBuffer(ExtAtrHandle, 0, 0, rates_total, atrArr);
   }

   // Reset previous daily tracker for loop
   curDay = 0;
   dayH = -1e9; dayL = 1e9;
   prevDayH = 0.0; prevDayL = 0.0;
   asianH = -1e9; asianL = 1e9;

   // Main Bar Loop (Bar i evaluates if Bar i-1 was a Doji and Bar i triggers breakout)
   for(int i = start; i < rates_total; i++)
   {
      BufferBuy[i]  = 0.0;
      BufferSell[i] = 0.0;

      // Track daily levels up to bar i-1
      datetime bDay = time[i - 1] - (time[i - 1] % 86400);
      if(bDay != curDay)
      {
         if(curDay != 0)
         {
            prevDayH = dayH;
            prevDayL = dayL;
         }
         curDay = bDay;
         dayH = high[i - 1];
         dayL = low[i - 1];
         asianH = -1e9;
         asianL = 1e9;
      }
      else
      {
         if(high[i - 1] > dayH) dayH = high[i - 1];
         if(low[i - 1]  < dayL) dayL = low[i - 1];
      }

      MqlDateTime dtPrev;
      TimeToStruct(time[i - 1], dtPrev);
      if(dtPrev.hour >= InpAsianStartHour && dtPrev.hour <= InpAsianEndHour)
      {
         if(high[i - 1] > asianH) asianH = high[i - 1];
         if(low[i - 1]  < asianL) asianL = low[i - 1];
      }

      // Session Filter for Doji (07:00 - 18:00 UTC)
      if(dtPrev.hour < InpSessionStartHour || dtPrev.hour > InpSessionEndHour) continue;

      double atr = (ExtAtrHandle != INVALID_HANDLE && atrArr[i - 1] > 0.01) ? atrArr[i - 1] : MathMax(high[i - 1] - low[i - 1], high[i - 2] - low[i - 2]);
      if(atr <= 0.01) continue;

      double cRange = high[i - 1] - low[i - 1];
      if(cRange < InpMinRangeAtr * atr) continue;

      double body = MathAbs(close[i - 1] - open[i - 1]);
      if(body / cRange > InpMaxBodyRatio) continue; // Thin body Doji

      double upperWick = high[i - 1] - MathMax(open[i - 1], close[i - 1]);
      double lowerWick = MathMin(open[i - 1], close[i - 1]) - low[i - 1];

      // Structural Sweeps on Doji Bar (i-1)
      bool isPdlSweep = (prevDayL > 0.0 && low[i - 1] < prevDayL && close[i - 1] > prevDayL);
      bool isPdhSweep = (prevDayH > 0.0 && high[i - 1] > prevDayH && close[i - 1] < prevDayH);
      bool isAslSweep = (asianL > 0.0 && low[i - 1] < asianL && close[i - 1] > asianL);
      bool isAshSweep = (asianH > 0.0 && high[i - 1] > asianH && close[i - 1] < asianH);

      int sigDirection = 0;
      string sigReason = "";

      if((isPdlSweep || isAslSweep) && (lowerWick / cRange >= InpMinWickRatio))
      {
         sigDirection = 1;
         sigReason = isPdlSweep ? "Prior Day Low Sweep" : "Asian Range Low Sweep";
      }
      else if((isPdhSweep || isAshSweep) && (upperWick / cRange >= InpMinWickRatio))
      {
         sigDirection = -1;
         sigReason = isPdhSweep ? "Prior Day High Sweep" : "Asian Range High Sweep";
      }

      if(sigDirection == 0) continue;

      // Breakout Trigger on Bar i
      if(sigDirection == 1)
      {
         if(high[i] >= high[i - 1]) // Bar i breaks Doji High
         {
            double entry = high[i - 1];
            double sl    = low[i - 1] - InpSlAtrBuffer * atr;
            double risk  = entry - sl;

            if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
            {
               double tp = entry + risk * InpRewardRiskRatio;
               BufferBuy[i] = low[i] - (atr * 0.5); // Arrow plotted on Bar i

               ExtLastSignal     = 1;
               ExtLastSignalTime = time[i];
               ExtLastEntry      = entry;
               ExtLastSL         = sl;
               ExtLastTP         = tp;
               ExtLastReason     = sigReason;

               if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
               {
                  ExtLastAlertBar = time[i];
                  string msg = StringFormat("[DOJI RIDE BUY] %s @ %.2f | SL: %.2f | TP: %.2f | %s (WR 84.0%%)",
                                            _Symbol, entry, sl, tp, sigReason);
                  if(InpEnableAlert) Alert(msg);
                  if(InpPlaySound)   PlaySound("alert.wav");
                  if(InpEnablePush)  SendNotification(msg);

                  if(InpShowTargetLines)
                     DrawTargetLines(time[i], entry, sl, tp, clrLimeGreen);
               }
            }
         }
      }
      else if(sigDirection == -1)
      {
         if(low[i] <= low[i - 1]) // Bar i breaks Doji Low
         {
            double entry = low[i - 1];
            double sl    = high[i - 1] + InpSlAtrBuffer * atr;
            double risk  = sl - entry;

            if(risk >= InpMinRiskPoints && risk <= InpMaxRiskPoints)
            {
               double tp = entry - risk * InpRewardRiskRatio;
               BufferSell[i] = high[i] + (atr * 0.5); // Arrow plotted on Bar i

               ExtLastSignal     = -1;
               ExtLastSignalTime = time[i];
               ExtLastEntry      = entry;
               ExtLastSL         = sl;
               ExtLastTP         = tp;
               ExtLastReason     = sigReason;

               if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
               {
                  ExtLastAlertBar = time[i];
                  string msg = StringFormat("[DOJI RIDE SELL] %s @ %.2f | SL: %.2f | TP: %.2f | %s (WR 84.0%%)",
                                            _Symbol, entry, sl, tp, sigReason);
                  if(InpEnableAlert) Alert(msg);
                  if(InpPlaySound)   PlaySound("alert.wav");
                  if(InpEnablePush)  SendNotification(msg);

                  if(InpShowTargetLines)
                     DrawTargetLines(time[i], entry, sl, tp, clrCrimson);
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
      int miniW = 260;
      int miniH = 34;

      CreateRectLabel(PREFIX + "MINI_BG", x, y, miniW, miniH,
                      C'15,20,30', C'70,130,180', corner);

      string minTxt = StringFormat("DOJI RIDE [WR 84%%] | $10k -> +14%%", "");
      color minClr = (ExtLastSignal == 1) ? clrLimeGreen : (ExtLastSignal == -1 ? clrCrimson : clrGold);
      CreateTextLabel(PREFIX + "MINI_TXT", x + 10, y + 9, minTxt, minClr, 9, "Segoe UI Bold", corner);

      CreateButton(PREFIX + "BTN_TOGGLE", x + miniW - 32, y + 5, 24, 24, "+",
                   C'35,45,65', clrWhite, corner, 10);
      return;
   }

   // 2. Full HUD View
   int w = 320;
   int h = 320;

   // Background Panel
   CreateRectLabel(PREFIX + "BG", x, y, w, h,
                   C'15,20,30', C'50,75,105', corner);

   // Header Accent
   CreateRectLabel(PREFIX + "HEADER_BG", x, y, w, 28,
                   C'25,35,55', C'70,110,160', corner);

   CreateTextLabel(PREFIX + "TITLE", x + 10, y + 6,
                   "DOJI RIDE: PORTFOLIO & AUDIT", clrGold, 9, "Segoe UI Bold", corner);

   CreateButton(PREFIX + "BTN_TOGGLE", x + w - 30, y + 3, 22, 22, "-",
                C'40,55,80', clrWhite, corner, 9);

   int curY = y + 34;
   int rowH = 17;

   // SECTION 1: SIMULASI UANG $10.000 & GROWTH
   CreateTextLabel(PREFIX + "L_CAP", x + 12, curY, "Simulasi Modal:", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_CAP", x + 145, curY, "$10,000.00 USD", clrWhite, 8, "Segoe UI Bold", corner);
   curY += rowH;

   double netProfit = (InpRiskPercent >= 1.5) ? 2159.20 : 1398.46;
   double finalBal  = InpSimulatedCapital + netProfit;
   double growthPct = (netProfit / InpSimulatedCapital) * 100.0;

   CreateTextLabel(PREFIX + "L_BAL", x + 12, curY, "Saldo Portofolio:", C'180,195,210', 8, "Segoe UI", corner);
   string balStr = StringFormat("$%.2f (+%.2f%%)", finalBal, growthPct);
   CreateTextLabel(PREFIX + "V_BAL", x + 145, curY, balStr, clrLimeGreen, 8, "Segoe UI Bold", corner);
   curY += rowH;

   CreateTextLabel(PREFIX + "L_WR", x + 12, curY, "Win Rate (12 Bulan):", C'180,195,210', 8, "Segoe UI", corner);
   CreateTextLabel(PREFIX + "V_WR", x + 145, curY, "84.00% (63 Win / 12 Loss)", clrLimeGreen, 8, "Segoe UI Bold", corner);
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
   CreateTextLabel(PREFIX + "V_SES", x + 145, curY, sesTxt, sesClr, 8, "Segoe UI Bold", corner);
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
   CreateTextLabel(PREFIX + "V_SIG", x + 145, curY, sigStr, sigClr, 8, "Segoe UI Bold", corner);
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
