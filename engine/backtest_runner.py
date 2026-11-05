#!/usr/bin/env python3
"""Unified Backtest Runner & Portfolio Simulator for Electron GUI.

Runs sweepbt strategies on CSV data, simulates account growth starting from
e.g. $10,000, calculates Win Rate, Growth %, Drawdown, generates interactive
report HTML, MT5 .set configuration, and MQL5 logic blueprint.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict, List

# Ensure src is in python path
current_dir = os.path.dirname(os.path.abspath(__file__))
src_dir = os.path.join(current_dir, "src")
if src_dir not in sys.path:
    sys.path.insert(0, src_dir)

from sweepbt.chart import write_report
from sweepbt.engine import run_file
from sweepbt.params import Params
from sweepbt.strategies import REGISTRY


# Strategies whose target is part of the edge, not a user-tunable knob.
# The UI/CLI may still send its global default (2.0R); force the tested value
# so the JSON summary, .set file and MQL5 blueprint stay consistent.
FIXED_RR = {
    "london_ny_vwap_pullback": 1.0,
    "volume_profile_failed_auction": 0.5,
    "liquidity_bubble_trap": 0.85,
    "doji_ride": 0.4,
}


def format_dt(dt: Any) -> str:
    if isinstance(dt, datetime):
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    return str(dt)


def simulate_portfolio(
    setups: list,
    candles: list,
    initial_balance: float = 10000.0,
    risk_pct: float = 1.0,
    use_trend_filter: bool = True
) -> Dict[str, Any]:
    """Simulate account portfolio with $10,000 initial balance."""
    # Filter setups based on trend filter setting
    if use_trend_filter:
        trades = [s for s in setups if s.filter_kept]
    else:
        trades = list(setups)

    balance = float(initial_balance)
    peak_balance = float(initial_balance)
    max_dd_amount = 0.0
    max_dd_pct = 0.0

    wins = 0
    losses = 0
    unresolved = 0
    total_profit = 0.0
    total_loss = 0.0

    trade_records = []
    equity_curve = [{"time": "Start", "balance": round(balance, 2), "drawdown_pct": 0.0}]

    for idx, s in enumerate(trades):
        # Time of entry
        entry_time_str = ""
        if s.entry_index < len(candles):
            entry_time_str = format_dt(candles[s.entry_index].timestamp)
        else:
            entry_time_str = f"Trade #{idx+1}"

        # Risk amount for this trade (e.g. 1% of current balance or initial balance)
        risk_amount = (balance * (risk_pct / 100.0)) if balance > 0 else (initial_balance * (risk_pct / 100.0))
        
        # Realized PnL ($)
        # s.r_multiple: +RR on win, -1.0 on loss, 0 on unresolved
        pnl = risk_amount * s.r_multiple
        balance += pnl

        if s.verdict == "win" or s.r_multiple > 0:
            wins += 1
            total_profit += pnl
        elif s.verdict == "loss" or s.r_multiple < 0:
            losses += 1
            total_loss += abs(pnl)
        else:
            unresolved += 1

        # Track Drawdown
        if balance > peak_balance:
            peak_balance = balance

        current_dd_amt = peak_balance - balance
        current_dd_pct = (current_dd_amt / peak_balance * 100.0) if peak_balance > 0 else 0.0

        if current_dd_amt > max_dd_amount:
            max_dd_amount = current_dd_amt
        if current_dd_pct > max_dd_pct:
            max_dd_pct = current_dd_pct

        trade_records.append({
            "id": idx + 1,
            "time": entry_time_str,
            "direction": s.direction.upper() if hasattr(s.direction, "upper") else str(s.direction),
            "entry_price": round(s.entry_price, 3),
            "stop_loss": round(s.stop_loss, 3),
            "take_profit": round(s.take_profit, 3),
            "verdict": s.verdict.upper() if hasattr(s.verdict, "upper") else str(s.verdict),
            "r_multiple": round(s.r_multiple, 2),
            "pnl": round(pnl, 2),
            "balance": round(balance, 2)
        })

        equity_curve.append({
            "time": entry_time_str,
            "balance": round(balance, 2),
            "drawdown_pct": round(current_dd_pct, 2)
        })

    total_trades = wins + losses + unresolved
    win_rate = (wins / (wins + losses) * 100.0) if (wins + losses) > 0 else 0.0
    profit_factor = (total_profit / total_loss) if total_loss > 0 else (999.0 if total_profit > 0 else 1.0)
    net_profit = balance - initial_balance
    growth_pct = (net_profit / initial_balance) * 100.0
    avg_win = (total_profit / wins) if wins > 0 else 0.0
    avg_loss = (total_loss / losses) if losses > 0 else 0.0

    return {
        "initial_balance": round(initial_balance, 2),
        "final_balance": round(balance, 2),
        "net_profit": round(net_profit, 2),
        "growth_pct": round(growth_pct, 2),
        "win_rate": round(win_rate, 2),
        "total_trades": total_trades,
        "wins": wins,
        "losses": losses,
        "unresolved": unresolved,
        "profit_factor": round(profit_factor, 2),
        "max_drawdown_amount": round(max_dd_amount, 2),
        "max_drawdown_pct": round(max_dd_pct, 2),
        "avg_win": round(avg_win, 2),
        "avg_loss": round(avg_loss, 2),
        "equity_curve": equity_curve,
        "trades": trade_records
    }


def generate_mt5_set_file(strategy: str, params: Params, risk_pct: float) -> str:
    """Generate MT5 Expert Advisor .set parameter file."""
    header = [
        "; ===========================================================",
        f"; MT5 EA Configuration: {strategy.upper()} Strategy",
        f"; Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "; ===========================================================",
        f"InpStrategyName={strategy}",
        f"InpRiskPercent={risk_pct:.2f}",
    ]
    if strategy == "london_ny_vwap_pullback":
        return "\n".join(header + [
            "InpRewardRiskRatio=1.00",
            "InpSessionStartHour=7",
            "InpSessionEndHour=17",
            "InpEmaPeriod=200",
            "InpAtrPeriod=14",
            "InpSlAtr=1.25",
            "InpTpAtr=1.25",
            "InpMaxHoldBars=24",
            "InpHalfSpread=0.12",
            "InpOnePositionAtATime=1",
            "InpMagicNumber=888555",
            "InpSlippagePips=3",
        ])
    if strategy == "volume_profile_failed_auction":
        return "\n".join(header + [
            "InpRewardRiskRatio=0.50",
            "InpProfileBinSize=5.00",
            "InpValueArea=0.80",
            "InpSessionStartHour=9",
            "InpSessionEndHour=11",
            "InpAtrPeriod=14",
            "InpSlAtrBuffer=0.50",
            "InpMaxHoldBars=48",
            "InpHalfSpread=0.12",
            "InpLongOnly=1",
            "InpOnePositionAtATime=1",
            "InpMagicNumber=888558",
            "InpSlippagePips=3",
        ])
    if strategy == "variance_ratio_regime":
        return "\n".join(header + [
            f"InpRewardRiskRatio={params.rr:.2f}",
            "InpReturnLookback=96",
            "InpDisplacementBars=12",
            "InpVarianceLag=4",
            "InpEntryZScore=2.00",
            "InpVarianceRatioThreshold=0.80",
            "InpMode=reversion",
            "InpStopATR=1.00",
            "InpMaxHoldBars=12",
            "InpHalfSpread=0.12",
            "InpOnePositionAtATime=1",
            "InpMagicNumber=888557",
            "InpSlippagePips=3",
        ])
    if strategy == "doji_ride":
        return "\n".join(header + [
            f"InpRewardRiskRatio={params.rr:.2f}",
            "InpMaxBodyRatio=0.08",
            "InpMinWickRatio=0.50",
            "InpMinRangeAtr=0.50",
            "InpSlAtrBuffer=0.20",
            "InpSessionStartHour=7",
            "InpSessionEndHour=18",
            "InpAsianStartHour=0",
            "InpAsianEndHour=6",
            "InpOnePositionAtATime=1",
            "InpMagicNumber=888570",
            "InpSlippagePips=3",
        ])

    if strategy == "doji_ride":
        return f"""//+------------------------------------------------------------------+
