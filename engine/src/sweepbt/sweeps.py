"""Liquidity-sweep detection.

A sweep wicks BEYOND a prior swing level but CLOSES BACK on the original side:

  * sell-side sweep (swing high, level L): ``high > L`` AND ``close < L``
  * buy-side  sweep (swing low,  level L): ``low  < L`` AND ``close > L``

A candle that merely *closes* beyond the level is a break, not a sweep, and is
ignored. Only the first sweep of each level is taken.
"""
from __future__ import annotations

from typing import List

from .models import Candle, Sweep, Swing


def find_sweeps(candles: List[Candle], swings: List[Swing]) -> List[Sweep]:
    sweeps: List[Sweep] = []
    for sw in swings:
        level = sw.price
        for k in range(sw.index + 1, len(candles)):
            c = candles[k]
            if sw.kind == "high":
                if c.high > level and c.close < level:
                    sweeps.append(Sweep(index=k, level=level, swing_index=sw.index,
                                        side="sell", wick=c.high))
                    break
                if c.close > level:  # broke and held above -> level consumed, stop looking
                    break
            else:  # swing low
                if c.low < level and c.close > level:
                    sweeps.append(Sweep(index=k, level=level, swing_index=sw.index,
                                        side="buy", wick=c.low))
                    break
                if c.close < level:  # broke below -> consumed
                    break
    sweeps.sort(key=lambda s: s.index)
    return sweeps
