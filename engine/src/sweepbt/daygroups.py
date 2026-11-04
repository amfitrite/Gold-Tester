"""Group a candle series into trading days (by timestamp date).

Candles without timestamps all fall into a single synthetic day so the
breakout/ORB strategies still run on un-timestamped exports.
"""
from __future__ import annotations

from typing import Dict, List, Tuple

from .models import Candle


def group_by_day(candles: List[Candle]) -> List[Tuple[object, List[Candle]]]:
    days: "Dict[object, List[Candle]]" = {}
    order: List[object] = []
    for c in candles:
        key = c.timestamp.date() if c.timestamp else "_all_"
        if key not in days:
            days[key] = []
            order.append(key)
        days[key].append(c)
    return [(k, days[k]) for k in order]


def day_high_low(candles: List[Candle]) -> Tuple[float, float]:
    return max(c.high for c in candles), min(c.low for c in candles)