//| MQL5 LOGIC BLUEPRINT: DOJI_RIDE
//| Structural Liquidity Sweep & Doji Absorption Momentum Breakout
//+------------------------------------------------------------------+

// 1. INPUT PARAMETERS
input double InpRiskPercent          = 1.0;          // Risk % per trade
input double InpRewardRiskRatio      = {params.rr:.2f};        // Target RR ({params.rr}:1)
input double InpMaxBodyRatio         = 0.08;         // Max body/range ratio (thin body indecision)
input double InpMinWickRatio         = 0.50;         // Min rejection wick ratio (50%)
input double InpMinRangeAtr          = 0.50;         // Min candle range (0.50x ATR)
input double InpSlAtrBuffer          = 0.20;         // Stop loss buffer (0.20x ATR)
input int    InpSessionStartHour     = 7;            // London session open (07:00 UTC)
input int    InpSessionEndHour       = 18;           // NY session close (18:00 UTC)
input int    InpAsianStartHour       = 0;            // Asian session open (00:00 UTC)
input int    InpAsianEndHour         = 6;            // Asian session close (06:55 UTC)

// 2. ENTRY LOGIC
// - Identifies Prior-Day High/Low (PDH/PDL) and Asian Session High/Low (ASH/ASL).
// - Doji Rejection Filter:
//   * Range >= 0.50 * ATR(14) and abs(Close - Open) / Range <= 0.08
//   * Bullish Doji: Sweeps PDL or ASL, closes back above, lower wick >= 50% range.
//   * Bearish Doji: Sweeps PDH or ASH, closes back below, upper wick >= 50% range.
// - Momentum Ride Trigger:
//   * Wait for Doji candle (i) to close.
//   * On candle i+1, enter immediately as price breaches Doji High (Buy) or Doji Low (Sell).
//   * Stop Loss = opposite wick tip +- 0.20 * ATR(14).
//   * Take Profit = Entry +- Risk * {params.rr:.2f}.
"""

    if strategy == "liquidity_bubble_trap":
        return "\n".join(header + [
            f"InpRewardRiskRatio={params.rr:.2f}",
            f"InpSwingStrength={params.swing_strength if params.swing_strength else 5}",
            "InpVolumeBubbleMultiplier=1.35",
            "InpWickRatioThreshold=0.45",
            "InpSessionStartHour=7",
            "InpSessionEndHour=18",
            "InpAtrPeriod=14",
            "InpSlAtrBuffer=0.25",
            "InpFastEma=20",
            "InpSlowEma=50",
            "InpOnePositionAtATime=1",
            "InpMagicNumber=888560",
            "InpSlippagePips=3",
        ])

    return "\n".join(header + [
        f"InpRewardRiskRatio={params.rr:.2f}",
        f"InpSwingStrength={params.swing_strength}",
        f"InpMinFVGPoints={params.min_fvg_size:.2f}",
        f"InpSLBufferPoints={params.sl_buffer:.2f}",
        f"InpPullbackWindow={params.pullback_window}",
        f"InpTrendFilterMethod={params.trend_method}",
        f"InpCloseConfirmation={1 if params.require_close_confirmation else 0}",
        f"InpMaxRiskPoints={params.max_risk if params.max_risk else 0}",
        "InpMagicNumber=888555",
        "InpSlippagePips=3"
    ])


def generate_mql5_blueprint(strategy: str, params: Params) -> str:
    """Generate structured MQL5 code logic blueprint for MT5."""
    if strategy == "liquidity_bubble_trap":
        return f"""//+------------------------------------------------------------------+
