"""Imbalance detection: order blocks (OB) and fair value gaps (FVG).

For a given sweep we prefer an OB; if none sits close enough we fall back to a
direction-aligned FVG, per the strategy spec.
"""
from __future__ import annotations

from typing import List, Optional, Tuple

from .models import Candle, Direction, Sweep, Zone


def find_fvgs(candles: List[Candle], min_size: float = 1.0) -> List[Tuple[Zone, Direction]]:
    """Return all 3-candle fair value gaps as ``(zone, direction)``.

    Bullish FVG: ``low[3] > high[1]`` (gap below price). Bearish FVG:
    ``high[3] < low[1]``. Candle indices are 1/2/3 = i/i+1/i+2. The gap width
    must strictly exceed ``min_size``.
    """
    out: List[Tuple[Zone, Direction]] = []
    for i in range(len(candles) - 2):
        c1, c3 = candles[i], candles[i + 2]
        if c3.low > c1.high and (c3.low - c1.high) > min_size:
            out.append((Zone("FVG", top=c3.low, bottom=c1.high,
                             start_index=i, end_index=i + 2), "long"))
        elif c3.high < c1.low and (c1.low - c3.high) > min_size:
            out.append((Zone("FVG", top=c1.low, bottom=c3.high,
                             start_index=i, end_index=i + 2), "short"))
    return out


def find_order_block(candles: List[Candle], sweep: Sweep, lookahead: int = 3) -> Optional[Zone]:
    """Order block = last opposite-color candle immediately before the impulse.

    Long (buy-side sweep): first bullish "impulse" candle in the window whose
    immediately-preceding candle is bearish -> that bearish candle is the OB.
    Short mirrors this (last bullish candle before a bearish impulse).
    """
    direction = sweep.direction
    n = len(candles)
    last = min(n - 1, sweep.index + lookahead)
    for p in range(sweep.index, last + 1):
        prev = p - 1
        if prev < 0:
            continue
        if direction == "long" and candles[p].bullish and candles[prev].bearish:
            ob = candles[prev]
            return Zone("OB", top=ob.high, bottom=ob.low, start_index=prev, end_index=prev)
        if direction == "short" and candles[p].bearish and candles[prev].bullish:
            ob = candles[prev]
            return Zone("OB", top=ob.high, bottom=ob.low, start_index=prev, end_index=prev)
    return None


def find_aligned_fvg(candles: List[Candle], sweep: Sweep, min_size: float,
                     lookahead: int) -> Optional[Zone]:
    """First FVG aligned with the trade direction within ``lookahead`` of the sweep."""
    for zone, direction in find_fvgs(candles, min_size):
        if direction != sweep.direction:
            continue
        if sweep.index <= zone.start_index <= sweep.index + lookahead:
            return zone
    return None


def select_zone(candles: List[Candle], sweep: Sweep, *, ob_lookahead: int = 3,
                fvg_lookahead: int = 4, min_fvg_size: float = 1.0) -> Optional[Zone]:
    """Pick the entry zone for a sweep: OB first, else an aligned FVG."""
    ob = find_order_block(candles, sweep, lookahead=ob_lookahead)
    if ob is not None:
        return ob
    return find_aligned_fvg(candles, sweep, min_size=min_fvg_size, lookahead=fvg_lookahead)
