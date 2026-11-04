"""Swing-point (resting liquidity) detection."""
from __future__ import annotations

from typing import List

from .models import Candle, Swing


def find_swings(candles: List[Candle], strength: int = 3) -> List[Swing]:
    """Return swing highs and lows.

    A candle ``i`` is a swing high if ``high[i]`` is strictly greater than the
    high of every one of the ``strength`` candles on BOTH sides. Swing lows
    mirror this with strictly-less-than lows. Endpoints that lack ``strength``
    neighbours on a side cannot be swings.
    """
    if strength < 1:
        raise ValueError("strength must be >= 1")

    swings: List[Swing] = []
    n = len(candles)
    for i in range(strength, n - strength):
        hi = candles[i].high
        lo = candles[i].low
        is_high = all(candles[j].high < hi for j in range(i - strength, i + strength + 1) if j != i)
        if is_high:
            swings.append(Swing(index=i, price=hi, kind="high"))
            continue  # a single candle won't be both a strict high and low
        is_low = all(candles[j].low > lo for j in range(i - strength, i + strength + 1) if j != i)
        if is_low:
            swings.append(Swing(index=i, price=lo, kind="low"))
    return swings
