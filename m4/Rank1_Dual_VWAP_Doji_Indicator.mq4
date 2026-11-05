//+------------------------------------------------------------------+
//|                                    Rank1_Dual_VWAP_Doji_Indicator.mq4  |
//|      RANK 1: DUAL (VWAP 2 + DOJI RIDE) - TUNED FOR FBS & MT4                               |
//|     Indikator Real Sim Live + Dummy Modal $10,000 + Chart Lines  |
//+------------------------------------------------------------------+
#property copyright "Quant Trading Lab - High Visibility Lines"
#property link      "https://github.com/amfitrite/Gold-Tester"
#property version   "9.50"
#property strict
#property indicator_chart_window
#property indicator_buffers 3

#property indicator_color1  C'0,102,204' // Deep Dodger Blue (High Contrast on White)
#property indicator_width1  2

#property indicator_color2  C'8,153,129' // Dark Emerald Green (High Contrast on White)
#property indicator_width2  3

#property indicator_color3  C'242,54,69' // Crimson Red (High Contrast on White)
#property indicator_width3  3

enum ENUM_THEME {
   THEME_DARK,  // Kotak Gelap Elegan (Sangat Kontras di Background Putih)
   THEME_LIGHT  // Kotak Terang Bersih
};

extern string         s0                 = "=== TAMPILAN & TEMA ===";
extern ENUM_THEME     InpTheme           = THEME_DARK;
extern bool           InpShowPanel       = true;
extern int            InpPanelX          = 370;
extern int            InpPanelY          = 30;
extern bool           InpDrawTradeLines  = true;  // Gambar Garis Entry, TP, SL di Chart
extern int            InpLineExtendBars  = 25;    // Panjang Garis ke Kanan (Bar)

extern string         s1                 = "=== BROKER TIMEZONE & SESI ===";
extern int            InpBrokerGMTOffset = 3;     // GMT Offset Server Broker (FBS Trader = 3)
extern int            InpUTCStart        = 7;     // Jam Mulai UTC (07:00 UTC = 10:00 FBS)
extern int            InpUTCEnd          = 18;    // Jam Selesai UTC (18:00 UTC = 21:00 FBS)
extern bool           InpWaitClose       = true;  // Sinyal Terkonfirmasi di Close Bar

extern string         s2                 = "=== PARAMETER TRADE & TARGET ===";
extern int            InpAtrPeriod       = 14;    // Periode ATR
extern int            InpMaxBars         = 48;    // Batas waktu trade (Expired Bars)
extern int            InpLookback        = 1500;  // History bar ke belakang (M5)

extern string         s3                 = "=== SIMULASI DUMMY MODAL ($10,000) ===";
extern double         InpInitialDeposit  = 10000.0; // Modal Awal Dummy ($)
extern double         InpRiskPercent     = 1.0;     // Risiko per trade dari Ekuitas (%)

extern string         s4                 = "=== PARAMETER SWAP ===";
extern bool           InpAutoSwap        = true;
extern double         InpManualSwapLong  = -5.0;
extern double         InpManualSwapShort = -2.0;

// Buffers
double BufVWAP[], BufBuy[], BufSell[];
#define PFX "R1_"
#define STRAT_TAG "R1"

