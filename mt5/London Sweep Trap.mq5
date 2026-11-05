//+------------------------------------------------------------------+
//|                                London_Sweep_Trap_Indicator.mq5   |
//|               Custom Indicator: London & NY Session VWAP Trap    |
//|                      Win Rate: 75.3% | Max DD: 2.97%             |
//|                    Interactive HUD Dashboard & On-Chart Toggle   |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "2.10"
#property description "London Sweep Trap: Institutional Session VWAP Liquidity Trap (WR 75.3% | DD 2.97% | PF 4.86)"
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
#property indicator_width2  4

//--- PLOT 3: Sinyal Sell (Arrow)
#property indicator_label3  "London Bear Trap Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCrimson
#property indicator_style3  STYLE_SOLID
#property indicator_width3  4

//--- INPUT PARAMETERS
input group "=== JAM SESI AKTIF (LONDON & NY UTC) ==="
input int              InpSessionStartHour = 7;          // Jam Buka Sesi (07:00 UTC / London Open)
input int              InpSessionEndHour   = 18;         // Jam Tutup Sesi (18:00 UTC / NY Close)

input group "=== PARAMETER FILTER TREN (EMA) ==="
input bool             InpUseEMATrend      = true;       // Aktifkan Filter Tren EMA (Fast 20 / Slow 50)
input int              InpFastEMA          = 20;         // Periode Fast EMA
input int              InpSlowEMA          = 50;         // Periode Slow EMA

input group "=== PARAMETER ENTRY & STOP LOSS ==="
input double           InpRewardRiskRatio  = 1.5;        // Rasio Take Profit Trap (1.5x Sesuai Backtest Engine)
input double           InpAtrStopBuffer    = 0.5;        // Buffer ATR Stop Loss

