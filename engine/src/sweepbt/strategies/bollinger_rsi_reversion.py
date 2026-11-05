"""Bollinger Bands + RSI Mean Reversion Strategy.

This strategy combines Bollinger Bands with RSI for mean reversion trades,
which often claims a high win rate in ranging markets.

Rules:
1. Long when price touches the lower Bollinger Band AND RSI is oversold (< 30).
2. Short when price touches the upper Bollinger Band AND RSI is overbought (> 70).
3. Exit at the middle Bollinger Band (Moving Average).
"""
from __future__ import annotations

from typing import List, Optional

from ..models import Candle, Setup
from ..params import Params
from ..indicators import sma, rsi
from ..simulate import simulate_setup

def _bollinger_bands(closes: List[float], period: int, std_devs: float = 2.0):
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
    bb_period = 20
    rsi_period = 14

    bands = _bollinger_bands(closes, bb_period)
    rsi_vals = rsi(closes, rsi_period)

    setups: List[Setup] = []
    busy_until = -1

    for i in range(max(bb_period, rsi_period), len(candles) - 1):
        if i < busy_until:
            continue

        upper, mid, lower = bands[i]
        r = rsi_vals[i]

        if upper is None or mid is None or lower is None or r is None:
            continue

        c = candles[i]
        band_width = upper - lower

        # Long: touches lower band & RSI oversold
        if c.low <= lower and r < 30:
            sl = lower - band_width * 0.5
            target = mid

            # Ensure proper R:R logic
            if target <= c.close or sl >= c.close:
                continue

            s = simulate_setup(candles, "long", i+1, candles[i+1].open, sl, target, params,
                             strategy="bollinger_rsi_reversion",
                             trigger_index=i,
                             trigger_level=round(lower, 5),
                             note=f"BB Lower + RSI {r:.1f}",
                             resolve_from=i + 1)
            if s:
                setups.append(s)
                busy_until = s.exit_index if s.exit_index else i+1

        # Short: touches upper band & RSI overbought
        elif c.high >= upper and r > 70:
            sl = upper + band_width * 0.5
            target = mid

            if target >= c.close or sl <= c.close:
                continue

            s = simulate_setup(candles, "short", i+1, candles[i+1].open, sl, target, params,
                             strategy="bollinger_rsi_reversion",
                             trigger_index=i,
                             trigger_level=round(upper, 5),
                             note=f"BB Upper + RSI {r:.1f}",
                             resolve_from=i + 1)
            if s:
                setups.append(s)
                busy_until = s.exit_index if s.exit_index else i+1

    return setups