int OnInit()
{
   ObjectsDeleteAll(0, "LST4_");
   ObjectsDeleteAll(0, PFX);

   IndicatorBuffers(3);

   SetIndexBuffer(0, BufVWAP);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, C'0,102,204');
   SetIndexLabel(0, "Session VWAP");

   SetIndexBuffer(1, BufBuy);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 3, C'8,153,129');
   SetIndexArrow(1, 233);
   SetIndexLabel(1, "Buy Signal");

   SetIndexBuffer(2, BufSell);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 3, C'242,54,69');
   SetIndexArrow(2, 234);
   SetIndexLabel(2, "Sell Signal");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, 0.0);
   SetIndexEmptyValue(2, 0.0);

   IndicatorShortName("RANK 1: DUAL (VWAP 2 + DOJI RIDE)");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX);
   ChartRedraw(0);
}

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
   if(rates_total < 100) return 0;

   int lookback = MathMin(InpLookback, rates_total - 50);

   // 1. Session VWAP Calculation (Daily Reset at 00:00 UTC)
   int startBar = MathMin(rates_total - 1, lookback + 100);
   double runningPV = 0.0;
   double runningVol = 0.0;

   for(int k = startBar; k >= 0; k--)
   {
      MqlDateTime dt;
      TimeToStruct(time[k], dt);
      int utc_hour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

      if(k == rates_total - 1)
      {
         runningPV = 0.0;
         runningVol = 0.0;
      }
      else
      {
         MqlDateTime prev_dt;
         TimeToStruct(time[k+1], prev_dt);
         if(dt.day != prev_dt.day)
         {
            runningPV = 0.0;
            runningVol = 0.0;
         }
      }

      double tpPrice = (high[k] + low[k] + close[k]) / 3.0;
      double vol = (tick_volume[k] > 0) ? (double)tick_volume[k] : 1.0;
      runningPV += tpPrice * vol;
      runningVol += vol;

      BufVWAP[k] = (runningVol > 0.0) ? (runningPV / runningVol) : tpPrice;
      BufBuy[k] = 0.0;
      BufSell[k] = 0.0;
   }

   // 2. Real Simulation Engine ($10,000 Dummy Deposit)
   double equity = InpInitialDeposit;
   double peak_equity = InpInitialDeposit;
   double max_dd_amount = 0.0;
   double max_dd_percent = 0.0;
   int total = 0, wins = 0, losses = 0, buys = 0, sells = 0, expired = 0;
   double total_swap_impact = 0.0;

   double swap_long = InpManualSwapLong;
   double swap_short = InpManualSwapShort;
   if(InpAutoSwap)
   {
      double broker_sl = MarketInfo(Symbol(), MODE_SWAPLONG);
      double broker_ss = MarketInfo(Symbol(), MODE_SWAPSHORT);
      if(broker_sl != 0.0 || broker_ss != 0.0)
      {
         swap_long = broker_sl;
         swap_short = broker_ss;
      }
   }

   // Track Last Signal for Chart Lines
   datetime last_sig_time = 0;
   double last_sig_entry = 0.0;
   double last_sig_sl = 0.0;
   double last_sig_tp = 0.0;
   bool last_sig_is_buy = false;

   int newest_bar = InpWaitClose ? 1 : 0;

   for(int i = lookback; i >= newest_bar; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int utc_hour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

      if(utc_hour < InpUTCStart || utc_hour > InpUTCEnd)
         continue;

      double curAtr = iATR(NULL, 0, InpAtrPeriod, i);
      if(curAtr <= 0.05) curAtr = MathMax(high[i] - low[i], 1.0);

      double vwapVal = BufVWAP[i];
      if(vwapVal == EMPTY_VALUE || vwapVal <= 0.0) continue;

      double ema20 = iMA(NULL, 0, 20, 0, MODE_EMA, PRICE_CLOSE, i);
      double ema50 = iMA(NULL, 0, 50, 0, MODE_EMA, PRICE_CLOSE, i);

      double candleRng = MathMax(high[i] - low[i], _Point * 10);
      double upperWick = high[i] - MathMax(open[i], close[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];

      // Session Asian High/Low
      double asiaHigh = 0.0;
      double asiaLow  = 999999.0;
      for(int a = i + 1; a <= i + 72 && a < rates_total; a++)
      {
         MqlDateTime a_dt;
         TimeToStruct(time[a], a_dt);
         int a_utc = (a_dt.hour - InpBrokerGMTOffset + 24) % 24;
         if(a_utc >= 0 && a_utc < 7)
         {
            if(high[a] > asiaHigh) asiaHigh = high[a];
            if(low[a] < asiaLow)   asiaLow  = low[a];
         }
         if(a_utc >= 22) break;
      }

      bool isB = false;
      bool isS = false;
      double sl = 0.0, tp = 0.0;

      // ENGINE: PURE LONDON SWEEP TRAP (INSTITUTIONAL VWAP TRAP)
      if(false && i < lookback - 2)
      {
         double vPrev  = BufVWAP[i + 1];
         double vPrev2 = BufVWAP[i + 2];
         if(vPrev != EMPTY_VALUE && vPrev2 != EMPTY_VALUE)
         {
            bool allowBuy  = (close[i] >= ema50 || ema20 >= ema50);
            bool allowSell = (close[i] <= ema50 || ema20 <= ema50);

            // Bullish Trap: Price pushed below VWAP, sweeps liquidity, reclaims VWAP
            if(allowBuy && close[i + 2] < vPrev2 && close[i + 1] < vPrev && close[i] >= vwapVal)
            {
               isB = true;
               sl = low[i] - (curAtr * 0.5);
               double trapDist = MathMax(vwapVal - low[i], curAtr * 0.3);
               tp = vwapVal + (trapDist * 1.5);
            }
            // Bearish Trap: Price pushed above VWAP, sweeps liquidity, falls back below VWAP
            else if(allowSell && close[i + 2] > vPrev2 && close[i + 1] > vPrev && close[i] <= vwapVal)
            {
               isS = true;
               sl = high[i] + (curAtr * 0.5);
               double trapDist = MathMax(high[i] - vwapVal, curAtr * 0.3);
               tp = vwapVal - (trapDist * 1.5);
            }
         }
      }

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
      if(true && !isB && !isS && i < lookback - 1)
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

      // ENGINE 3: LONDON SWEEP TRAP (MULTI-PORTFOLIO VARIANT)
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
         double dLow  = iLow(NULL, PERIOD_D1, 1);
         double dHigh = iHigh(NULL, PERIOD_D1, 1);
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

      total++;
      if(isB) buys++; else sells++;

      double entry = InpWaitClose ? open[i-1] : close[i];
      if(isB) BufBuy[i] = low[i] - (curAtr * 0.3);
      else    BufSell[i] = high[i] + (curAtr * 0.3);

      // Record for Chart Lines
      last_sig_time = time[i];
      last_sig_entry = entry;
      last_sig_sl = sl;
      last_sig_tp = tp;
      last_sig_is_buy = isB;

      // Calculate Position Sizing
      double sl_dist = MathAbs(entry - sl);
      if(sl_dist <= 0.0) sl_dist = curAtr;
      double risk_amount = equity * (InpRiskPercent / 100.0);
      double lot = (sl_dist > 0.0) ? (risk_amount / (sl_dist * 100.0)) : 0.01;
      lot = MathMax(0.01, MathMin(10.0, NormalizeDouble(lot, 2)));

      // Non-Overlapping Sequential Forward Simulation
      int exit_idx = i - 1;
      bool won = false;
      bool hit = false;
      int holding_bars = 0;

      while(exit_idx >= 0 && holding_bars < InpMaxBars)
      {
         holding_bars++;
         if(isB)
         {
            if(low[exit_idx] <= sl)  { won = false; hit = true; break; }
            if(high[exit_idx] >= tp) { won = true;  hit = true; break; }
         }
         else
         {
            if(high[exit_idx] >= sl) { won = false; hit = true; break; }
            if(low[exit_idx] <= tp)  { won = true;  hit = true; break; }
         }
         exit_idx--;
      }

      // Calculate PnL & Swaps
      double pnl = 0.0;
      double swap_cost = 0.0;
      int days_held = (holding_bars * Period()) / 1440;
      if(days_held > 0)
      {
         double daily_swap = isB ? swap_long : swap_short;
         swap_cost = daily_swap * lot * days_held;
         total_swap_impact += swap_cost;
      }

      if(hit)
      {
         if(won)
         {
            wins++;
            pnl = MathAbs(tp - entry) * 100.0 * lot + swap_cost;
         }
         else
         {
            losses++;
            pnl = -MathAbs(entry - sl) * 100.0 * lot + swap_cost;
         }
      }
      else
      {
         expired++;
         double curExit = (exit_idx >= 0) ? close[exit_idx] : close[0];
         pnl = isB ? ((curExit - entry) * 100.0 * lot) : ((entry - curExit) * 100.0 * lot);
         pnl += swap_cost;
         if(pnl > 0.0) wins++; else losses++;
      }

      equity += pnl;
      if(equity > peak_equity) peak_equity = equity;
      double cur_dd = peak_equity - equity;
      if(cur_dd > max_dd_amount)
      {
         max_dd_amount = cur_dd;
         max_dd_percent = (peak_equity > 0.0) ? ((max_dd_amount / peak_equity) * 100.0) : 0.0;
      }

      // Advance loop index to exit_idx to prevent trade overlap spam
      if(exit_idx < i)
         i = exit_idx + 1; // Loop decrement will make it exit_idx
   }

   int closed = wins + losses;
   double wr = (closed > 0) ? (100.0 * wins / closed) : 0.0;
   double growth_pct = ((equity - InpInitialDeposit) / InpInitialDeposit) * 100.0;

   // 3. Draw Chart Lines for Active/Latest Signal
   if(InpDrawTradeLines && last_sig_time > 0)
   {
      DrawTradeLines(last_sig_time, last_sig_entry, last_sig_sl, last_sig_tp, last_sig_is_buy);
   }

   // 4. Update Dashboard HUD
   if(InpShowPanel)
   {
      string s = "";
      s += "===== SIMULASI DUMMY MODAL REAL MT4 =====\n";
      s += "RANK 1: DUAL (VWAP 2 + DOJI RIDE) [TUNED]\n";
      s += "-----------------------------------------\n";
      s += StringFormat("History Lookback: %d Bar (M5)\n", lookback);
      s += StringFormat("Broker Server   : GMT+%d (FBS Server Time)\n", InpBrokerGMTOffset);
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
      if(last_sig_time > 0)
      {
         s += StringFormat("Sinyal Terakhir : [%s] @ %.2f\n", last_sig_is_buy ? "BUY" : "SELL", last_sig_entry);
         s += StringFormat("Target TP/SL    : TP %.2f | SL %.2f\n", last_sig_tp, last_sig_sl);
         s += "Status Garis    : [ON] Tergambar di Chart\n";
      }
      else
      {
         s += "Sinyal Terakhir : Menunggu Setup...\n";
      }
      s += "-----------------------------------------\n";
      s += InpWaitClose ? "Mode: Sinyal Terkonfirmasi (Non-Repaint)" : "Mode: Sinyal Berjalan";

      ShowPanel(s);
   }

   return rates_total;
}

