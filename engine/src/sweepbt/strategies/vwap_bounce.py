"""VWAP bounce: trade price returning to Volume Weighted Average Price.

VWAP is a volume-weighted average that shows the true "market balance point."
When price bounces off VWAP (oversold at low, overbought at high relative to VWAP),
it often reverts back to VWAP or continues in the direction of the bounce.
Entry is when price touches VWAP from either side; stop is 1 candle's range
beyond the touch point.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def _calculate_vwap(candles: List) -> List[float]:
    """Calculate VWAP: Cumulative(TP × Vol) / Cumulative(Vol)."""
    vwap = [None] * len(candles)
    cumulative_pv = 0  # Cumulative Price × Volume
    cumulative_vol = 0  # Cumulative Volume
    for i, c in enumerate(candles):
        tp = (c.high + c.low + c.close) / 3
        vol = c.volume if c.volume else 1  # Use 1 if no volume (unit volume)
        cumulative_pv += tp * vol
        cumulative_vol += vol
        vwap[i] = cumulative_pv / cumulative_vol
    return vwap


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if not candles or len(candles) < 5:
        return []

    vwap = _calculate_vwap(candles)
    setups: List[Setup] = []

    for i in range(2, len(candles)):
        c = candles[i]
        prev_c = candles[i - 1]
        prev_prev = candles[i - 2]
        v = vwap[i]

        if v is None:
            continue

        # Long: price was below VWAP and touches/crosses it from below
        if prev_prev.close < vwap[i - 2] and prev_c.close < v and c.close >= v:
            atr = max(c.high - c.low, prev_c.high - prev_c.low)
            sl = c.low - atr * 0.5  # 0.5× recent range as stop
            target = v + (v - c.low)  # Distance from entry to VWAP
            s = simulate_setup(candles, "long", i, c.close, sl, target, params,
                             strategy="vwap_bounce",
                             trigger_index=i,
                             trigger_level=round(v, 5),
                             note=f"VWAP bounce long {v:.2f}",
                             resolve_from=i + 1)
            if s:
                setups.append(s)

        # Short: price was above VWAP and touches/crosses it from above
        if prev_prev.close > vwap[i - 2] and prev_c.close > v and c.close <= v:
            atr = max(c.high - c.low, prev_c.high - prev_c.low)
            sl = c.high + atr * 0.5  # 0.5× recent range as stop
            target = v - (c.high - v)  # Distance from VWAP to entry
            s = simulate_setup(candles, "short", i, c.close, sl, target, params,
                             strategy="vwap_bounce",
                             trigger_index=i,
                             trigger_level=round(v, 5),
                             note=f"VWAP bounce short {v:.2f}",
                             resolve_from=i + 1)
            if s:
                setups.append(s)

    return setups
