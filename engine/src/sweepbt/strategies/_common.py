"""Small shared helpers for the strategy modules.

Kept deliberately tiny: detection logic lives in the dedicated modules
(``swings``, ``imbalance``, ``structure`` …); these are just the bits several
strategies repeat — finding a pullback fill into a zone, and a swing-based stop.
"""
from __future__ import annotations

from typing import List, Optional

from ..models import Candle, Direction


def first_touch(candles: List[Candle], start: int, end: int, level: float,
                direction: Direction, require_close: bool = False) -> Optional[int]:
    """First candle in ``[start, end]`` whose price reaches ``level``.

    Mirrors :func:`simulate.find_entry`: a wick touch fills by default; with
    ``require_close`` the candle must also close back through the level in the
    trade direction (rejection). No lookahead — caller passes a forward window.
    """
    end = min(end, len(candles) - 1)
    for i in range(max(0, start), end + 1):
        c = candles[i]
        if direction == "long":
            touched, confirmed = c.low <= level, c.close > level
        else:
            touched, confirmed = c.high >= level, c.close < level
        if touched and (confirmed or not require_close):
            return i
    return None
