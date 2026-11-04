"""Plain indicator series used by the optional MA / RSI entry filters.

Causal by construction: each value at index ``i`` uses only candles ``<= i``, so
filtering a setup on the indicator value at its entry candle never peeks ahead.
"""
from __future__ import annotations

from typing import List, Optional

from .trend import ema  # reuse the EMA already defined for the trend filter


def sma(values: List[float], period: int) -> List[Optional[float]]:
    out: List[Optional[float]] = [None] * len(values)
    run = 0.0
    for i, v in enumerate(values):
        run += v
        if i >= period:
            run -= values[i - period]
        if i >= period - 1:
            out[i] = run / period
    return out


def moving_average(values: List[float], period: int, kind: str = "ema"):
    if kind == "sma":
        return sma(values, period)
    e = ema(values, period)            # EMA is defined from the first bar
    # Blank out the warm-up region so it behaves like SMA for filtering.
    return [v if i >= period - 1 else None for i, v in enumerate(e)]


def rsi(closes: List[float], period: int = 14) -> List[Optional[float]]:
    """Wilder's RSI. Returns ``None`` until enough bars exist."""
    n = len(closes)
    out: List[Optional[float]] = [None] * n
    if n <= period:
        return out
    gains = losses = 0.0
    for i in range(1, period + 1):
        d = closes[i] - closes[i - 1]
        gains += max(d, 0.0)
        losses += max(-d, 0.0)
    avg_gain, avg_loss = gains / period, losses / period
    out[period] = 100.0 if avg_loss == 0 else 100.0 - 100.0 / (1.0 + avg_gain / avg_loss)
    for i in range(period + 1, n):
        d = closes[i] - closes[i - 1]
        avg_gain = (avg_gain * (period - 1) + max(d, 0.0)) / period
        avg_loss = (avg_loss * (period - 1) + max(-d, 0.0)) / period
        out[i] = 100.0 if avg_loss == 0 else 100.0 - 100.0 / (1.0 + avg_gain / avg_loss)
    return out