//| MQL5 LOGIC BLUEPRINT: LIQUIDITY_BUBBLE_TRAP
//| Swing Liquidity Sweep + Bookmap-style Volume Bubble Absorption
//+------------------------------------------------------------------+

// 1. INPUT PARAMETERS
input double InpRiskPercent          = 1.0;          // Risk % per trade
input double InpRewardRiskRatio      = {params.rr:.2f};        // Target RR ({params.rr}:1)
input int    InpSwingStrength        = {params.swing_strength if params.swing_strength else 5};            // Swing pivot bars
input double InpVolumeMultiplier     = 1.35;         // Bubble volume threshold (1.35x SMA20)
input double InpWickRatioThreshold   = 0.45;         // Min rejection wick ratio (45%)
input int    InpSessionStartHour     = 7;            // London session open (07:00 UTC)
input int    InpSessionEndHour       = 18;           // NY session close (18:00 UTC)

// 2. ENTRY LOGIC
// - Identifies swing high/low within lookback = 50 bars.
// - Checks bar volume >= 1.35 * SMA(Volume, 20).
// - Bear Trap (Sell): sweeps swing high, closes <= swing high, upper wick >= 45% range, EMA20 <= EMA50.
//   SL = High + ATR(14) * 0.25, TP = Close - Risk * RR.
// - Bull Trap (Buy): sweeps swing low, closes >= swing low, lower wick >= 45% range, EMA20 >= EMA50.
//   SL = Low - ATR(14) * 0.25, TP = Close + Risk * RR.
"""

    if strategy == "london_ny_vwap_pullback":
        return """//+------------------------------------------------------------------+
