"""Strategy 3: opening-range breakout (ORB).

The opening range is the high/low of the first 15 minutes of the 9:30 EST (14:30 UTC)
market open, adjusted per timeframe. After that window, the first candle to CLOSE above
the range high goes long; the first to close below the range low goes short. Entry at
the broken range edge, stop on the opposite range edge + buffer, target RR of risk.
One long and one short attempt per day.
"""
from __future__ import annotations

from datetime import datetime, timezone, timedelta
from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..daygroups import group_by_day
from ..simulate import simulate_setup


def _is_market_open_time(ts: datetime, tf: str) -> bool:
    """Check if timestamp is at or after 14:30 UTC (9:30 EST market open)."""
    if ts is None:
        return False
    # 14:30 UTC = 9:30 EST
    hour, minute = ts.hour, ts.minute
    return (hour > 14) or (hour == 14 and minute >= 30)


def _get_or_window_size(tf: str) -> int:
    """Return candle count for first 15 minutes of market open at each timeframe."""
    return {"M5": 3, "M15": 1, "M30": 1, "H1": 1, "H4": 1}.get(tf, 1)


def run(candles: List[Candle], params: Params) -> List[Setup]:
    setups: List[Setup] = []
    tf = params.timeframe or "M5"

    for _, today in group_by_day(candles):
        or_start_idx = 0
        or_window = max(1, params.orb_window)

        # If timestamps are available, use market open time instead of configured window
        if today and today[0].timestamp is not None:
            for j, c in enumerate(today):
                if _is_market_open_time(c.timestamp, tf):
                    or_start_idx = j
                    or_window = _get_or_window_size(tf)
                    break

        if len(today) <= or_start_idx + or_window + 1:
            continue

        # Use candles from market open (or first candles if no timestamp) for the OR window
        or_candles = today[or_start_idx : or_start_idx + or_window]
        or_hi = max(c.high for c in or_candles)
        or_lo = min(c.low for c in or_candles)

        took_long = took_short = False
        for c in today[or_start_idx + or_window:]:
            i = c.index
            if not took_long and c.close > or_hi:
                took_long = True
                sl = or_lo - params.sl_buffer
                s = simulate_setup(candles, "long", i, or_hi, sl,
                                   or_hi + (or_hi - sl) * params.rr, params,
                                   strategy="orb", trigger_index=i, trigger_level=or_hi,
                                   note=f"close>{or_hi:.2f} (OR high)", resolve_from=i + 1)
                if s:
                    setups.append(s)
            if not took_short and c.close < or_lo:
                took_short = True
                sl = or_hi + params.sl_buffer
                s = simulate_setup(candles, "short", i, or_lo, sl,
                                   or_lo - (sl - or_lo) * params.rr, params,
                                   strategy="orb", trigger_index=i, trigger_level=or_lo,
                                   note=f"close<{or_lo:.2f} (OR low)", resolve_from=i + 1)
                if s:
                    setups.append(s)
            if took_long and took_short:
                break
    return setups
