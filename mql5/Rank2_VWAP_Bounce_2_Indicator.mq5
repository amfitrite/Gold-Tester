//+------------------------------------------------------------------+
//|                                    Rank2_VWAP_Bounce_2_Indicator.mq5  |
//|      RANK 2: VWAP BOUNCE 2 ONLY - TUNED FOR MT5                                     |
//|     Indikator Real Sim Live + Simulasi Dummy Modal $10,000       |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Lab - Tuned for Broker Time"
#property link      "https://github.com/amfitrite/Gold-Tester"
#property version   "9.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "Session VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  2

#property indicator_label2  "Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  C'8,153,129'
#property indicator_width2  3

#property indicator_label3  "Sell Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  C'242,54,69'
#property indicator_width3  3

enum ENUM_THEME {
   THEME_DARK,
   THEME_LIGHT
};

input group "=== Tampilan & Tema ==="
input ENUM_THEME   InpTheme       = THEME_DARK;
input bool         InpShowPanel   = true;
input int          InpPanelX      = 15;
input int          InpPanelY      = 30;

input group "=== Broker Timezone & Sesi ==="
input int          InpBrokerGMTOffset = 3;     // GMT Offset Server Broker (FBS Trader = 3)
input int          InpUTCStart        = 7;     // Jam Mulai UTC (07:00 UTC = 10:00 Broker)
input int          InpUTCEnd          = 18;    // Jam Selesai UTC (18:00 UTC = 21:00 Broker)
input bool         InpWaitClose       = true;  // Sinyal Terkonfirmasi di Close Bar

input group "=== Parameter Trade & Target ==="
input int          InpAtrPeriod       = 14;    // Periode ATR
input int          InpMaxBars         = 48;    // Batas waktu trade (Expired Bars)
input int          InpLookback        = 1500;  // History bar ke belakang (M5)

input group "=== Simulasi Dummy Modal ($10,000) ==="
input double       InpInitialDeposit  = 10000.0; // Modal Awal Dummy ($)
input double       InpRiskPercent     = 1.0;     // Risiko per trade dari Ekuitas (%)

input group "=== Parameter Swap ==="
input bool         InpAutoSwap        = true;
input double       InpManualSwapLong  = -5.0;
input double       InpManualSwapShort = -2.0;

// Buffers
double BufVWAP[], BufBuy[], BufSell[];
double atrArr[], ema20Arr[], ema50Arr[];
int hATR = INVALID_HANDLE, hEMA20 = INVALID_HANDLE, hEMA50 = INVALID_HANDLE;

#define PFX "Rank2_VWAP_Bounce_2_MT5_"