//| MQL5 LOGIC BLUEPRINT: LONDON_NY_VWAP_PULLBACK
//| Session VWAP reclaim + EMA-200 trend filter + ATR bracket
//+------------------------------------------------------------------+

// 1. INPUT PARAMETER
input double InpRiskPercent      = 1.5;    // Risk % per trade (recommended 1.0-1.5)
input int    InpSessionStartHour = 7;      // UTC, inclusive
input int    InpSessionEndHour   = 17;     // UTC, inclusive
input int    InpEmaPeriod        = 200;    // Trend bias EMA
input int    InpAtrPeriod        = 14;     // Volatility bracket
input double InpSlAtr            = 1.25;   // Stop distance = 1.25 x ATR
input double InpTpAtr            = 1.25;   // Target distance = 1.25 x ATR (1:1)
input int    InpMaxHoldBars      = 24;     // Time stop: 24 x M5 = 2 hours
input double InpHalfSpread       = 0.12;   // Modelled cost per side on XAUUSD
input int    InpMagicNumber      = 888555;

// 2. PER-BAR STATE (M5 ONLY)
// - Reset cumulative VWAP at 00:00 UTC:
//     typical = (high + low + close) / 3
//     VWAP = sum(typical * volume) / sum(volume)
// - EMA200 on closes, using only closed bars.
// - Only evaluate entries when server hour is 07..17 UTC.
// - Skip a new signal while a position from this strategy is open.

// 3. ENTRY RULES (evaluated on the closed bar)
// Long:
//   low <= VWAP  AND  close > VWAP  AND  close > open
//   AND close > EMA200
// Short:
//   high >= VWAP AND  close < VWAP  AND  close < open
//   AND close < EMA200
// Enter at the next bar open. One position at a time.

// 4. EXIT RULES
// risk = InpSlAtr * ATR(14) at the signal bar
// Long : SL = entry - risk; TP = entry + InpTpAtr * ATR
// Short: SL = entry + risk; TP = entry - InpTpAtr * ATR
// Close at market after InpMaxHoldBars bars if neither level was touched.
// Apply adverse slippage/spread on entry and exit.

// 5. MONEY MANAGEMENT ($10.000 account example)
double CalculateLotSize(double slDistancePrice)
{
    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (InpRiskPercent / 100.0);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lossPerLot = (slDistancePrice / tickSize) * tickValue;
    if(lossPerLot <= 0.0) return 0.0;
    return NormalizeDouble(riskMoney / lossPerLot, 2);
}
"""

    if strategy == "volume_profile_failed_auction":
        return """//+------------------------------------------------------------------+
//| MQL5 LOGIC BLUEPRINT: VOLUME_PROFILE_FAILED_AUCTION
//| Prior-day value-area failed breakdown, long-only London morning
//+------------------------------------------------------------------+
// 1. INPUT PARAMETER
input double InpRiskPercent      = 1.0;    // Risk % per trade (recommended 1.0; max 1.25)
input double InpRewardRiskRatio  = 0.50;   // Fixed target, fraction of actual risk
input double InpProfileBinSize   = 5.00;   // USD volume-profile row
input double InpValueArea        = 0.80;   // 80% value area
input int    InpSessionStartHour = 9;      // UTC, inclusive
input int    InpSessionEndHour   = 11;     // UTC, inclusive
input int    InpAtrPeriod        = 14;
input double InpSlAtrBuffer      = 0.50;   // SL below rejection low by 0.5 x ATR
input int    InpMaxHoldBars      = 48;     // 4 hours on M5
input double InpHalfSpread       = 0.12;   // Modelled cost per side on XAUUSD
input int    InpMagicNumber      = 888558;

