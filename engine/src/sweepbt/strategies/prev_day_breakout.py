"""Strategy 2: previous-day high / low breakout.

For each trading day (after the first), the prior day's high (PDH) and low (PDL)
are resting reference levels. The first candle that CLOSES beyond a level is a
breakout: close > PDH -> long, close < PDL -> short. Entry is taken at the level
(it was crossed intrabar), the stop sits beyond the breakout candle's opposite
extreme + buffer, and the target is RR multiples of that risk. One long and one
short attempt per day at most.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..daygroups import group_by_day, day_high_low
from ..simulate import simulate_setup


def run(candles: List[Candle], params: Params) -> List[Setup]:
    setups: List[Setup] = []
    days = group_by_day(candles)
    for d in range(1, len(days)):
        _, today = days[d]
        pdh, pdl = day_high_low(days[d - 1][1])
        took_long = took_short = False
        for c in today:
            i = c.index
            if not took_long and c.close > pdh:
                took_long = True
                sl = c.low - params.sl_buffer
                s = simulate_setup(candles, "long", i, pdh, sl,
                                   pdh + (pdh - sl) * params.rr, params,
                                   strategy="prev_day_breakout", trigger_index=i,
                                   trigger_level=pdh, note=f"close>{pdh:.2f} (prev-day high)",
                                   resolve_from=i + 1)
                if s:
                    setups.append(s)
            if not took_short and c.close < pdl:
                took_short = True
                sl = c.high + params.sl_buffer
                s = simulate_setup(candles, "short", i, pdl, sl,
                                   pdl - (sl - pdl) * params.rr, params,
                                   strategy="prev_day_breakout", trigger_index=i,
                                   trigger_level=pdl, note=f"close<{pdl:.2f} (prev-day low)",
                                   resolve_from=i + 1)
                if s:
                    setups.append(s)
            if took_long and took_short:
                break
    return setups