int OnInit()
{
   SetIndexBuffer(0, BufVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(2, BufSell, INDICATOR_DATA);
   ArraySetAsSeries(BufVWAP, true);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 234);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);

   hATR   = iATR(_Symbol, _Period, InpAtrPeriod);
   hEMA20 = iMA(_Symbol, _Period, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hEMA20 == INVALID_HANDLE || hEMA50 == INVALID_HANDLE) return INIT_FAILED;
   ArraySetAsSeries(atrArr, true);
   ArraySetAsSeries(ema20Arr, true);
   ArraySetAsSeries(ema50Arr, true);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX);
   if(hATR != INVALID_HANDLE)   IndicatorRelease(hATR);
   if(hEMA20 != INVALID_HANDLE) IndicatorRelease(hEMA20);
   if(hEMA50 != INVALID_HANDLE) IndicatorRelease(hEMA50);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total < 100) return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);

   static datetime lastSimTime = 0;
   if(prev_calculated > 0 && time[0] == lastSimTime)
      return rates_total;
   lastSimTime = time[0];

   int lookback = (int)MathMin(rates_total - 50, InpLookback);
   if(lookback < 50) return 0;

   if(CopyBuffer(hATR, 0, 0, lookback + 50, atrArr) <= 0) return 0;
   if(CopyBuffer(hEMA20, 0, 0, lookback + 50, ema20Arr) <= 0) return 0;
   if(CopyBuffer(hEMA50, 0, 0, lookback + 50, ema50Arr) <= 0) return 0;

   ArrayInitialize(BufBuy, 0.0);
   ArrayInitialize(BufSell, 0.0);
   ArrayInitialize(BufVWAP, 0.0);

   double cumVol = 0.0, cumPV = 0.0;
   int lastDay = -1;
   for(int i = lookback; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      if(dt.day != lastDay)
      {
         cumVol = 0.0;
         cumPV  = 0.0;
         lastDay = dt.day;
      }
      double v = (double)tick_volume[i];
      if(v <= 0) v = 1.0;
      double typ = (high[i] + low[i] + close[i]) / 3.0;
      cumVol += v;
      cumPV  += (typ * v);
      BufVWAP[i] = (cumVol > 0) ? (cumPV / cumVol) : typ;
   }

   double equity = InpInitialDeposit;
   double peak_equity = equity;
   double max_dd_percent = 0.0;
   double total_swap_impact = 0.0;
   int wins = 0, losses = 0, expired = 0, total = 0, buys = 0, sells = 0;

   double asiaHigh = 0.0, asiaLow = 999999.0;
   int curAsiaDay = -1;

   int newest_bar = InpWaitClose ? 1 : 0;

   for(int i = lookback; i >= newest_bar; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      int utc_hour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

      if(dt.day != curAsiaDay)
      {
         asiaHigh = 0.0;
         asiaLow  = 999999.0;
         curAsiaDay = dt.day;
      }
      if(utc_hour < 7)
      {
         if(high[i] > asiaHigh) asiaHigh = high[i];
         if(low[i] < asiaLow)   asiaLow  = low[i];
      }

      if(utc_hour < InpUTCStart || utc_hour >= InpUTCEnd) continue;

      double curAtr = (i < ArraySize(atrArr)) ? atrArr[i] : (_Point * 20.0);
      if(curAtr <= 0) curAtr = _Point * 20.0;

      double candleRng = high[i] - low[i];
      if(candleRng <= 0) continue;

      double lowerWick = MathMin(open[i], close[i]) - low[i];
      double upperWick = high[i] - MathMax(open[i], close[i]);
      double vwapVal   = BufVWAP[i];
      double ema20     = (i < ArraySize(ema20Arr)) ? ema20Arr[i] : close[i];
      double ema50     = (i < ArraySize(ema50Arr)) ? ema50Arr[i] : close[i];

      bool isB = false;
      bool isS = false;
      double sl = 0.0;
      double tp = 0.0;

      // ENGINE 1: VWAP BOUNCE 2
      if(true)
      {
         if(low[i] <= (vwapVal * 1.0005) && close[i] >= vwapVal && (close[i] >= open[i] || lowerWick >= 0.35 * candleRng) && (close[i] >= ema50 || ema20 >= ema50))
         {
            isB = true;
            sl = low[i] - (curAtr * 0.5);
            double dist = vwapVal - low[i];
            double tp_dist = MathMax(dist, curAtr * 0.3) * 1.0;
            tp = vwapVal + tp_dist;
         }
         else if(high[i] >= (vwapVal * 0.9995) && close[i] <= vwapVal && (close[i] <= open[i] || upperWick >= 0.35 * candleRng) && (close[i] <= ema50 || ema20 <= ema50))
         {
            isS = true;
            sl = high[i] + (curAtr * 0.5);
            double dist = high[i] - vwapVal;
            double tp_dist = MathMax(dist, curAtr * 0.3) * 1.0;
            tp = vwapVal - tp_dist;
         }
      }

      // ENGINE 2: DOJI RIDE
      if(false && !isB && !isS && i < lookback - 1)
      {
         double body = MathAbs(close[i] - open[i]);
         if((body / candleRng) <= 0.10 && candleRng >= (0.4 * curAtr))
         {
            if(asiaLow < 999990.0 && low[i] < asiaLow && close[i] > asiaLow && (lowerWick / candleRng) >= 0.45)
            {
               isB = true;
               sl = low[i] - (0.2 * curAtr);
               double risk = MathAbs(open[i-1] - sl);
               tp = open[i-1] + (risk * 0.40);
            }
            else if(asiaHigh > 0 && high[i] > asiaHigh && close[i] < asiaHigh && (upperWick / candleRng) >= 0.45)
            {
               isS = true;
               sl = high[i] + (0.2 * curAtr);
               double risk = MathAbs(sl - open[i-1]);
               tp = open[i-1] - (risk * 0.40);
            }
         }
      }

      // ENGINE 3: LONDON SWEEP TRAP
      if(false && !isB && !isS && asiaHigh > 0 && asiaLow < 999990.0)
      {
         if(high[i] > asiaHigh && close[i] < asiaHigh && close[i] < open[i])
         {
            isS = true;
            sl = high[i] + (curAtr * 0.5);
            double dist = high[i] - vwapVal;
            tp = vwapVal - MathMax(dist, curAtr * 0.5);
         }
         else if(low[i] < asiaLow && close[i] > asiaLow && close[i] > open[i])
         {
            isB = true;
            sl = low[i] - (curAtr * 0.5);
            double dist = vwapVal - low[i];
            tp = vwapVal + MathMax(dist, curAtr * 0.5);
         }
      }

      // ENGINE 4: VP FAILED AUCTION
      if(false && !isB && !isS)
      {
         MqlRates dailyRates[];
         ArraySetAsSeries(dailyRates, true);
         if(CopyRates(_Symbol, PERIOD_D1, 1, 1, dailyRates) > 0)
         {
            double dLow  = dailyRates[0].low;
            double dHigh = dailyRates[0].high;
            double dRng  = dHigh - dLow;
            double val = dLow + dRng * 0.20;
            double vah = dLow + dRng * 0.80;
            if(low[i] < val && close[i] > val && close[i] > open[i])
            {
               isB = true;
               sl = low[i] - (curAtr * 0.5);
               tp = open[i-1] + (MathAbs(open[i-1] - sl) * 0.50);
            }
            else if(high[i] > vah && close[i] < vah && close[i] < open[i])
            {
               isS = true;
               sl = high[i] + (curAtr * 0.5);
               tp = open[i-1] - (MathAbs(sl - open[i-1]) * 0.50);
            }
         }
      }

      // ENGINE 5: LIQUIDITY BUBBLE TRAP
      if(false && !isB && !isS && i < lookback - 20)
      {
         double vMA = 0.0;
         for(int v = 1; v <= 20; v++) vMA += (double)tick_volume[i + v];
         vMA /= 20.0;
         if(vMA > 0 && ((double)tick_volume[i] / vMA) >= 2.2)
         {
            if(lowerWick > (candleRng * 0.40) && close[i] > open[i])
            {
               isB = true;
               sl = low[i] - (curAtr * 0.5);
               tp = open[i-1] + (MathAbs(open[i-1] - sl) * 0.85);
            }
            else if(upperWick > (candleRng * 0.40) && close[i] < open[i])
            {
               isS = true;
               sl = high[i] + (curAtr * 0.5);
               tp = open[i-1] - (MathAbs(sl - open[i-1]) * 0.85);
            }
         }
      }

      if(!isB && !isS) continue;

      if(isB) BufBuy[i]  = low[i]  - curAtr * 0.5;
      if(isS) BufSell[i] = high[i] + curAtr * 0.5;

      int entry_idx = InpWaitClose ? i - 1 : i;
      if(entry_idx < 0) continue;

      total++;
      if(isB) buys++; else sells++;

      double entry = open[entry_idx];
      double risk_dist = MathAbs(entry - sl);
      if(risk_dist <= 0) risk_dist = _Point * 15.0;

      bool resolved = false, hit_tp = false, hit_sl = false;
      int exit_idx = entry_idx;

      for(int j = entry_idx; j >= 0 && j >= entry_idx - InpMaxBars; j--)
      {
         exit_idx = j;
         if(isB)
         {
            if(low[j]  <= sl) { losses++; hit_sl = true; resolved = true; break; }
            if(high[j] >= tp) { wins++;   hit_tp = true; resolved = true; break; }
         }
         else
         {
            if(high[j] >= sl) { losses++; hit_sl = true; resolved = true; break; }
            if(low[j]  <= tp) { wins++;   hit_tp = true; resolved = true; break; }
         }
      }

      if(resolved)
      {
         double risk_usd = equity * (InpRiskPercent / 100.0);
         double r_mult = MathAbs(tp - entry) / risk_dist;

         double trade_swap_cost = 0;
         int days_held = (int)(time[exit_idx] / 86400) - (int)(time[entry_idx] / 86400);
         if(days_held > 0 && days_held < 60)
         {
            double swap_rate = isB ? (InpAutoSwap ? SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG) : InpManualSwapLong) :
                                     (InpAutoSwap ? SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT) : InpManualSwapShort);
            double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_sz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            if(tick_val > 0 && tick_sz > 0 && risk_dist > 0)
            {
               double est_lot = risk_usd / ((risk_dist / tick_sz) * tick_val);
               trade_swap_cost = est_lot * swap_rate * days_held;
            }
         }
         total_swap_impact += trade_swap_cost;

         if(hit_tp)
            equity += (risk_usd * r_mult) + trade_swap_cost;
         else if(hit_sl)
            equity += (-risk_usd) + trade_swap_cost;

         if(equity > peak_equity) peak_equity = equity;
         double dd = (peak_equity > 0) ? ((peak_equity - equity) / peak_equity * 100.0) : 0;
         if(dd > max_dd_percent) max_dd_percent = dd;

         i = exit_idx;
      }
      else
      {
         expired++;
      }
   }

   int closed = wins + losses;
   double wr = (closed > 0) ? (100.0 * wins / closed) : 0.0;
   double growth_pct = ((equity - InpInitialDeposit) / InpInitialDeposit) * 100.0;

   if(InpShowPanel)
   {
      string s = "";
      s += "===== SIMULASI DUMMY MODAL REAL MT5 =====\n";
      s += "RANK 2: VWAP BOUNCE 2 ONLY [TUNED]\n";
      s += "-----------------------------------------\n";
      s += StringFormat("History Lookback: %d Bar (M5)\n", lookback);
      s += StringFormat("Broker Server   : GMT+%d (Broker Time)\n", InpBrokerGMTOffset);
      s += StringFormat("Sesi Aktif (UTC): %02d:00 - %02d:00 UTC\n", InpUTCStart, InpUTCEnd);
      s += "-----------------------------------------\n";
      s += StringFormat("Total Sinyal    : %d (Buy: %d, Sell: %d)\n", total, buys, sells);
      s += StringFormat("Win / Loss      : %d / %d (WR: %.2f%%)\n", wins, losses, wr);
      s += StringFormat("Trade Expired   : %d\n", expired);
      s += "-----------------------------------------\n";
      s += StringFormat("Deposit Awal    : $%.2f\n", InpInitialDeposit);
      s += StringFormat("Total Biaya Swap: $%.2f\n", total_swap_impact);
      s += StringFormat("Saldo Akhir     : $%.2f\n", equity);
      s += StringFormat("Net Growth      : %+.2f%%\n", growth_pct);
      s += StringFormat("Max Drawdown    : %.2f%%\n", max_dd_percent);
      s += "-----------------------------------------\n";
      s += InpWaitClose ? "Mode: Sinyal Terkonfirmasi (Non-Repaint)" : "Mode: Sinyal Berjalan";

      ShowPanel(s);
   }

   return rates_total;
}