// 2. PRIOR-DAY VOLUME PROFILE (M5, UTC)
// At the start of each new UTC day, build the completed prior trading day's
// profile.  Sunday bars are ignored.  For every M5 bar:
//     typical = (high + low + close) / 3
//     bin     = round(typical / InpProfileBinSize)
//     volume  = bar volume, or 1.0 when volume is missing
// POC = bin with the largest volume.  Sort bins by volume descending and take
// bins until they contain InpValueArea of total volume; VAL/VAH are the lowest
// and highest chosen bins.  Cache the levels for the whole current day.

// 3. ENTRY RULES (evaluated on the closed bar)
// Only 09:00-11:59 UTC.  Long only.  One position at a time.
//   prior_close inside [VAL, VAH]
//   low < VAL
//   close > VAL
//   close > open
//   POC > close
// Enter at the next bar open with adverse half-spread.

// 4. EXIT RULES
// risk = entry - (signal_low - InpSlAtrBuffer * ATR(14))
// TP   = entry + InpRewardRiskRatio * risk
// Close at market after InpMaxHoldBars if neither SL nor TP is touched.
// Same-bar SL and TP: assume SL first (conservative OHLC tie-break).

// 5. MONEY MANAGEMENT ($10.000 account example)
double CalculateLotSize(double slDistancePrice)
{
    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (InpRiskPercent / 100.0);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lossPerLot = (slDistancePrice / tickSize) * tickValue;
    if(lossPerLot <= 0.0) return 0.0;
    return NormalizeDouble(riskMoney / lossPerLot, 2);
}
"""

    if strategy == "variance_ratio_regime":
        return f"""//+------------------------------------------------------------------+
//| MQL5 LOGIC BLUEPRINT: VARIANCE_RATIO_REGIME
//| Statistical return direction gated by persistence regime
//+------------------------------------------------------------------+
// On each closed M5 bar, compute log returns; over 96 bars calculate
// one-bar variance, overlapping 4-bar variance, and the variance ratio:
// VR4 = Var(4-bar returns) / (4 * Var(1-bar returns)). Compute the 12-bar
// cumulative return z-score using the rolling one-bar standard deviation.
// In reversion mode, fade when |z| >= 2.0 and VR4 <= 0.80; in persistence
// mode, follow when |z| >= 2.0 and VR4 >= 1.20.
// Enter at next bar open. SL = 1.0 x ATR(14), target = {params.rr:.2f}R.
// Time stop: 12 bars. Apply adverse 0.12 price-unit entry/exit costs.
// Same-bar SL and TP: resolve as SL (conservative OHLC assumption).
"""

    return f"""//+------------------------------------------------------------------+
//| MQL5 LOGIC BLUEPRINT: {strategy.upper()}
//| Adaptasi Strategi dari Python Backtester ke MetaTrader 5
//+------------------------------------------------------------------+

// 1. INPUT PARAMETER
input double InpRiskPercent      = 1.0;          // Risk % per trade
input double InpRewardRiskRatio  = {params.rr:.2f};        // Target RR ({params.rr}:1)
input int    InpSwingStrength    = {params.swing_strength};            // Swing pivot bars
input double InpMinFVG           = {params.min_fvg_size:.2f};        // Min FVG size
input string InpTrendMethod      = "{params.trend_method}";     // Trend filter (ema / structure)

// 2. ATURAN ENTRY (ON TICK / ON NEW BAR)
bool CheckEntrySignal(ENUM_ORDER_TYPE &orderType, double &slPrice, double &tpPrice)
{{
    // A. Deteksi Swing High / Low sebelumnya menggunakan pivot bar
    // B. Verifikasi apakah ada Liquidity Sweep (Wick melampaui level, candle close di dalam)
    // C. Verifikasi konfirmasi Fair Value Gap (FVG) atau Inbalance 3-bar
    // D. Filter Trend: {params.trend_method.upper()} harus sejalan dengan arah transaksi
    
    // Contoh Kalkulasi SL & TP:
    // double riskDistance = MathAbs(entryPrice - slPrice);
    // tpPrice = entryPrice + (riskDistance * InpRewardRiskRatio); // for Buy
    return false;
}}

