"""Session gap fade: trade gaps between session opens (Asian → London → NY).

Gold (XAUUSD) trades 24/5 with distinct sessions. When the NY session closes
and Asian opens the next day, or when Asian closes and London opens, there's
often a gap. This strategy fades (trades against) the gap direction, expecting
reversion. Entry is at the first candle of the new session; stop is 1.5× the
gap size beyond the open.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def _get_session(timestamp) -> str:
    """Return 'asia', 'london', or 'newyork' based on UTC hour."""
    if timestamp is None:
        return 'unknown'
    # Handle both string and datetime objects
    if hasattr(timestamp, 'hour'):
        hour = timestamp.hour
    else:
        hour = int(str(timestamp).split('T')[1].split(':')[0])
    if 21 <= hour or hour < 8:
        return 'asia'  # 21:00-23:59 and 00:00-07:59 UTC
    elif 8 <= hour < 13:
        return 'london'  # 08:00-12:59 UTC
    else:
        return 'newyork'  # 13:00-20:59 UTC


def run(candles: List[Candle], params: Params) -> List[Setup]:
    setups: List[Setup] = []

    if not candles or len(candles) < 2:
        return setups

    prev_session = None
    for i in range(1, len(candles)):
        c = candles[i]
        prev_c = candles[i - 1]

        # Skip if no timestamp (test data)
        if c.timestamp is None or prev_c.timestamp is None:
            continue

        curr_session = _get_session(c.timestamp)

        # Detect session change
        if prev_session is None:
            prev_session = _get_session(prev_c.timestamp)

        if curr_session != prev_session:
            # Session boundary detected
            gap = c.open - prev_c.close
            gap_size = abs(gap)

            if gap_size > 0.10:  # Minimum gap size (0.10 in price units)
                if gap > 0:  # Gap up (bullish): fade with short
                    sl = c.open + gap_size * 1.5
                    target = prev_c.close - gap_size  # Revert to previous close
                    s = simulate_setup(candles, "short", i, c.open, sl, target, params,
                                     strategy="session_gap",
                                     trigger_index=i,
                                     trigger_level=round(c.open, 5),
                                     note=f"Gap up fade: {prev_session}→{curr_session}",
                                     resolve_from=i + 1)
                    if s:
                        setups.append(s)
                else:  # Gap down (bearish): fade with long
                    sl = c.open - gap_size * 1.5
                    target = prev_c.close + gap_size  # Revert to previous close
                    s = simulate_setup(candles, "long", i, c.open, sl, target, params,
                                     strategy="session_gap",
                                     trigger_index=i,
                                     trigger_level=round(c.open, 5),
                                     note=f"Gap down fade: {prev_session}→{curr_session}",
                                     resolve_from=i + 1)
                    if s:
                        setups.append(s)

        prev_session = curr_session

    return setups
