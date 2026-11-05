//+------------------------------------------------------------------+
//|                                    Rank2_VWAP_Bounce_2_Indicator.mq5  |
//|      RANK 2: VWAP BOUNCE 2 ONLY      |
//|     Indikator Real Sim Live + Simulasi Dummy Modal $10,000       |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Lab - Real History Simulator"
#property link      "https://github.com/amfitrite/Gold-Tester"
#property version   "8.00"
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
   THEME_DARK,  // Latar Hitam (Dark Theme)
   THEME_LIGHT  // Latar Putih (Light Theme)
};

input group "=== Tampilan & Tema ==="
input ENUM_THEME   InpTheme       = THEME_DARK;
input bool         InpShowPanel   = true;
input int          InpPanelX      = 15;
input int          InpPanelY      = 30;

input group "=== Eksekusi Sinyal ==="
input bool         InpWaitClose   = true;  // Simulasi Entry di Open candle berikutnya (Non-Repaint)
input int          InpSessionStart= 7;     // Jam Mulai Sesi (07:00 UTC London)
input int          InpSessionEnd  = 18;    // Jam Akhir Sesi (18:00 UTC New York)

input group "=== Parameter Trade (SL & TP) ==="
input double       InpTargetRR    = 1.5;   // Reward:Risk Ratio (TP = RR * SL)
input double       InpAtrMult     = 1.5;   // Jarak SL (kali ATR)
input int          InpAtrPeriod   = 14;    // Periode ATR
input int          InpMaxBars     = 48;    // Batas waktu trade (Expired Bars)
input int          InpLookback    = 1500;  // Batas history bar ke belakang yang disimulasikan

input group "=== Simulasi Modal Real (Money Management) ==="
input double       InpInitialDeposit = 10000.0; // Modal Awal Dummy ($)
input double       InpRiskPercent    = 1.0;     // Risiko per trade dari Ekuitas (%)

input group "=== Parameter Swap (Biaya Inap Real) ==="
input bool         InpAutoSwap        = true;   // Auto-detect Swap dari Broker
input double       InpManualSwapLong  = -5.0;   // Manual Swap Long (USD per Lot) jika Auto false
input double       InpManualSwapShort = -2.0;   // Manual Swap Short (USD per Lot) jika Auto false

// Buffers
double BufVWAP[], BufBuy[], BufSell[];
double atrArr[], ema20Arr[], ema50Arr[];
int hATR = INVALID_HANDLE, hEMA20 = INVALID_HANDLE, hEMA50 = INVALID_HANDLE;

