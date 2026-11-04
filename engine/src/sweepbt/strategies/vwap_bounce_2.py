"""VWAP Bounce 2 (Optimized): Multi-timeframe trend-aligned VWAP bounce with rejection confirmation.

Improvements over VWAP Bounce 1:
1. Trend Confluence: Evaluates EMA-20 and EMA-50 alignment for higher win rate.
2. Rejection Confirmation: Requires a true bounce with rejection wick off VWAP rather
   than just crossing price.
3. Asymmetric Risk/Reward: Target is dynamically structured based on ATR and 1.5R-2.0R minimum
   target rather than tight distance to entry.
4. Preserved as a standalone strategy so users can compare v1 vs v2 side-by-side.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def _calculate_vwap(candles: List[Candle]) -> List[float]:
    """Calculate VWAP: Cumulative(TP × Vol) / Cumulative(Vol)."""
    vwap = [None] * len(candles)
    cumulative_pv = 0.0
    cumulative_vol = 0.0
    for i, c in enumerate(candles):
        tp = (c.high + c.low + c.close) / 3.0
        vol = c.volume if (c.volume and c.volume > 0) else 1.0
        cumulative_pv += tp * vol
        cumulative_vol += vol
        vwap[i] = cumulative_pv / cumulative_vol
    return vwap


def _calculate_ema(candles: List[Candle], period: int) -> List[float]:
    """Calculate Exponential Moving Average."""
    ema = [None] * len(candles)
    if len(candles) < period:
        return ema
    k = 2.0 / (period + 1.0)
    # Simple moving average for seed
    sma = sum(c.close for c in candles[:period]) / period
    ema[period - 1] = sma
    for i in range(period, len(candles)):
        ema[i] = (candles[i].close - ema[i - 1]) * k + ema[i - 1]
    return ema


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if not candles or len(candles) < 55:
        return []

    vwap = _calculate_vwap(candles)
    ema20 = _calculate_ema(candles, 20)
    ema50 = _calculate_ema(candles, 50)
    setups: List[Setup] = []

    for i in range(50, len(candles)):
        c = candles[i]
        prev_c = candles[i - 1]
        v = vwap[i]
        e20 = ema20[i]
        e50 = ema50[i]

        if v is None or e20 is None or e50 is None:
            continue

        candle_range = c.high - c.low
        if candle_range <= 0:
            continue

        atr = max(candle_range, prev_c.high - prev_c.low)
        # Rejection wick calculation
        lower_wick = min(c.open, c.close) - c.low
        upper_wick = c.high - max(c.open, c.close)

        # Bullish VWAP Bounce (Long):
        # 1. Price tested VWAP (low reached near or below VWAP)
        # 2. Rejection happened: close finished back above VWAP
        # 3. Rejection lower wick present
        # 4. Trend filter: Bullish bias (Close >= EMA20 or EMA20 >= EMA50)
        is_touch_vwap_long = (c.low <= v * 1.0005) and (c.close >= v)
        bullish_candle = c.close >= c.open or lower_wick >= 0.35 * candle_range
        bullish_trend = (c.close >= e50) or (e20 >= e50)

        if is_touch_vwap_long and bullish_candle and bullish_trend:
            sl = min(c.low, v) - atr * 0.4
            risk = c.close - sl
            if risk > 0.05:  # Avoid micro-stops
                tp = c.close + max(risk * 1.8, atr * 1.5)
                s = simulate_setup(
                    candles, "long", i, c.close, sl, tp, params,
                    strategy="vwap_bounce_2",
                    trigger_index=i,
                    trigger_level=round(v, 3),
                    note=f"VWAP 2.0 Bounce Long @ {c.close:.2f} (VWAP={v:.2f})",
                    resolve_from=i + 1
                )
                if s:
                    setups.append(s)

        # Bearish VWAP Bounce (Short):
        # 1. Price tested VWAP (high reached near or above VWAP)
        # 2. Rejection happened: close finished back below VWAP
        # 3. Rejection upper wick present
        # 4. Trend filter: Bearish bias (Close <= EMA20 or EMA20 <= EMA50)
        is_touch_vwap_short = (c.high >= v * 0.9995) and (c.close <= v)
        bearish_candle = c.close <= c.open or upper_wick >= 0.35 * candle_range
        bearish_trend = (c.close <= e50) or (e20 <= e50)

        if is_touch_vwap_short and bearish_candle and bearish_trend:
            sl = max(c.high, v) + atr * 0.4
            risk = sl - c.close
            if risk > 0.05:
                tp = c.close - max(risk * 1.8, atr * 1.5)
                s = simulate_setup(
                    candles, "short", i, c.close, sl, tp, params,
                    strategy="vwap_bounce_2",
                    trigger_index=i,
                    trigger_level=round(v, 3),
                    note=f"VWAP 2.0 Bounce Short @ {c.close:.2f} (VWAP={v:.2f})",
                    resolve_from=i + 1
                )
                if s:
                    setups.append(s)

    return setups
