//+------------------------------------------------------------------+
//|                                        ICT_IFVG_Indicator.mq5    |
//|               Custom Indicator: ICT Inversion Fair Value Gap     |
//|                                  Copyright 2026, Quant Trading   |
//+------------------------------------------------------------------+
#property copyright   "Quant Trading"
#property link        "https://github.com/amfitrite/Gold-Tester"
#property version     "1.00"
#property description "Indikator Visual ICT Inversion FVG + EMA Trend + Alert"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//--- PLOT 1: Sinyal Buy (Arrow)
#property indicator_label1  "IFVG Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- PLOT 2: Sinyal Sell (Arrow)
#property indicator_label2  "IFVG Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- PLOT 3: Fast EMA
#property indicator_label3  "Fast EMA (20)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- PLOT 4: Slow EMA
#property indicator_label4  "Slow EMA (50)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDarkOrange
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

//--- INPUT PARAMETERS
input group "=== PARAMETER STRATEGI IFVG ==="
input double   InpMinFVGPoints         = 0.50;      // Minimal Lebar FVG (Price Points)
input int      InpPullbackWindow       = 12;        // Maksimal Lilin Menunggu Retest
input int      InpMaxBarsToScan        = 500;       // Jumlah Lilin Historis yang Dianalisa

input group "=== FILTER TREN EMA ==="
input bool     InpUseEMATrend          = true;      // Wajibkan Filter Tren EMA
input int      InpFastEMAPeriod        = 20;        // Periode Fast EMA
input int      InpSlowEMAPeriod        = 50;        // Periode Slow EMA

input group "=== TAMPILAN VISUAL & ALERT ==="
input bool     InpDrawZones            = true;      // Gambar Kotak Zona IFVG
input color    InpColorBullishZone     = clrDeepSkyBlue; // Warna Zona Buy (Support)
input color    InpColorBearishZone     = clrCrimson;     // Warna Zona Sell (Resistance)
input bool     InpEnableAlerts         = true;      // Tampilkan Popup Alert saat Sinyal Muncul

//--- BUFFER ARRAYS
double         BufferBuy[];
double         BufferSell[];
double         BufferFastEMA[];
double         BufferSlowEMA[];

