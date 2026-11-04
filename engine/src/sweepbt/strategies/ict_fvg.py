"""ICT fair value gap (FVG) fill.

A 3-candle imbalance leaves a gap price tends to revisit. After a bullish FVG
forms, the first pullback that taps the top of the gap is a long (entry at that
proximal edge, stop below the gap); a bearish FVG mirrors this for shorts. We
trade the gap in its own direction and only the first tap, within the pullback
window.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..imbalance import find_fvgs
from ..simulate import simulate_setup
from ._common import first_touch


def run(candles: List[Candle], params: Params) -> List[Setup]:
    setups: List[Setup] = []
    for zone, direction in find_fvgs(candles, params.min_fvg_size):
        entry = zone.proximal(direction)
        start = zone.end_index + 1
        end = zone.end_index + params.pullback_window
        i = first_touch(candles, start, end, entry, direction,
                        require_close=params.require_close_confirmation)
        if i is None:
            continue
        if direction == "long":
            sl = zone.bottom - params.sl_buffer
            tp = entry + (entry - sl) * params.rr
        else:
            sl = zone.top + params.sl_buffer
            tp = entry - (sl - entry) * params.rr
        s = simulate_setup(candles, direction, i, entry, sl, tp, params,
                           strategy="ict_fvg", trigger_index=zone.start_index,
                           trigger_level=entry, zone=zone,
                           note=f"{direction} FVG fill [{zone.bottom:.2f}-{zone.top:.2f}]")
        if s:
            setups.append(s)
    return setups
