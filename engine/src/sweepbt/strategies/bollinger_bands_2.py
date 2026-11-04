"""Bollinger Bands 2 (Optimized Mean Reversion):
High-winrate outer band rejection with built-in EMA 20/50 trend confluence and dynamic stop buffer.

Key Enhancements over v1:
1. Built-in EMA Trend Bias:
   - Longs only when price > EMA(50) and fast EMA(20) is rising (buying value pullbacks in an uptrend).
   - Shorts only when price < EMA(50) and fast EMA(20) is falling (selling value rallies in a downtrend).
2. Volatility Stop Buffer:
   - Sets stop loss at 35% of the total band width beyond the outer band, giving market room to breathe
     and avoiding stop-hunting spikes on Gold (XAUUSD).
3. Target:
   - Projects mean reversion beyond the middle band to lock in asymmetric 2.0+ Reward-to-Risk.
4. Preserved as a standalone strategy so users can compare v1 vs v2 side-by-side.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def _calculate_bollinger_bands(closes: List[float], period: int = 16, std_devs: float = 2.0):
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


def _calculate_ema(series: List[float], period: int) -> List[float]:
    ema = [None] * len(series)
    if len(series) < period:
        return ema
    k = 2.0 / (period + 1.0)
    sma_val = sum(series[:period]) / period
    ema[period - 1] = sma_val
    for i in range(period, len(series)):
        ema[i] = (series[i] - ema[i - 1]) * k + ema[i - 1]
    return ema


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if not candles or len(candles) < 55:
        return []

    closes = [c.close for c in candles]
    period = 16  # Tuned for high winrate on XAUUSD
    std_devs = 2.0
    sl_mult = 0.35

    bands = _calculate_bollinger_bands(closes, period, std_devs)
    ema20 = _calculate_ema(closes, 20)
    ema50 = _calculate_ema(closes, 50)

    setups: List[Setup] = []

    for i in range(50, len(candles)):
        upper, mid, lower = bands[i]
        if upper is None or mid is None or lower is None:
            continue

        c = candles[i]
        prev_c = candles[i - 1]
        band_width = upper - lower
        if band_width <= 0.05:
            continue

        e20_now = ema20[i]
        e20_prev = ema20[i - 1]
        e50_now = ema50[i]

        if e20_now is None or e20_prev is None or e50_now is None:
            continue

        rising_fast = e20_now > e20_prev
        falling_fast = e20_now < e20_prev

        # Long Setup: Touch/pierce lower band while bullish trend structure is active
        bias_long = (c.close > e50_now) and rising_fast
        if c.low <= lower and prev_c.low > lower and bias_long:
            sl = lower - band_width * sl_mult
            risk = c.close - sl
            if risk > 0.05:
                target = mid + (mid - lower)
                s = simulate_setup(
                    candles, "long", i, c.close, sl, target, params,
                    strategy="bollinger_bands_2",
                    trigger_index=i,
                    trigger_level=round(lower, 3),
                    note=f"BB2 Long Reversal @ {c.close:.2f} (Band={lower:.2f})",
                    resolve_from=i + 1
                )
                if s:
                    setups.append(s)

        # Short Setup: Touch/pierce upper band while bearish trend structure is active
        bias_short = (c.close < e50_now) and falling_fast
        if c.high >= upper and prev_c.high < upper and bias_short:
            sl = upper + band_width * sl_mult
            risk = sl - c.close
            if risk > 0.05:
                target = mid - (upper - mid)
                s = simulate_setup(
                    candles, "short", i, c.close, sl, target, params,
                    strategy="bollinger_bands_2",
                    trigger_index=i,
                    trigger_level=round(upper, 3),
                    note=f"BB2 Short Reversal @ {c.close:.2f} (Band={upper:.2f})",
                    resolve_from=i + 1
                )
                if s:
                    setups.append(s)

    return setups