void ShowPanel(string text)
{
   string bgName = PFX + "BG";
   color bgCol, textCol, borderCol;
   if(InpTheme == THEME_DARK) {
      bgCol = C'20,24,35'; textCol = clrWhite; borderCol = clrDeepSkyBlue;
   } else {
      bgCol = clrWhiteSmoke; textCol = clrBlack; borderCol = clrDimGray;
   }

   string sep = "\n"; ushort u_sep = StringGetCharacter(sep, 0);
   string lines[]; int count = StringSplit(text, u_sep, lines);
   int boxH = count * 15 + 15;

   if(ObjectFind(0, bgName) < 0) {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, InpPanelX - 5);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, InpPanelY - 5);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 370);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, boxH);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, bgCol);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, borderCol);

   for(int i = 0; i < count; i++) {
      string name = PFX + "Line_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0) {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + (i * 15));
      ObjectSetInteger(0, name, OBJPROP_COLOR, (i == 1) ? clrGold : ((i >= 7 && i <= 9) ? clrLimeGreen : textCol));
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
   }

   int clear_idx = count;
   while(ObjectFind(0, PFX + "Line_" + IntegerToString(clear_idx)) >= 0) {
      ObjectDelete(0, PFX + "Line_" + IntegerToString(clear_idx));
      clear_idx++;
   }
}
//+------------------------------------------------------------------+