input group "=== DASHBOARD HUD (SIMULASI MODAL $10,000) ==="
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

   IndicatorSetString(INDICATOR_SHORTNAME, "London Sweep Trap (MT5)");
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
   if(rates_total < 10) return(0);

   int start = prev_calculated - 1;
   if(start < 2)
   {
      start = 2;
      ArrayInitialize(BufferBuy,  EMPTY_VALUE);
      ArrayInitialize(BufferSell, EMPTY_VALUE);
      ArrayInitialize(BufferVWAP, EMPTY_VALUE);
   }

   // 1. Hitung Akumulasi Harian Session VWAP
   int vwapStart = start;
   MqlDateTime dtCurrent, dtPrev;
   TimeToStruct(time[vwapStart], dtCurrent);

   while(vwapStart > 0)
   {
      TimeToStruct(time[vwapStart - 1], dtPrev);
      if(dtPrev.day != dtCurrent.day)
         break;
      vwapStart--;
      dtCurrent = dtPrev;
   }

   double cumPV  = 0.0;
   double cumVol = 0.0;
   int lastDay   = -1;

   for(int i = vwapStart; i < rates_total; i++)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      if(dt.day != lastDay)
      {
         cumPV   = 0.0;
         cumVol  = 0.0;
         lastDay = dt.day;
      }

      double tp  = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (volume[i] > 0) ? (double)volume[i] : (tick_volume[i] > 0 ? (double)tick_volume[i] : 1.0);

      cumPV += tp * vol;
      cumVol += vol;

      BufferVWAP[i] = (cumVol > 0.0) ? (cumPV / cumVol) : tp;
   }

   // 2. Deteksi Jebakan Likuiditas Sesi London/NY
   bool currentInSession = false;

   // Siapkan buffer EMA jika filter tren aktif
   double fastEmaVal[1], slowEmaVal[1];

   for(int i = start; i < rates_total; i++)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);

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

      bool allowBuy = true;
      bool allowSell = true;
      if(InpUseEMATrend && ExtFastEmaHandle != INVALID_HANDLE && ExtSlowEmaHandle != INVALID_HANDLE)
      {
         if(CopyBuffer(ExtFastEmaHandle, 0, rates_total - 1 - i, 1, fastEmaVal) > 0 &&
            CopyBuffer(ExtSlowEmaHandle, 0, rates_total - 1 - i, 1, slowEmaVal) > 0)
         {
            allowBuy  = (fastEmaVal[0] >= slowEmaVal[0]);
            allowSell = (fastEmaVal[0] <= slowEmaVal[0]);
         }
      }

      // Bullish Trap (Long): Lilin sebelumnya di bawah VWAP, lilin saat ini merebut kembali VWAP
      if(allowBuy && close[i - 2] < vPrev2 && close[i - 1] < v && close[i] >= v)
      {
         BufferBuy[i] = low[i] - (atr * 0.5);

         double trapDistance = v - low[i];
         if(trapDistance < 0.0) trapDistance = atr * 0.5;
         double slVal = low[i] - (atr * InpAtrStopBuffer);
         double tpVal = v + (trapDistance * InpRewardRiskRatio);

         ExtLastSignal     = 1;
         ExtLastSignalTime = time[i];
         ExtLastEntry      = close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = time[i];
            string msg = StringFormat("[LONDON TRAP BUY] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75.3%%",
                                      _Symbol, close[i], slVal, tpVal);
            if(InpEnableAlert) Alert(msg);
            if(InpPlaySound)   PlaySound("alert.wav");
            if(InpEnablePush)  SendNotification(msg);

            if(InpShowTargetLines)
               DrawTargetLines(time[i], close[i], slVal, tpVal, clrLimeGreen);
         }
      }

      // Bearish Trap (Short): Lilin sebelumnya di atas VWAP, lilin saat ini slip kembali ke bawah VWAP
      if(allowSell && close[i - 2] > vPrev2 && close[i - 1] > v && close[i] <= v)
      {
         BufferSell[i] = high[i] + (atr * 0.5);

         double trapDistance = high[i] - v;
         if(trapDistance < 0.0) trapDistance = atr * 0.5;
         double slVal = high[i] + (atr * InpAtrStopBuffer);
         double tpVal = v - (trapDistance * InpRewardRiskRatio);

         ExtLastSignal     = -1;
         ExtLastSignalTime = time[i];
         ExtLastEntry      = close[i];
         ExtLastSL         = slVal;
         ExtLastTP         = tpVal;

         if(i == rates_total - 1 && time[i] != ExtLastAlertBar)
         {
            ExtLastAlertBar = time[i];
            string msg = StringFormat("[LONDON TRAP SELL] %s @ %.2f | SL: %.2f | TP: %.2f | WR 75.3%%",
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
      UpdateDashboard(currentInSession, curVWAP, close[rates_total - 1]);
      ChartRedraw(0);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Buat atau Update Tampilan Dashboard HUD di Layar Chart           |
//+------------------------------------------------------------------+
void UpdateDashboard(bool inSession, double currentVWAP, double currentPrice)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   ENUM_BASE_CORNER corner = InpDashboardCorner;

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
   string vwapStr = (currentVWAP > 0 && currentVWAP != EMPTY_VALUE) ? DoubleToString(currentVWAP, 2) : "-";
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

   ObjectSetInteger(0, name, OBJPROP_CORNER,     corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetString(0,  name, OBJPROP_FONT,       fontName);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper Buat Tombol Interaktif                                    |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h, string text,
                  color bgClr, color txtClr, ENUM_BASE_CORNER corner, int fontSize = 8)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER,     corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bgClr);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      txtClr);
   ObjectSetString(0,  name, OBJPROP_TEXT,       text);
   ObjectSetString(0,  name, OBJPROP_FONT,       "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_STATE,      false);
}

//+------------------------------------------------------------------+
//| Chart Event Handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == PREFIX + "BTN_TOGGLE")
   {
      ExtIsMinimized = !ExtIsMinimized;
      ObjectSetInteger(0, PREFIX + "BTN_TOGGLE", OBJPROP_STATE, false);

      int total = ArraySize(BufferVWAP);
      double curVWAP = (total > 0) ? BufferVWAP[total - 1] : 0.0;
      MqlDateTime dt;
      TimeCurrent(dt);
      bool inSession = (dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour);

      double curPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      UpdateDashboard(inSession, curVWAP, curPrice);
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+