// 3. ATURAN MONEY MANAGEMENT ($10.000 Akun Standar)
double CalculateLotSize(double slDistancePoints)
{{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = accountBalance * (InpRiskPercent / 100.0);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotSize = riskMoney / (slDistancePoints * tickValue);
    return NormalizeDouble(lotSize, 2);
}}
"""


def main():
    parser = argparse.ArgumentParser(description="Backtest runner for Electron")
    parser.add_argument("--list-strategies", action="store_true", help="Print available strategies in JSON")
    parser.add_argument("--file", help="Path to CSV candle data")
    parser.add_argument("--aux-file", help="Optional secondary CSV for cross-asset strategies")
    parser.add_argument("--strategy", default="liquidity_imbalance", choices=sorted(REGISTRY.keys()))
    parser.add_argument("--capital", type=float, default=10000.0, help="Initial capital in USD")
    parser.add_argument("--risk-pct", type=float, default=1.0, help="Risk percent per trade")
    parser.add_argument("--rr", type=float, default=2.0, help="Reward-to-Risk ratio")
    parser.add_argument("--timeframe", default="M5", choices=["M1", "M5", "M15", "M30", "H1", "H4"])
    parser.add_argument("--trend", default="ema", choices=["ema", "structure", "none"])
    parser.add_argument("--swing-strength", type=int, default=5)
    parser.add_argument("--min-fvg", type=float, default=0.5)
    parser.add_argument("--sl-buffer", type=float, default=0.0)
    parser.add_argument("--pullback", type=int, default=10)
    parser.add_argument("--close-confirm", action="store_true")
    parser.add_argument("--report-out", default="report.html", help="Path to write HTML report")
    parser.add_argument("--json-out", default="result.json", help="Path to write JSON summary")
    parser.add_argument("--set-out", default="strategy.set", help="Path to write MT5 .set file")

    args = parser.parse_args()

    if args.list_strategies:
        strategies_info = []
        descriptions = {
            "liquidity_imbalance": "Liquidity Sweep + Fair Value Gap (FVG) confirmation",
            "prev_day_breakout": "Previous Day High/Low (PDH/PDL) Breakout & Retest",
            "orb": "Opening Range Breakout (ORB) on session open",
            "ict_fvg": "ICT Fair Value Gap entry with market structure shift",
            "ict_ifvg": "ICT Inversion Fair Value Gap",
            "ict_order_block": "ICT Institutional Order Block mitigation",
            "smart_money": "Smart Money Concepts (SMC) CHoCH & Liquidity Purge",
            "supply_demand": "Institutional Supply & Demand Zones",
            "order_flow": "Order Flow absorption and delta imbalance",
            "rsi_reversal": "RSI extreme exhaustion + Sweep reversal",
            "support_resistance": "Key horizontal Support & Resistance level sweeps",
            "momentum_breakout": "High momentum range expansion",
            "momentum_pullback": "Trend continuation pullback to value area",
            "bollinger_bands": "Bollinger Band outer band sweep & mean reversion",
            "bollinger_bands_2": "Bollinger Bands 2: Trend-aligned outer band sweep with 35% volatility buffer (WR>75%)",
            "session_gap": "London/New York opening session imbalance gap",
            "vwap_bounce": "Institutional Volume-Weighted Average Price bounce",
            "gold_session_sweep": "Previous 24-bar high/low sweep + rejection + later 50% retrace",
            "london_ny_vwap_pullback": "M5 only: London/NY session VWAP reclaim in the EMA-200 direction, fixed 1:1 ATR stop/target, 2-hour time stop; recommended risk 1.0-1.5%",
            "london_sweep_trap": "London Sweep Trap: Institutional London/NY VWAP liquidity trap (WR>75%, DD<3%)",
            "liquidity_bubble_trap": "Liquidity Sweep + Volume Bubble Trap: Institutional absorption & failed auction fading false breakouts (WR 80.8%, DD < 3.8%)",
            "doji_ride": "Doji Ride: Fades structural sweeps at Prior Day & Asian High/Low with Doji absorption wicks and rides immediate momentum breakout (WR 84.0%, DD < 3.0%)",
            "variance_ratio_regime": "Variance-Ratio Regime: statistically classify return persistence, then fade or follow stretched returns",
            "volume_profile_failed_auction": "M5 only: long a failed breakdown below the prior day's 80% volume-area low during 09:00-11:59 UTC, with a 0.5R target and 4-hour time stop; recommended risk 1.0% (1.25% max)",
            "vwap_bounce_2": "VWAP Bounce 2: Trend-aligned VWAP bounce with rejection wick & dynamic R:R"
        }
        # Put newly validated strategies at the top so they are visible without
        # scrolling the long HTML select.  The rest stay alphabetical.
        featured = ["doji_ride", "liquidity_bubble_trap", "volume_profile_failed_auction", "london_sweep_trap"]
        ordered = featured + [n for n in sorted(REGISTRY.keys()) if n not in featured]
        for name in ordered:
            strategies_info.append({
                "id": name,
                "name": name.replace("_", " ").title(),
                "description": descriptions.get(name, "Quantitative trading strategy")
            })
        print(json.dumps(strategies_info))
        return

    if not args.file:
        print("ERROR: --file argument is required when not using --list-strategies", file=sys.stderr)
        sys.exit(1)

    fixed_rr = FIXED_RR.get(args.strategy)
    if fixed_rr is not None:
        if abs(args.rr - fixed_rr) > 1e-9:
            print(f"Note: {args.strategy} uses a fixed {fixed_rr:g}R target; "
                  f"overriding RR={args.rr:g}.")
        args.rr = fixed_rr

    if args.strategy in ("london_ny_vwap_pullback", "volume_profile_failed_auction") and args.timeframe != "M5":
        print(f"WARNING: {args.strategy} was designed and validated on M5; "
              f"results on {args.timeframe} are not reliable.", file=sys.stderr)

    aux_file = args.aux_file
    params = Params(
        timeframe=args.timeframe,
        rr=args.rr,
        trend_method=args.trend if args.trend in ["ema", "structure"] else "ema",
        swing_strength=args.swing_strength,
        min_fvg_size=args.min_fvg,
        sl_buffer=args.sl_buffer,
        pullback_window=args.pullback,
        require_close_confirmation=args.close_confirm,
        aux_file=aux_file,
    )

    if not os.path.exists(args.file):
        print(f"ERROR: Data file not found: {args.file}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading data: {args.file}...")
    run_result = run_file(args.file, params, strategy=args.strategy)

    use_trend = (args.trend != "none")
    print(f"Simulating portfolio on ${args.capital:,.2f} capital with {args.risk_pct}% risk per trade...")
    
    sim_stats = simulate_portfolio(
        setups=run_result.setups,
        candles=run_result.candles,
        initial_balance=args.capital,
        risk_pct=args.risk_pct,
        use_trend_filter=use_trend
    )

    # Write HTML report
    try:
        report_dir = os.path.dirname(args.report_out)
        if report_dir and not os.path.exists(report_dir):
            os.makedirs(report_dir, exist_ok=True)
            
        write_report(
            args.report_out,
            [run_result],
            params,
            agg_on=run_result.stats_on,
            agg_off=run_result.stats_off
        )
        print(f"Report written to: {args.report_out}")
    except Exception as e:
        print(f"Warning: Failed to generate report HTML: {e}", file=sys.stderr)

    # Generate MT5 artifacts
    set_content = generate_mt5_set_file(args.strategy, params, args.risk_pct)
    mql5_blueprint = generate_mql5_blueprint(args.strategy, params)

    try:
        with open(args.set_out, "w", encoding="utf-8") as f:
            f.write(set_content)
        print(f"MT5 .set file written to: {args.set_out}")
    except Exception as e:
        print(f"Warning: Failed to write MT5 .set file: {e}", file=sys.stderr)

    # Full JSON payload
    payload = {
        "success": True,
        "strategy": args.strategy,
        "file": args.file,
        "timeframe": args.timeframe,
        "params": {
            "capital": args.capital,
            "risk_pct": args.risk_pct,
            "rr": args.rr,
            "trend": args.trend,
            "swing_strength": args.swing_strength,
            "min_fvg": args.min_fvg,
            "sl_buffer": args.sl_buffer,
            "pullback": args.pullback,
            "close_confirm": args.close_confirm
        },
        "summary": sim_stats,
        "report_file": os.path.abspath(args.report_out),
        "set_file": os.path.abspath(args.set_out),
        "set_content": set_content,
        "mql5_blueprint": mql5_blueprint
    }

    # Write JSON output
    try:
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        print(f"JSON result written to: {args.json_out}")
    except Exception as e:
        print(f"Error writing JSON: {e}", file=sys.stderr)

    # Output JSON string marker for IPC parsing
    print("__JSON_RESULT_START__")
    print(json.dumps(payload))
    print("__JSON_RESULT_END__")


if __name__ == "__main__":
    main()
