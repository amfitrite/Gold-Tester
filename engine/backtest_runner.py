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
    lines = [
        "; ===========================================================",
        f"; MT5 EA Configuration: {strategy.upper()} Strategy",
        f"; Generated on: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "; ===========================================================",
        f"InpStrategyName={strategy}",
        f"InpRiskPercent={risk_pct:.2f}",
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
    ]
    return "\n".join(lines)


def generate_mql5_blueprint(strategy: str, params: Params) -> str:
    """Generate structured MQL5 code logic blueprint for MT5."""
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
            "session_gap": "London/New York opening session imbalance gap",
            "vwap_bounce": "Institutional Volume-Weighted Average Price bounce"
        }
        for name in sorted(REGISTRY.keys()):
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
    params = Params(
        timeframe=args.timeframe,
        rr=args.rr,
        trend_method=args.trend if args.trend in ["ema", "structure"] else "ema",
        swing_strength=args.swing_strength,
        min_fvg_size=args.min_fvg,
        sl_buffer=args.sl_buffer,
        pullback_window=args.pullback,
        require_close_confirmation=args.close_confirm
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
            "close_confirm": args.close_confirm
        },
        "summary": sim_stats,
        "report_file": os.path.abspath(args.report_out),
        "set_file": os.path.abspath(args.set_out),
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
