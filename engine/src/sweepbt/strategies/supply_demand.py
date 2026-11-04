"""Supply / demand zones.

A zone is a quiet "base" candle followed by a strong departure that leaves an
imbalance: a base + bullish departure is DEMAND (buy the return to the base
top), a base + bearish departure is SUPPLY (sell the return to the base bottom).
The departure must be an expansion candle (range well above the recent average)
with a body that dominates it, which is what marks institutional intent. First
return into the base only.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup, Zone
from ..params import Params
from ..simulate import simulate_setup
from ._common import first_touch


def run(candles: List[Candle], params: Params) -> List[Setup]:
    lookback = max(5, params.ema_fast)
    setups: List[Setup] = []
    for i in range(lookback, len(candles)):
        c = candles[i]
        base = candles[i - 1]
        rng = c.high - c.low
        if rng <= 0:
            continue
        avg_range = sum(x.high - x.low for x in candles[i - lookback:i]) / lookback
        body = abs(c.close - c.open)
        # Expansion departure with a dominant body.
        if rng < 1.5 * avg_range or body < 0.6 * rng:
            continue
        if c.bullish:                          # demand: base below, departure up
            direction, entry = "long", base.high
            sl = base.low - params.sl_buffer
            tp = entry + (entry - sl) * params.rr
            note = "demand base"
        elif c.bearish:                        # supply: base above, departure down
            direction, entry = "short", base.low
            sl = base.high + params.sl_buffer
            tp = entry - (sl - entry) * params.rr
            note = "supply base"
        else:
            continue
        j = first_touch(candles, i + 1, i + params.pullback_window, entry, direction)
        if j is None:
            continue
        zone = Zone("OB", top=base.high, bottom=base.low,
                    start_index=i - 1, end_index=i - 1)
        s = simulate_setup(candles, direction, j, entry, sl, tp, params,
                           strategy="supply_demand", trigger_index=i,
                           trigger_level=round(entry, 5), zone=zone, note=note)
        if s:
            setups.append(s)
    return setups
