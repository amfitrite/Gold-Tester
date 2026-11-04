"""Composable entry filters: trend, MA, RSI.

Each filter is a causal gate evaluated at a setup's entry candle. They compose
with AND — a setup is kept only if every *enabled* filter keeps it. Nothing here
mutates setups; callers ask ``keep()`` per setup so multiple filter combinations
can be scored over the same setup list (used by the analyzer and the lab).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

from .models import Candle, Direction, Setup, Swing
from .params import Params
from .trend import compute_bias
from .indicators import moving_average, rsi as rsi_series


@dataclass
class FilterContext:
    bias: List[Optional[Direction]]
    ma: List[Optional[float]]
    rsi: List[Optional[float]]
    closes: List[float]
    params: Params


def build_context(candles: List[Candle], params: Params,
                  swings: Optional[List[Swing]] = None) -> FilterContext:
    closes = [c.close for c in candles]
    return FilterContext(
        bias=compute_bias(candles, params, swings),
        ma=moving_average(closes, params.ma_period, params.ma_kind),
        rsi=rsi_series(closes, params.rsi_period),
        closes=closes, params=params,
    )


def trend_ok(s: Setup, ctx: FilterContext) -> bool:
    return ctx.bias[s.entry_index] == s.direction


def ma_ok(s: Setup, ctx: FilterContext) -> Optional[bool]:
    m = ctx.ma[s.entry_index]
    if m is None:
        return None          # not enough data -> treated as "no opinion"
    close = ctx.closes[s.entry_index]
    return close > m if s.direction == "long" else close < m


def rsi_ok(s: Setup, ctx: FilterContext) -> Optional[bool]:
    r = ctx.rsi[s.entry_index]
    if r is None:
        return None
    if s.direction == "long":
        return r <= ctx.params.rsi_long_max      # don't buy overbought
    return r >= ctx.params.rsi_short_min         # don't sell oversold


def keep(s: Setup, ctx: FilterContext, *, use_trend: bool, use_ma: bool,
         use_rsi: bool) -> bool:
    """True if the setup survives every *enabled* filter (None == no opinion == pass)."""
    if use_trend and not trend_ok(s, ctx):
        return False
    if use_ma and ma_ok(s, ctx) is False:
        return False
    if use_rsi and rsi_ok(s, ctx) is False:
        return False
    return True
