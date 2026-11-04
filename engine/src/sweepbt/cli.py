"""Command-line entry point.

Examples:
  python -m sweepbt.cli data/xauusd_m15_2026-05-27.csv
  python -m sweepbt.cli data/*.csv --timeframe M15 --out report.html
  python -m sweepbt.cli data/day.csv --rr 3 --swing-strength 4 --trend structure
  python -m sweepbt.cli data/day.csv --close-confirm --max-risk 8
"""
from __future__ import annotations

import argparse
import glob
import sys
from typing import List

from .params import Params
from .engine import run_batch
from .chart import write_report
from .strategies import REGISTRY


def _expand(globs: List[str]) -> List[str]:
    paths: List[str] = []
    for g in globs:
        hit = glob.glob(g)
        paths.extend(hit if hit else [g])
    return sorted(dict.fromkeys(paths))


def parse_rr(text: str) -> float:
    """Accept '2', '2.5', or ratio forms '1:2' / '3:1' -> reward/risk multiple."""
    text = text.strip()
    if ":" in text:
        risk_s, reward_s = text.split(":", 1)
        risk, reward = float(risk_s), float(reward_s)
        if risk <= 0:
            raise ValueError(f"risk side of RR must be > 0: {text!r}")
        return reward / risk
    return float(text)


def build_params(args) -> Params:
    p = Params.for_timeframe(args.timeframe) if args.timeframe else Params()
    if args.swing_strength is not None: p.swing_strength = args.swing_strength
    if args.min_fvg is not None: p.min_fvg_size = args.min_fvg
    if args.rr is not None: p.rr = parse_rr(args.rr)
    if args.sl_buffer is not None: p.sl_buffer = args.sl_buffer
    if args.pullback is not None: p.pullback_window = args.pullback
    if args.orb_window is not None: p.orb_window = args.orb_window
    if args.max_risk is not None: p.max_risk = args.max_risk
    p.trend_method = args.trend
    p.require_close_confirmation = args.close_confirm
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description="Liquidity-sweep + imbalance backtester for gold (MT5).")
    ap.add_argument("files", nargs="+", help="MT5 csv export(s); globs allowed")
    ap.add_argument("--timeframe", choices=["M1", "M5", "M15", "M30", "H1", "H4"],
                    help="preset defaults")
    ap.add_argument("--strategy", choices=sorted(REGISTRY), default="liquidity_imbalance",
                    help="which strategy to backtest")
    ap.add_argument("--swing-strength", type=int)
    ap.add_argument("--min-fvg", type=float, dest="min_fvg")
    ap.add_argument("--rr", help="reward:risk, e.g. 2, 2.5, '1:2', '3:1'")
    ap.add_argument("--sl-buffer", type=float, dest="sl_buffer")
    ap.add_argument("--pullback", type=int, help="pullback window in candles")
    ap.add_argument("--orb-window", type=int, dest="orb_window",
                    help="candles forming the opening range (ORB strategy)")
    ap.add_argument("--trend", choices=["ema", "structure"], default="ema")
    ap.add_argument("--close-confirm", action="store_true",
                    help="require a close back through the zone, not just a wick")
    ap.add_argument("--max-risk", type=float, help="reject setups whose risk exceeds this")
    ap.add_argument("--out", default="report.html")
    args = ap.parse_args(argv)

    params = build_params(args)
    paths = _expand(args.files)
    if not paths:
        print("no input files matched", file=sys.stderr)
        return 2

    batch = run_batch(paths, params, strategy=args.strategy)
    write_report(args.out, batch.runs, params, agg_on=batch.agg_on, agg_off=batch.agg_off)

    # console summary
    print(f"Parsed {len(batch.runs)} file(s). Strategy: {args.strategy}  "
          f"RR: {params.rr:g}  Trend filter method: {params.trend_method}")
    for r in batch.runs:
        if r.bad_rows:
            print(f"  [{r.name}] {len(r.bad_rows)} bad row(s) skipped")
    def line(tag, s):
        return (f"  {tag:<4} setups={s.n_setups:<3} W/L={s.wins}/{s.losses} "
                f"unresolved={s.unresolved} win%={s.win_rate*100:5.1f} "
                f"totalR={s.total_r:+.2f} exp={s.expectancy:+.2f}R")
    print("AGGREGATE (all files):")
    print(line("OFF", batch.agg_off))
    print(line("ON", batch.agg_on))
    print(f"Report written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
