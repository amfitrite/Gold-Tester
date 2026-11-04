"""Momentum breakout.

The first candle to CLOSE beyond the highest high / lowest low of the prior
``lookback`` candles, on an expansion candle (range >= average of the lookback),
breaks out: close above -> long, close below -> short. The expansion filter is
what makes it a *momentum* breakout rather than a drift through the level. Stop
sits at the breakout candle's opposite extreme; one breakout attempt per side
while the level holds.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def run(candles: List[Candle], params: Params) -> List[Setup]:
    lookback = max(5, params.ema_fast)
    setups: List[Setup] = []
    cooldown = 0
    for i in range(lookback, len(candles)):
        if cooldown > 0:
            cooldown -= 1
            continue
        window = candles[i - lookback:i]
        hh = max(c.high for c in window)
        ll = min(c.low for c in window)
        avg_range = sum(c.high - c.low for c in window) / lookback
        c = candles[i]
        rng = c.high - c.low
        if rng < avg_range:
            continue
        if c.close > hh:
            sl = c.low - params.sl_buffer
            s = simulate_setup(candles, "long", i, c.close, sl,
                               c.close + (c.close - sl) * params.rr, params,
                               strategy="momentum_breakout", trigger_index=i,
                               trigger_level=round(hh, 5),
                               note=f"close>{hh:.2f} ({lookback}-bar high)", resolve_from=i + 1)
            if s:
                setups.append(s)
                cooldown = lookback
        elif c.close < ll:
            sl = c.high + params.sl_buffer
            s = simulate_setup(candles, "short", i, c.close, sl,
                               c.close - (sl - c.close) * params.rr, params,
                               strategy="momentum_breakout", trigger_index=i,
                               trigger_level=round(ll, 5),
                               note=f"close<{ll:.2f} ({lookback}-bar low)", resolve_from=i + 1)
            if s:
                setups.append(s)
                cooldown = lookback
    return setups