void DrawTradeLines(datetime t_sig, double entry, double sl, double tp, bool is_buy)
{
   datetime t_end = Time[0] + Period() * 60 * InpLineExtendBars;

   string nameEntry = PFX + "Line_Entry";
   string nameSL    = PFX + "Line_SL";
   string nameTP    = PFX + "Line_TP";
   string lblEntry  = PFX + "Lbl_Entry";
   string lblSL     = PFX + "Lbl_SL";
   string lblTP     = PFX + "Lbl_TP";

   // High visibility colors for white background
   color colEntry = C'0,90,210';   // Deep Dodger Blue
   color colSL    = C'220,30,40';  // Crimson Red
   color colTP    = C'0,140,50';   // Dark Emerald Green

   DrawOneTrendLine(nameEntry, t_sig, entry, t_end, entry, colEntry, STYLE_SOLID, 2);
   DrawOneText(lblEntry, t_end, entry, StringFormat("[%s ENTRY] %.2f", STRAT_TAG, entry), colEntry);

   DrawOneTrendLine(nameSL, t_sig, sl, t_end, sl, colSL, STYLE_DASH, 2);
   DrawOneText(lblSL, t_end, sl, StringFormat("[%s SL] %.2f", STRAT_TAG, sl), colSL);

   DrawOneTrendLine(nameTP, t_sig, tp, t_end, tp, colTP, STYLE_DASH, 2);
   DrawOneText(lblTP, t_end, tp, StringFormat("[%s TP] %.2f", STRAT_TAG, tp), colTP);
}

void DrawOneTrendLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int style, int width)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   else
   {
      ObjectSet(name, OBJPROP_TIME1, t1);
      ObjectSet(name, OBJPROP_PRICE1, p1);
      ObjectSet(name, OBJPROP_TIME2, t2);
      ObjectSet(name, OBJPROP_PRICE2, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
}

void DrawOneText(string name, datetime t, double p, string txt, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   else
   {
      ObjectSet(name, OBJPROP_TIME1, t);
      ObjectSet(name, OBJPROP_PRICE1, p);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void ShowPanel(string text)
{
   string bgName = PFX + "BG";
   color bgCol, textCol, borderCol;
   if(InpTheme == THEME_DARK) {
      bgCol = C'20,24,35'; textCol = clrWhite; borderCol = clrDeepSkyBlue;
   } else {
      bgCol = clrWhiteSmoke; textCol = clrBlack; borderCol = C'70,80,95';
   }

   string sep = "\n"; ushort u_sep = StringGetCharacter(sep, 0);
   string lines[]; int count = StringSplit(text, u_sep, lines);
   int boxH = count * 15 + 15;

   if(ObjectFind(0, bgName) < 0) {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, InpPanelX - 5);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, InpPanelY - 5);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 350);
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
      color lineCol = textCol;
      if(InpTheme == THEME_DARK) {
         lineCol = (i == 1) ? clrGold : ((i >= 7 && i <= 9) ? clrLimeGreen : textCol);
      } else {
         lineCol = (i == 1) ? C'0,90,190' : ((i >= 7 && i <= 9) ? C'0,130,50' : textCol);
      }
      ObjectSetInteger(0, name, OBJPROP_COLOR, lineCol);
      ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
   }
}
