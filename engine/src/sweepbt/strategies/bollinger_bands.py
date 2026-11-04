"""Bollinger Bands mean reversion: trade price returning to the middle band.

When price touches the upper band (overbought), go short expecting a bounce to
the middle band (MA). When price touches the lower band (oversold), go long
expecting a bounce to the middle band. Bands are based on MA ± (2 * StdDev).
Entry is at the band touch; stop is 1 band-width beyond the extreme.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..indicators import sma
from ..simulate import simulate_setup


def _bollinger_bands(closes: List[float], period: int, std_devs: float = 2.0):
    """Calculate Bollinger Bands: (upper_band, middle_band, lower_band) for each candle."""
    if len(closes) < period:
        return [(None, None, None)] * len(closes)

    bands = []
    for i in range(len(closes)):
        if i < period - 1:
            bands.append((None, None, None))
        else:
            window = closes[i - period + 1:i + 1]
            mid = sum(window) / period
            variance = sum((x - mid) ** 2 for x in window) / period
            std = variance ** 0.5
            upper = mid + std_devs * std
            lower = mid - std_devs * std
            bands.append((upper, mid, lower))
    return bands


def run(candles: List[Candle], params: Params) -> List[Setup]:
    closes = [c.close for c in candles]
    period = 20  # Standard Bollinger Bands period
    bands = _bollinger_bands(closes, period)

    setups: List[Setup] = []
    for i in range(1, len(candles)):
        upper, mid, lower = bands[i]
        if upper is None or mid is None or lower is None:
            continue

        c = candles[i]
        prev_c = candles[i - 1]
        band_width = upper - lower

        # Long: price touches lower band, expecting bounce to middle
        if c.low <= lower and prev_c.low > lower:
            sl = lower - band_width * 0.3  # Stop 30% of band-width below lower band
            target = mid + (mid - lower)   # Distance to middle plus equal distance for profit
            s = simulate_setup(candles, "long", i, c.close, sl, target, params,
                             strategy="bollinger_bands",
                             trigger_index=i,
                             trigger_level=round(lower, 5),
                             note=f"BB touch lower {lower:.2f}",
                             resolve_from=i + 1)
            if s:
                setups.append(s)

        # Short: price touches upper band, expecting bounce to middle
        if c.high >= upper and prev_c.high < upper:
            sl = upper + band_width * 0.3  # Stop 30% of band-width above upper band
            target = mid - (upper - mid)   # Distance to middle minus equal distance for profit
            s = simulate_setup(candles, "short", i, c.close, sl, target, params,
                             strategy="bollinger_bands",
                             trigger_index=i,
                             trigger_level=round(upper, 5),
                             note=f"BB touch upper {upper:.2f}",
                             resolve_from=i + 1)
            if s:
                setups.append(s)

    return setups
