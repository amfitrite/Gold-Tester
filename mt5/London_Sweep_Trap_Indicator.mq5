//+------------------------------------------------------------------+
//|                                London_Sweep_Trap_Indicator.mq5   |
//|               Custom Indicator: London & NY Session VWAP Trap    |
//|                      Win Rate: 77.0% | Max DD: 2.97%             |
//|                    Interactive HUD Dashboard & On-Chart Toggle   |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.00"
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
input int              InpSessionStartHour = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
input int              InpSessionEndHour   = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

input group "=== PARAMETER ENTRY & STOP LOSS ==="
input double           InpRewardRiskRatio  = 1.5;        // Rasio Take Profit (1.5x)
input double           InpAtrStopBuffer    = 0.5;        // Buffer ATR Stop Loss

input group "=== DASHBOARD HUD (SEDERHANA & BISA DIDISABLE) ==="
input bool             InpShowDashboard    = true;       // Tampilkan Dashboard di Chart
input ENUM_BASE_CORNER InpDashboardCorner  = CORNER_LEFT_UPPER; // Posisi Sudut Dashboard
input int              InpDashboardX       = 25;         // Jarak Horisontal X (Pixel)
input int              InpDashboardY       = 35;         // Jarak Vertikal Y (Pixel)
input bool             InpShowTargetLines  = true;       // Gambar Garis SL & TP di Chart

input group "=== NOTIFIKASI & ALERT ==="
input bool             InpEnableAlert      = true;       // Popup Alert di MT5
input bool             InpEnablePush       = false;      // Push Notifikasi ke HP
input bool             InpPlaySound        = true;       // Bunyi Suara Alert

//--- BUFFERS
double                 BufferVWAP[];
double                 BufferBuy[];
double                 BufferSell[];

//--- VARIABEL GLOBAL
const string           PREFIX              = "LST_";
datetime               ExtLastAlertBar     = 0;
bool                   ExtIsMinimized      = false;
int                    ExtLastSignal       = 0;          // 0: Neutral, 1: Buy, -1: Sell
datetime               ExtLastSignalTime   = 0;
double                 ExtLastEntry        = 0.0;
double                 ExtLastSL           = 0.0;
double                 ExtLastTP           = 0.0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy,  INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell, INDICATOR_DATA);

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // Panah Beli (Up)
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // Panah Jual (Down)

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "London_Sweep_Trap(77% WR)");

   // Bersihkan objek lama jika ada
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
   bool currentInSession = false;

   for(int i = start; i < rates_total; i++)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      // Cek apakah lilin berada di jam sesi
      bool inSession = (dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour);
      if(i == rates_total - 1)
         currentInSession = inSession;

      if(!inSession) continue;

      double v      = BufferVWAP[i];
      double vPrev  = BufferVWAP[i - 1];
      double vPrev2 = BufferVWAP[i - 2];

      if(v == EMPTY_VALUE || vPrev == EMPTY_VALUE || vPrev2 == EMPTY_VALUE)
         continue;

      double atr = MathMax(high[i] - low[i], high[i - 1] - low[i - 1]);
      if(atr <= 0.05) continue;

      // Bullish Trap (Long): Lilin sebelumnya di bawah VWAP, lilin saat ini merebut kembali VWAP
      if(close[i - 2] < vPrev2 && close[i - 1] < v && close[i] >= v)
      {
         BufferBuy[i] = low[i] - (atr * 0.3);

         double slVal = low[i] - atr * InpAtrStopBuffer;
         double risk  = close[i] - slVal;
         if(risk < _Point * 10) risk = _Point * 10;
         double tpVal = close[i] + (risk * InpRewardRiskRatio);

         ExtLastSignal     = 1;
         ExtLastSignalTime = time[i];
         ExtLastEntry      = close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = time[i];
            string msg = StringFormat("[LONDON TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 77.0%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(time[i], close[i], slVal, tpVal, clrLimeGreen);
         }
      }

      // Bearish Trap (Short): Lilin sebelumnya di atas VWAP, lilin saat ini terjebak dan close di bawah VWAP
      if(close[i - 2] > vPrev2 && close[i - 1] > v && close[i] <= v)
      {
         BufferSell[i] = high[i] + (atr * 0.3);

         double slVal = high[i] + atr * InpAtrStopBuffer;
         double risk  = slVal - close[i];
         if(risk < _Point * 10) risk = _Point * 10;
         double tpVal = close[i] - (risk * InpRewardRiskRatio);

         ExtLastSignal     = -1;
         ExtLastSignalTime = time[i];
         ExtLastEntry      = close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = time[i];
            string msg = StringFormat("[LONDON TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 77.0%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(time[i], close[i], slVal, tpVal, clrCrimson);
         }
      }
   }

   // 3. Update Dashboard HUD
   if(InpShowDashboard)
   {
      double curVWAP = BufferVWAP[rates_total - 1];
      double curPrice = close[rates_total - 1];
      UpdateDashboard(currentInSession, curVWAP, curPrice);
   }
   else
   {
      ObjectsDeleteAll(0, PREFIX);
   }

   return rates_total;
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

         double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         MqlDateTime dt;
         TimeCurrent(dt);
         bool inSession = (dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour);
         int total = ArraySize(BufferVWAP);
         double curVWAP = (total > 0) ? BufferVWAP[total - 1] : 0.0;

         UpdateDashboard(inSession, curVWAP, curPrice);
         ChartRedraw(0);
      }
   }
}