//--- INDICATOR HANDLES
int            ExtHandleFastEMA = INVALID_HANDLE;
int            ExtHandleSlowEMA = INVALID_HANDLE;
datetime       ExtLastAlertTime = 0;
string         ExtPrefix = "IFVG_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Binding Buffers
   SetIndexBuffer(0, BufferBuy, INDICATOR_DATA);
   SetIndexBuffer(1, BufferSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufferFastEMA, INDICATOR_DATA);
   SetIndexBuffer(3, BufferSlowEMA, INDICATOR_DATA);

   // Atur Simbol Panah (Wingdings)
   PlotIndexSetInteger(0, PLOT_ARROW, 233); // Panah Atas
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // Panah Bawah

   // Nilai Kosong
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   // Inisialisasi EMA
   ExtHandleFastEMA = iMA(_Symbol, _Period, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ExtHandleSlowEMA = iMA(_Symbol, _Period, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(ExtHandleFastEMA == INVALID_HANDLE || ExtHandleSlowEMA == INVALID_HANDLE)
   {
      Print("Gagal inisialisasi handle EMA!");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ExtHandleFastEMA != INVALID_HANDLE) IndicatorRelease(ExtHandleFastEMA);
   if(ExtHandleSlowEMA != INVALID_HANDLE) IndicatorRelease(ExtHandleSlowEMA);

   // Hapus semua kotak visual yang digambar oleh indikator
   ObjectsDeleteAll(0, ExtPrefix);
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
   if(rates_total < InpSlowEMAPeriod + 5) return 0;

   // Copy data EMA ke Buffer
   int calculatedEMA = CopyBuffer(ExtHandleFastEMA, 0, 0, rates_total, BufferFastEMA);
   int calculatedSlow = CopyBuffer(ExtHandleSlowEMA, 0, 0, rates_total, BufferSlowEMA);
   if(calculatedEMA <= 0 || calculatedSlow <= 0) return 0;

   int startBar = prev_calculated - 1;
   if(startBar < 3)
   {
      startBar = 3;
      ArrayInitialize(BufferBuy, 0.0);
      ArrayInitialize(BufferSell, 0.0);
      ObjectsDeleteAll(0, ExtPrefix);
   }

   int limit = MathMin(rates_total - 2, InpMaxBarsToScan);

   // Telusuri lilin dari masa lalu ke lilin terbaru
   for(int i = rates_total - limit; i < rates_total - 1; i++)
   {
      // 3-Bar FVG Check pada bar i: Candle 1=(i-2), Candle 2=(i-1), Candle 3=i
      double c1_high = high[i - 2];
      double c1_low  = low[i - 2];
      double c3_high = high[i];
      double c3_low  = low[i];

      // 1. BULLISH FVG ASLI (c3_low > c1_high)
      if((c3_low - c1_high) >= InpMinFVGPoints)
      {
         double zoneTop    = c3_low;
         double zoneBottom = c1_high;

         // Cari apakah lilin setelahnya CLOSE di bawah zoneBottom (Inversion menjadi RESISTANCE / SELL)
         for(int j = i + 1; j < rates_total - 1; j++)
         {
            if(close[j] < zoneBottom)
            {
               // Terjadi Inversi pada bar j! Sekarang cari Retest pertama dalam rentang Pullback Window
               int maxRetestBar = MathMin(rates_total - 1, j + InpPullbackWindow);
               for(int k = j + 1; k <= maxRetestBar; k++)
               {
                  // Retest Sell: harga menyentuh kembali Bottom zona dari bawah
                  if(high[k] >= zoneBottom && close[k] <= zoneBottom)
                  {
                     // Cek Filter Tren EMA (Fast EMA < Slow EMA)
                     bool trendOk = (!InpUseEMATrend) || (BufferFastEMA[k] < BufferSlowEMA[k]);

                     if(trendOk && BufferSell[k] == 0.0)
                     {
                        BufferSell[k] = high[k] + (zoneBottom - zoneTop) * 0.2; // Titik panah sell

                        // Gambar Kotak Zona jika diaktifkan
                        if(InpDrawZones)
                        {
                           string objName = ExtPrefix + "SELL_" + TimeToString(time[j]);
                           DrawZoneBox(objName, time[j], zoneTop, time[k], zoneBottom, InpColorBearishZone);
                        }

                        // Kirim Alert jika sinyal berada pada lilin yang baru terbentuk
                        if(InpEnableAlerts && k == rates_total - 2 && time[k] != ExtLastAlertTime)
                        {
                           ExtLastAlertTime = time[k];
                           Alert("ICT IFVG [SELL] Sinyal pada ", _Symbol, " (", EnumToString((ENUM_TIMEFRAMES)_Period), ") @ ", DoubleToString(close[k], _Digits));
                        }
                     }
                     break; // Hanya ambil retest pertama (first touch)
                  }
               }
               break; // Inversi sudah tercatat
            }
         }
      }

      // 2. BEARISH FVG ASLI (c1_low > c3_high)
      if((c1_low - c3_high) >= InpMinFVGPoints)
      {
         double zoneTop    = c1_low;
         double zoneBottom = c3_high;

         // Cari apakah lilin setelahnya CLOSE di atas zoneTop (Inversion menjadi SUPPORT / BUY)
         for(int j = i + 1; j < rates_total - 1; j++)
         {
            if(close[j] > zoneTop)
            {
               // Terjadi Inversi pada bar j! Sekarang cari Retest pertama dalam rentang Pullback Window
               int maxRetestBar = MathMin(rates_total - 1, j + InpPullbackWindow);
               for(int k = j + 1; k <= maxRetestBar; k++)
               {
                  // Retest Buy: harga menyentuh kembali Top zona dari atas
                  if(low[k] <= zoneTop && close[k] >= zoneTop)
                  {
                     // Cek Filter Tren EMA (Fast EMA > Slow EMA)
                     bool trendOk = (!InpUseEMATrend) || (BufferFastEMA[k] > BufferSlowEMA[k]);

                     if(trendOk && BufferBuy[k] == 0.0)
                     {
                        BufferBuy[k] = low[k] - (zoneTop - zoneBottom) * 0.2; // Titik panah buy

                        // Gambar Kotak Zona jika diaktifkan
                        if(InpDrawZones)
                        {
                           string objName = ExtPrefix + "BUY_" + TimeToString(time[j]);
                           DrawZoneBox(objName, time[j], zoneTop, time[k], zoneBottom, InpColorBullishZone);
                        }

                        // Kirim Alert jika sinyal berada pada lilin yang baru terbentuk
                        if(InpEnableAlerts && k == rates_total - 2 && time[k] != ExtLastAlertTime)
                        {
                           ExtLastAlertTime = time[k];
                           Alert("ICT IFVG [BUY] Sinyal pada ", _Symbol, " (", EnumToString((ENUM_TIMEFRAMES)_Period), ") @ ", DoubleToString(close[k], _Digits));
                        }
                     }
                     break; // Hanya ambil retest pertama (first touch)
                  }
               }
               break; // Inversi sudah tercatat
            }
         }
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Fungsi Menggambar Kotak Zona Visual di Chart                    |
//+------------------------------------------------------------------+
void DrawZoneBox(string name, datetime time1, double price1, datetime time2, double price2, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}
