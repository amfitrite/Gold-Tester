"""Read-and-report analysis: run a strategy over a window, score filter variants.

This is the surface the assistant uses to *read* a backtest: it runs detection on
the full series (so context is correct), restricts to the chosen window, then
scores the same setups under several filter combinations and slices them by hour
and direction so it's obvious where the losers come from and which filter removes
them. ``AnalysisResult.text()`` renders a console-friendly summary.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Dict, List, Optional, Tuple

from .params import Params
from .parser import parse_file
from .swings import find_swings
from .strategies import run_strategy, LABELS
from .filters import build_context, keep, ma_ok, rsi_ok, trend_ok
from .report import compute_stats, Stats

# (label, use_trend, use_ma, use_rsi)
DEFAULT_VARIANTS: List[Tuple[str, bool, bool, bool]] = [
    ("none (raw)", False, False, False),
    ("trend", True, False, False),
    ("MA", False, True, False),
    ("RSI", False, False, True),
    ("trend+MA", True, True, False),
    ("trend+RSI", True, False, True),
    ("trend+MA+RSI", True, True, True),
]


@dataclass
class AnalysisResult:
    strategy: str
    timeframe: Optional[str]
    date_from: str
    date_to: str
    params: Params
    n_window: int
    variants: List[dict]                 # one per filter combo (label + stats)
    setups: List[dict]                   # per-setup detail in the window
    by_hour: List[dict]
    by_dir: List[dict]
    best: Optional[dict] = None

    def text(self) -> str:
        lines = []
        lines.append(f"Strategy : {LABELS.get(self.strategy, self.strategy)}")
        lines.append(f"Timeframe: {self.timeframe or '-'}   Window: {self.date_from} -> {self.date_to}")
        lines.append(f"RR       : {self.params.rr:g}   MA: {self.params.ma_kind}{self.params.ma_period}   "
                     f"RSI: {self.params.rsi_period} (long<= {self.params.rsi_long_max:g}, short>= {self.params.rsi_short_min:g})")
        lines.append(f"Setups in window: {self.n_window}")
        lines.append("")
        lines.append(f"{'filter':<14}{'trades':>7}{'W/L':>8}{'win%':>7}{'totalR':>9}{'exp/trade':>11}")
        lines.append("-" * 56)
        for v in self.variants:
            s = v["stats"]
            wl = f"{s['wins']}/{s['losses']}"
            lines.append(f"{v['label']:<14}{s['n_setups']:>7}{wl:>8}"
                         f"{s['win_rate']*100:>6.1f}%{s['total_r']:>+9.2f}{s['expectancy']:>+11.3f}")
        if self.best:
            b = self.best
            resolved = b['stats']['wins'] + b['stats']['losses']
            lines.append("")
            lines.append(f"Best expectancy: {b['label']}  ->  {b['stats']['expectancy']:+.3f}R/trade "
                         f"over {resolved} resolved")
        lines.append("")
        lines.append("By hour (raw, all setups):")
        lines.append(f"{'hour':<7}{'trades':>7}{'W/L':>8}{'win%':>7}{'totalR':>9}")
        for h in self.by_hour:
            wl = f"{h['wins']}/{h['losses']}"
            lines.append(f"{h['key']:<7}{h['n']:>7}{wl:>8}"
                         f"{h['win_rate']*100:>6.1f}%{h['total_r']:>+9.2f}")
        lines.append("")
        lines.append("By direction (raw):")
        for d in self.by_dir:
            lines.append(f"  {d['key']:<6} trades {d['n']:>3}  W/L {d['wins']}/{d['losses']}  "
                         f"win% {d['win_rate']*100:4.1f}  totalR {d['total_r']:+.2f}")
        return "\n".join(lines)


def _stats_dict(setups) -> dict:
    return compute_stats(setups).as_dict()


def _group(setups, keyf) -> List[dict]:
    groups: Dict[str, list] = {}
    for s in setups:
        groups.setdefault(keyf(s), []).append(s)
    out = []
    for k in sorted(groups):
        st = compute_stats(groups[k])
        out.append({"key": k, "n": st.n_setups, "wins": st.wins, "losses": st.losses,
                    "win_rate": st.win_rate, "total_r": st.total_r})
    return out


def analyze(path: str, timeframe: Optional[str] = None, strategy: str = "liquidity_imbalance",
            *, days: Optional[int] = None, date_from: Optional[str] = None,
            date_to: Optional[str] = None, params: Optional[Params] = None,
            overrides: Optional[dict] = None,
            variants=DEFAULT_VARIANTS) -> AnalysisResult:
    pr = parse_file(path)
    candles = pr.candles
    if params is None:
        params = Params.for_timeframe(timeframe, **(overrides or {})) if timeframe \
            else Params(**(overrides or {}))

    all_dates = sorted({c.timestamp.date() for c in candles if c.timestamp})
    if date_to is None and all_dates:
        date_to = str(all_dates[-1])
    if date_from is None and all_dates:
        if days is not None:
            date_from = str(all_dates[-days])
        else:
            date_from = str(all_dates[0])
    df = date.fromisoformat(date_from) if date_from else None
    dt = date.fromisoformat(date_to) if date_to else None

    def in_window(c) -> bool:
        if c.timestamp is None:
            return True
        d = c.timestamp.date()
        return (df is None or d >= df) and (dt is None or d <= dt)

    swings = find_swings(candles, params.swing_strength)
    all_setups = run_strategy(strategy, candles, params)
    window = [s for s in all_setups if in_window(candles[s.entry_index])]
    ctx = build_context(candles, params, swings)

    # filter variants
    variant_rows = []
    for label, ut, um, ur in variants:
        kept = [s for s in window if keep(s, ctx, use_trend=ut, use_ma=um, use_rsi=ur)]
        variant_rows.append({"label": label, "use": [ut, um, ur], "stats": _stats_dict(kept)})
    resolved_variants = [v for v in variant_rows
                         if v["stats"]["wins"] + v["stats"]["losses"] >= 5]
    best = max(resolved_variants, key=lambda v: v["stats"]["expectancy"], default=None)

    # per-setup detail
    detail = []
    for s in window:
        ci = s.entry_index
        detail.append({
            "time": candles[ci].label, "dir": s.direction,
            "entry": round(s.entry_price, 2), "sl": round(s.stop_loss, 2),
            "tp": round(s.take_profit, 2), "verdict": s.verdict,
            "r": round(s.r_multiple, 2),
            "rsi": (round(ctx.rsi[ci], 1) if ctx.rsi[ci] is not None else None),
            "ma": (round(ctx.ma[ci], 2) if ctx.ma[ci] is not None else None),
            "close": round(ctx.closes[ci], 2),
            "trend_bias": ctx.bias[ci],
            "trend_ok": trend_ok(s, ctx), "ma_ok": ma_ok(s, ctx), "rsi_ok": rsi_ok(s, ctx),
            "note": s.note,
        })

    return AnalysisResult(
        strategy=strategy, timeframe=timeframe, date_from=date_from, date_to=date_to,
        params=params, n_window=len(window), variants=variant_rows, setups=detail,
        by_hour=_group(window, lambda s: candles[s.entry_index].label[11:13] + ":00"),
        by_dir=_group(window, lambda s: s.direction), best=best,
    )
