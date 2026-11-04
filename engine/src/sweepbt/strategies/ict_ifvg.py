"""ICT inverse fair value gap (IFVG).

When price CLOSES through an FVG it invalidates it, and the gap flips polarity:
a bullish gap that gets closed below becomes resistance, a bearish gap closed
above becomes support. We trade the first retest of the flipped zone in the new
direction, after the violation candle.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup, Zone
from ..params import Params
from ..imbalance import find_fvgs
from ..structure import inverse_fvgs
from ..simulate import simulate_setup
from ._common import first_touch


def run(candles: List[Candle], params: Params) -> List[Setup]:
    fvgs = find_fvgs(candles, params.min_fvg_size)
    setups: List[Setup] = []
    for x in inverse_fvgs(candles, fvgs):
        direction = x["new_dir"]
        top, bottom = x["top"], x["bottom"]
        entry = top if direction == "long" else bottom
        start = x["violated"] + 1
        end = x["violated"] + params.pullback_window
        i = first_touch(candles, start, end, entry, direction,
                        require_close=params.require_close_confirmation)
        if i is None:
            continue
        if direction == "long":
            sl = bottom - params.sl_buffer
            tp = entry + (entry - sl) * params.rr
        else:
            sl = top + params.sl_buffer
            tp = entry - (sl - entry) * params.rr
        zone = Zone("FVG", top=top, bottom=bottom,
                    start_index=x["start"], end_index=x["violated"])
        s = simulate_setup(candles, direction, i, entry, sl, tp, params,
                           strategy="ict_ifvg", trigger_index=x["violated"],
                           trigger_level=entry, zone=zone,
                           note=f"inverse FVG retest -> {direction}")
        if s:
            setups.append(s)
    return setups
