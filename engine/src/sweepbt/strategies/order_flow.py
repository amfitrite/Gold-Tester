"""Order Flow strategy: detects accumulation/distribution via volume + price action.

Identifies effort vs result mismatch: high volume candles that fail to move price
further, indicating trapped buyers/sellers. Entry follows when price breaks in the
direction of the trapped liquidity, targeting the wick extreme for exit.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def _volume_profile(candles: List[Candle], start: int, end: int) -> float:
    """Average volume in a window."""
    if start >= len(candles) or end <= start:
        return 0.0
    window = candles[start:end]
    return sum(c.volume for c in window) / len(window) if window else 0.0


def run(candles: List[Candle], params: Params) -> List[Setup]:
    setups: List[Setup] = []

    for i in range(20, len(candles)):
        c = candles[i]
        p1 = candles[i - 1]
        p2 = candles[i - 2] if i >= 2 else None

        # Average volume over last 20 candles
        avg_vol = _volume_profile(candles, max(0, i - 20), i)
        if avg_vol == 0:
            continue

        # Look for effort/result mismatch: high volume, small body, large wick
        volume_spike = c.volume >= 1.5 * avg_vol
        body_size = abs(c.close - c.open)
        wick_size = c.high - c.low
        body_ratio = (body_size / wick_size) if wick_size > 0 else 0
        rejection = volume_spike and body_ratio < 0.4  # small body relative to wick

        if not rejection or p1 is None:
            continue

        # Determine which side trapped liquidity
        # Bullish rejection (wick down, close up): trapped shorts -> go long on next up
        bullish_rejection = c.bullish and c.low < p1.low and c.volume >= 1.2 * avg_vol
        # Bearish rejection (wick up, close down): trapped longs -> go short on next down
        bearish_rejection = c.bearish and c.high > p1.high and c.volume >= 1.2 * avg_vol

        if bullish_rejection and i + 1 < len(candles):
            next_c = candles[i + 1]
            # Entry on close above current candle (confirming trapped shorts covered)
            if next_c.close > c.close:
                sl = c.low - params.sl_buffer
                entry = next_c.close
                if entry > sl:
                    s = simulate_setup(
                        candles, "long", i + 1, entry, sl,
                        entry + (entry - sl) * params.rr, params,
                        strategy="order_flow",
                        trigger_index=i, trigger_level=c.high,
                        note=f"bullish rejection @{c.high:.2f}, vol {c.volume:.0f}",
                        resolve_from=i + 2
                    )
                    if s:
                        setups.append(s)

        if bearish_rejection and i + 1 < len(candles):
            next_c = candles[i + 1]
            # Entry on close below current candle (confirming trapped longs covered)
            if next_c.close < c.close:
                sl = c.high + params.sl_buffer
                entry = next_c.close
                if entry < sl:
                    s = simulate_setup(
                        candles, "short", i + 1, entry, sl,
                        entry - (sl - entry) * params.rr, params,
                        strategy="order_flow",
                        trigger_index=i, trigger_level=c.low,
                        note=f"bearish rejection @{c.low:.2f}, vol {c.volume:.0f}",
                        resolve_from=i + 2
                    )
                    if s:
                        setups.append(s)

    return setups