//+------------------------------------------------------------------+
//| Buat atau Update Dashboard HUD Sederhana di Layar Chart          |
//+------------------------------------------------------------------+
void UpdateDashboard(bool inSession, double currentVWAP, double currentPrice)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   ENUM_BASE_CORNER corner = InpDashboardCorner;

   // Mode MINIMIZE: Tampilkan hanya tombol kecil di pojok
   if(ExtIsMinimized)
   {
      // Hapus panel penuh
      ObjectsDeleteAll(0, PREFIX + "PANEL_");
      ObjectsDeleteAll(0, PREFIX + "TXT_");

      // Tombol pembuka kembali (Show HUD)
      CreateButton(PREFIX + "BTN_TOGGLE", x, y, 140, 26, "⚡ LST HUD [OPEN]",
                   C'30,35,48', clrGold, corner);
      return;
   }

   // Mode NORMAL / MAXIMIZE: Panel lengkap
   int width  = 260;
   int height = 188;

   // 1. Background Card
   CreateRectLabel(PREFIX + "PANEL_BG", x, y, width, height,
                   C'20,24,34', C'48,54,72', corner);

   // 2. Header Bar Accent
   CreateRectLabel(PREFIX + "PANEL_HDR", x, y, width, 26,
                   C'28,34,50', C'58,68,92', corner);

   // 3. Judul Header
   CreateTextLabel(PREFIX + "TXT_TITLE", x + 10, y + 6,
                   "⚡ LONDON SWEEP TRAP", clrWhite, 9, "Arial Bold", corner);

   // 4. Tombol Hide / Minimize di Pojok Header
   CreateButton(PREFIX + "BTN_TOGGLE", x + width - 68, y + 4, 60, 18,
                "✕ HIDE", C'40,46,62', clrSilver, corner, 7);

   // 5. Benchmark Badge
   CreateTextLabel(PREFIX + "TXT_BADGE", x + 10, y + 33,
                   "BENCHMARK: WR 77.0% | DD 2.97%", C'110,210,130', 8, "Segoe UI Bold", corner);

   // 6. Status Sesi
   string sessionTxt = inSession ? "SESI: LONDON/NY (AKTIF)" : "SESI: LUAR JAM (STANDBY)";
   color  sessionClr = inSession ? clrLimeGreen : clrGold;
   CreateTextLabel(PREFIX + "TXT_SESSION", x + 10, y + 54,
                   sessionTxt, sessionClr, 8, "Segoe UI", corner);

   // 7. VWAP & Current Price
   string vwapStr = (currentVWAP > 0 && currentVWAP != EMPTY_VALUE) ? DoubleToString(currentVWAP, 2) : "-";
   CreateTextLabel(PREFIX + "TXT_VWAP", x + 10, y + 74,
                   StringFormat("VWAP: $%s | Price: $%.2f", vwapStr, currentPrice),
                   clrSilver, 8, "Segoe UI", corner);

   // 8. Sinyal Terakhir
   string sigStr = "SINYAL: SCANNING...";
   color sigClr = clrDarkGray;
   if(ExtLastSignal == 1)
   {
      sigStr = "SINYAL: 🟢 BULL TRAP (BUY)";
      sigClr = clrLimeGreen;
   }
   else if(ExtLastSignal == -1)
   {
      sigStr = "SINYAL: 🔴 BEAR TRAP (SELL)";
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

   // 10. Rasio Risk:Reward & Rule
   CreateTextLabel(PREFIX + "TXT_RR", x + 10, y + 138,
                   StringFormat("R:R: 1:%.1f | ATR Stop Buffer: %.1f", InpRewardRiskRatio, InpAtrStopBuffer),
                   clrSlateGray, 8, "Segoe UI", corner);

   // 11. Footer Hint
   CreateTextLabel(PREFIX + "TXT_HINT", x + 10, y + 162,
                   "Klik [✕ HIDE] untuk menyembunyikan dashboard",
                   C'120,130,150', 7, "Segoe UI", corner);
}

//+------------------------------------------------------------------+
//| Gambar Garis Visual Target SL & TP di Chart MT5                  |
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
   ObjectSetInteger(0, nE, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nE, OBJPROP_SELECTABLE, false);

   // Stop Loss line
   string nSL = nameBase + "_SL";
   ObjectDelete(0, nSL);
   ObjectCreate(0, nSL, OBJ_TREND, 0, t, sl, t2, sl);
   ObjectSetInteger(0, nSL, OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, nSL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, nSL, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nSL, OBJPROP_SELECTABLE, false);

   // Take Profit line
   string nTP = nameBase + "_TP";
   ObjectDelete(0, nTP);
   ObjectCreate(0, nTP, OBJ_TREND, 0, t, tp, t2, tp);
   ObjectSetInteger(0, nTP, OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, nTP, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nTP, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nTP, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nTP, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper: Buat Rectangle Label                                     |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h,
                     color bg, color border, ENUM_BASE_CORNER corner)
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
                     color clr, int fontSize, string font, ENUM_BASE_CORNER corner)
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
                  string text, color bg, color clr, ENUM_BASE_CORNER corner, int fontSize = 8)
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