#define PFX "Rank2_VWAP_Bounce_2_"

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

   // Optimasi CPU: jalankan simulasi komplit saat candle baru
   static datetime lastSimTime = 0;
   if(prev_calculated > 0 && time[0] == lastSimTime)
      return rates_total;
   lastSimTime = time[0];

   int lookback = (int)MathMin(rates_total - 50, InpLookback);
   if(lookback < 50) return 0;

   if(CopyBuffer(hATR, 0, 0, lookback + 50, atrArr) <= 0) return 0;
   if(CopyBuffer(hEMA20, 0, 0, lookback + 50, ema20Arr) <= 0) return 0;
   if(CopyBuffer(hEMA50, 0, 0, lookback + 50, ema50Arr) <= 0) return 0;

   // 1. Calculate Daily Reset VWAP (Chronological order)
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

   // 2. Real History Simulation Engine
   double equity = InpInitialDeposit;
   double peak_equity = equity;
   double max_dd_percent = 0.0;
   double total_swap_impact = 0.0;
   int wins = 0, losses = 0, expired = 0, total = 0, buys = 0, sells = 0;

   // Pre-detect Asia Range
   double asiaHigh = 0.0, asiaLow = 999999.0;
   int curAsiaDay = -1;

   int newest_bar = InpWaitClose ? 1 : 0;

   for(int i = lookback; i >= newest_bar; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);

      // Asia High/Low tracking (00:00 - 06:55 UTC)
      if(dt.day != curAsiaDay)
      {
         asiaHigh = 0.0;
         asiaLow  = 999999.0;
         curAsiaDay = dt.day;
      }
      if(dt.hour < 7)
      {
         if(high[i] > asiaHigh) asiaHigh = high[i];
         if(low[i] < asiaLow)   asiaLow  = low[i];
      }

      // Check session window (07:00 - 18:00 UTC)
      if(dt.hour < InpSessionStart || dt.hour >= InpSessionEnd) continue;

      double curAtr = (i < ArraySize(atrArr)) ? atrArr[i] : (_Point * 20.0);
      if(curAtr <= 0) curAtr = _Point * 20.0;

      double candleRng = high[i] - low[i];
      if(candleRng <= 0) continue;

      double bodySize  = MathAbs(close[i] - open[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];
      double upperWick = high[i] - MathMax(open[i], close[i]);
      double vwapVal   = BufVWAP[i];
      double ema20     = (i < ArraySize(ema20Arr)) ? ema20Arr[i] : close[i];
      double ema50     = (i < ArraySize(ema50Arr)) ? ema50Arr[i] : close[i];

      bool isB = false;
      bool isS = false;
      string tag = "";

      // Engine 1: VWAP Bounce 2
      if(true)
      {
         double tol = vwapVal * 0.0006;
         if(low[i] <= (vwapVal + tol) && close[i] > vwapVal && ema20 > ema50 && (lowerWick / candleRng) >= 0.35 && close[i] > open[i])
         {
            isB = true; tag = "VWAP2";
         }
         else if(high[i] >= (vwapVal - tol) && close[i] < vwapVal && ema20 < ema50 && (upperWick / candleRng) >= 0.35 && close[i] < open[i])
         {
            isS = true; tag = "VWAP2";
         }
      }

      // Engine 2: Doji Ride
      if(false && !isB && !isS && i < lookback - 1)
      {
         int pb = i + 1;
         double pRng = high[pb] - low[pb];
         if(pRng > 0)
         {
            double pBody  = MathAbs(close[pb] - open[pb]);
            double pLower = MathMin(open[pb], close[pb]) - low[pb];
            double pUpper = high[pb] - MathMax(open[pb], close[pb]);
            if((pBody / pRng) <= 0.12)
            {
               if((pLower / pRng) >= 0.45 && high[i] > high[pb] && close[i] > open[i])
               {
                  isB = true; tag = "DOJI";
               }
               else if((pUpper / pRng) >= 0.45 && low[i] < low[pb] && close[i] < open[i])
               {
                  isS = true; tag = "DOJI";
               }
            }
         }
      }

      // Engine 3: London Sweep Trap
      if(false && !isB && !isS && asiaHigh > 0 && asiaLow < 999990.0)
      {
         if(high[i] > asiaHigh && close[i] < asiaHigh && close[i] < open[i])
         {
            isS = true; tag = "SWEEP";
         }
         else if(low[i] < asiaLow && close[i] > asiaLow && close[i] > open[i])
         {
            isB = true; tag = "SWEEP";
         }
      }

      // Engine 4: Volume Profile Failed Auction
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
               isB = true; tag = "VP_AUC";
            }
            else if(high[i] > vah && close[i] < vah && close[i] < open[i])
            {
               isS = true; tag = "VP_AUC";
            }
         }
      }

      // Engine 5: Liquidity Bubble Trap
      if(false && !isB && !isS && i < lookback - 20)
      {
         double vMA = 0.0;
         for(int v = 1; v <= 20; v++) vMA += (double)tick_volume[i + v];
         vMA /= 20.0;
         if(vMA > 0 && ((double)tick_volume[i] / vMA) >= 2.2)
         {
            if(lowerWick > bodySize && close[i] > open[i])
            {
               isB = true; tag = "BUBBLE";
            }
            else if(upperWick > bodySize && close[i] < open[i])
            {
               isS = true; tag = "BUBBLE";
            }
         }
      }

      if(isB) BufBuy[i]  = low[i]  - curAtr * 0.5;
      if(isS) BufSell[i] = high[i] + curAtr * 0.5;

      if(!isB && !isS) continue;

      int entry_idx = InpWaitClose ? i - 1 : i;
      if(entry_idx < 0) continue;

      total++;
      if(isB) buys++; else sells++;

      double entry = open[entry_idx];
      double sl_dist = MathMax(curAtr * InpAtrMult, _Point * 15.0);
      double sl = isB ? entry - sl_dist : entry + sl_dist;
      double tp = isB ? entry + (sl_dist * InpTargetRR) : entry - (sl_dist * InpTargetRR);

      bool resolved = false, hit_tp = false, hit_sl = false;
      int exit_idx = entry_idx;

      for(int j = entry_idx; j >= 0 && j >= entry_idx - InpMaxBars; j--)
      {
         if(isB)
         {
            if(low[j]  <= sl) { losses++; hit_sl = true; resolved = true; exit_idx = j; break; }
            if(high[j] >= tp) { wins++;   hit_tp = true; resolved = true; exit_idx = j; break; }
         }
         else
         {
            if(high[j] >= sl) { losses++; hit_sl = true; resolved = true; exit_idx = j; break; }
            if(low[j]  <= tp) { wins++;   hit_tp = true; resolved = true; exit_idx = j; break; }
         }
      }

      if(resolved)
      {
         double risk_usd = equity * (InpRiskPercent / 100.0);
         double trade_swap_cost = 0;

         // Real Swap Calculation
         int days_held = (int)(time[exit_idx] / 86400) - (int)(time[entry_idx] / 86400);
         if(days_held > 0 && days_held < 60)
         {
            double swap_rate = isB ? (InpAutoSwap ? SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG) : InpManualSwapLong) :
                                     (InpAutoSwap ? SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT) : InpManualSwapShort);
            double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double tick_sz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            if(tick_val > 0 && tick_sz > 0 && sl_dist > 0)
            {
               double est_lot = risk_usd / ((sl_dist / tick_sz) * tick_val);
               trade_swap_cost = est_lot * swap_rate * days_held;
            }
         }
         total_swap_impact += trade_swap_cost;

         if(hit_tp)
            equity += (risk_usd * InpTargetRR) + trade_swap_cost;
         else if(hit_sl)
            equity += (-risk_usd) + trade_swap_cost;

         if(equity > peak_equity) peak_equity = equity;
         double dd = (peak_equity > 0) ? ((peak_equity - equity) / peak_equity * 100.0) : 0;
         if(dd > max_dd_percent) max_dd_percent = dd;
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
      s += "RANK 2: VWAP BOUNCE 2 ONLY\n";
      s += "-----------------------------------------\n";
      s += StringFormat("History Lookback: %d Bar (M5)\n", lookback);
      s += StringFormat("Risk per Trade  : %.1f%%  |  RR: 1:%.1f\n", InpRiskPercent, InpTargetRR);
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
      ObjectSetInteger(0, name, OBJPROP_COLOR, (i == 1) ? clrGold : ((i >= 6 && i <= 8) ? clrLimeGreen : textCol));
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
   }

   int clear_idx = count;
   while(ObjectFind(0, PFX + "Line_" + IntegerToString(clear_idx)) >= 0) {
      ObjectDelete(0, PFX + "Line_" + IntegerToString(clear_idx));
      clear_idx++;
   }
}
//+------------------------------------------------------------------+
