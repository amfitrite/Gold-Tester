"""End-to-end pipeline: parse -> detect -> simulate -> filter -> stats."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from .models import Candle, Swing, Sweep, Zone, Setup
from .params import Params
from .parser import parse_file, ParseResult, BadRow
from .swings import find_swings
from .sweeps import find_sweeps
from .imbalance import find_fvgs
from .strategies import run_strategy
from .trend import apply_trend_filter
from .report import Stats, stats_filtered


@dataclass
class RunResult:
    name: str
    candles: List[Candle]
    swings: List[Swing]
    sweeps: List[Sweep]
    fvgs: List[Tuple[Zone, str]]
    setups: List[Setup]
    stats_off: Stats          # all setups (filter OFF)
    stats_on: Stats           # trend-filter-kept setups only
    bad_rows: List[BadRow] = field(default_factory=list)
    params: Optional[Params] = None
    strategy: str = "liquidity_imbalance"


def run(candles: List[Candle], params: Params, name: str = "series",
        bad_rows: Optional[List[BadRow]] = None,
        strategy: str = "liquidity_imbalance") -> RunResult:
    swings = find_swings(candles, params.swing_strength)
    sweeps = find_sweeps(candles, swings)
    fvgs = find_fvgs(candles, params.min_fvg_size)
    setups = run_strategy(strategy, candles, params)
    apply_trend_filter(setups, candles, params, swings)
    return RunResult(
        name=name, candles=candles, swings=swings, sweeps=sweeps, fvgs=fvgs,
        setups=setups,
        stats_off=stats_filtered(setups, kept_only=False),
        stats_on=stats_filtered(setups, kept_only=True),
        bad_rows=bad_rows or [], params=params, strategy=strategy,
    )


def run_file(path: str, params: Params,
             strategy: str = "liquidity_imbalance") -> RunResult:
    pr: ParseResult = parse_file(path)
    import os
    name = os.path.splitext(os.path.basename(path))[0]
    return run(pr.candles, params, name=name, bad_rows=pr.bad_rows, strategy=strategy)


@dataclass
class BatchResult:
    runs: List[RunResult]
    agg_off: Stats
    agg_on: Stats


def run_batch(paths: List[str], params: Params,
              strategy: str = "liquidity_imbalance") -> BatchResult:
    from .report import compute_stats
    runs = [run_file(p, params, strategy=strategy) for p in paths]
    all_setups = [s for r in runs for s in r.setups]
    agg_off = compute_stats(all_setups)
    agg_on = compute_stats([s for s in all_setups if s.filter_kept])
    return BatchResult(runs=runs, agg_off=agg_off, agg_on=agg_on)
