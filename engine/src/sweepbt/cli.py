"""Command-line entry point for the Gold Strategy Lab backtest engine."""
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
    mapping = {
        "swing_strength": args.swing_strength, "min_fvg_size": args.min_fvg,
        "rr": parse_rr(args.rr) if args.rr is not None else None,
        "sl_buffer": args.sl_buffer, "pullback_window": args.pullback,
        "orb_window": args.orb_window, "max_risk": args.max_risk,
        "ase_donchian_period": args.ase_donchian,
        "ase_atr_period": args.ase_atr_period,
        "ase_atr_baseline_period": args.ase_atr_baseline,
        "ase_atr_min_ratio": args.ase_atr_min,
        "ase_atr_max_ratio": args.ase_atr_max,
        "ase_min_channel_width_atr": args.ase_min_channel_atr,
        "ase_regime_slope_bars": args.ase_slope_bars,
        "ase_trend_slope_atr": args.ase_trend_slope,
        "ase_min_body_efficiency": args.ase_body_efficiency,
        "ase_rejection_tolerance_atr": args.ase_rejection_tolerance,
        "ase_sl_buffer_atr": args.ase_sl_buffer_atr,
        "ase_value_area_period": args.ase_value_area_period,
        "ase_value_area_fraction": args.ase_value_area_fraction,
        "ase_profile_bin_size": args.ase_profile_bin_size,
        "ase_min_target_rr": args.ase_min_target_rr,
        "ase_target_rr_max": args.ase_target_rr_max,
    }
    for key, value in mapping.items():
        if value is not None:
            setattr(p, key, value)
    p.trend_method = args.trend
    p.require_close_confirmation = args.close_confirm
    return p


def main(argv=None):
    ap = argparse.ArgumentParser(description="Gold Strategy Lab backtester (MT5 OHLCV).")
    ap.add_argument("files", nargs="+", help="MT5 CSV export(s); globs allowed")
    ap.add_argument("--timeframe", choices=["M1", "M5", "M15", "M30", "H1", "H4"])
    ap.add_argument("--strategy", choices=sorted(REGISTRY), default="liquidity_imbalance")
    ap.add_argument("--swing-strength", type=int)
    ap.add_argument("--min-fvg", type=float, dest="min_fvg")
    ap.add_argument("--rr", help="reward:risk, e.g. 2, 2.5, '1:2', '3:1'")
    ap.add_argument("--sl-buffer", type=float, dest="sl_buffer")
    ap.add_argument("--pullback", type=int)
    ap.add_argument("--orb-window", type=int, dest="orb_window")
    ap.add_argument("--trend", choices=["ema", "structure"], default="ema")
    ap.add_argument("--close-confirm", action="store_true")
    ap.add_argument("--max-risk", type=float)

    # ASE controls; omitted values use the timeframe preset.
    ap.add_argument("--ase-donchian", type=int)
    ap.add_argument("--ase-atr-period", type=int)
    ap.add_argument("--ase-atr-baseline", type=int)
    ap.add_argument("--ase-atr-min", type=float)
    ap.add_argument("--ase-atr-max", type=float)
    ap.add_argument("--ase-min-channel-atr", type=float, dest="ase_min_channel_atr")
    ap.add_argument("--ase-slope-bars", type=int)
    ap.add_argument("--ase-trend-slope", type=float)
    ap.add_argument("--ase-body-efficiency", type=float)
    ap.add_argument("--ase-rejection-tolerance", type=float)
    ap.add_argument("--ase-sl-buffer-atr", type=float)
    ap.add_argument("--ase-value-area-period", type=int)
    ap.add_argument("--ase-value-area-fraction", type=float)
    ap.add_argument("--ase-profile-bin-size", type=float)
    ap.add_argument("--ase-min-target-rr", type=float)
    ap.add_argument("--ase-target-rr-max", type=float)

    ap.add_argument("--out", default="report.html")
    args = ap.parse_args(argv)

    params = build_params(args)
    paths = _expand(args.files)
    if not paths:
        print("no input files matched", file=sys.stderr)
        return 2

    batch = run_batch(paths, params, strategy=args.strategy)
    write_report(args.out, batch.runs, params, agg_on=batch.agg_on, agg_off=batch.agg_off)

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
