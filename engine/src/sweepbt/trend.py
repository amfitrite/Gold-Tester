"""Trend / bias filters and entry guardrails.

The headline knob is the trend filter: only take setups aligned with the
prevailing bias. Two methods are offered:

  * ``ema``       — 20/50 EMA: longs only when price > slow EMA and the fast EMA
                    is rising; shorts only when price < slow EMA and fast falling.
  * ``structure`` — higher-high/higher-low vs lower-high/lower-low read off the
                    detected swing points.

Filtering is non-destructive: every setup is tagged ``filter_kept`` + reason so
the report can show filter-ON vs filter-OFF side by side.
"""
from __future__ import annotations

from typing import List, Optional

from .models import Candle, Direction, Setup, Swing
from .params import Params


def ema(values: List[float], period: int) -> List[float]:
    if not values:
        return []
    k = 2.0 / (period + 1.0)
    out = [values[0]]
    for v in values[1:]:
        out.append(v * k + out[-1] * (1.0 - k))
    return out


def ema_bias(candles: List[Candle], fast: int, slow: int) -> List[Optional[Direction]]:
    closes = [c.close for c in candles]
    ef, es = ema(closes, fast), ema(closes, slow)
    bias: List[Optional[Direction]] = []
    for i in range(len(candles)):
        rising = i > 0 and ef[i] > ef[i - 1]
        falling = i > 0 and ef[i] < ef[i - 1]
        if closes[i] > es[i] and rising:
            bias.append("long")
        elif closes[i] < es[i] and falling:
            bias.append("short")
        else:
            bias.append(None)
    return bias


def structure_bias(candles: List[Candle], swings: List[Swing]) -> List[Optional[Direction]]:
    """Carry-forward bias from the last two swing highs and two swing lows."""
    highs = [s for s in swings if s.kind == "high"]
    lows = [s for s in swings if s.kind == "low"]
    bias = [None] * len(candles)

    def latest_two(seq, idx):
        prior = [s for s in seq if s.index <= idx]
        return prior[-2:] if len(prior) >= 2 else None

    current: Optional[Direction] = None
    for i in range(len(candles)):
        hh = latest_two(highs, i)
        ll = latest_two(lows, i)
        if hh and ll:
            higher_high = hh[1].price > hh[0].price
            higher_low = ll[1].price > ll[0].price
            lower_high = hh[1].price < hh[0].price
            lower_low = ll[1].price < ll[0].price
            if higher_high and higher_low:
                current = "long"
            elif lower_high and lower_low:
                current = "short"
        bias[i] = current
    return bias


def compute_bias(candles: List[Candle], params: Params,
                 swings: Optional[List[Swing]] = None) -> List[Optional[Direction]]:
    if params.trend_method == "structure":
        return structure_bias(candles, swings or [])
    return ema_bias(candles, params.ema_fast, params.ema_slow)


def apply_trend_filter(setups: List[Setup], candles: List[Candle], params: Params,
                       swings: Optional[List[Swing]] = None) -> List[Setup]:
    """Tag each setup with whether the trend filter keeps it. Mutates in place."""
    bias = compute_bias(candles, params, swings)
    for s in setups:
        b = bias[s.entry_index]
        if b == s.direction:
            s.filter_kept = True
            s.filter_reason = f"aligned ({params.trend_method} bias={b})"
        else:
            s.filter_kept = False
            s.filter_reason = f"counter-trend ({params.trend_method} bias={b or 'none'})"
    return setups
