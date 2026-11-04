"""ICT order block.

A structure break (BOS / CHoCH) is driven by an order block: the last
opposite-colour candle before the displacement that broke the level. After an
up-break the bullish OB (last down candle) is demand -> buy the retrace into its
top; after a down-break the bearish OB is supply -> sell the retrace into its
bottom. First retrace only, within the pullback window.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup, Zone
from ..params import Params
from ..swings import find_swings
from ..structure import find_structure_events
from ..simulate import simulate_setup
from ._common import first_touch


def run(candles: List[Candle], params: Params) -> List[Setup]:
    swings = find_swings(candles, params.swing_strength)
    events = find_structure_events(candles, swings, params.swing_strength)
    setups: List[Setup] = []
    for ev in events:
        want_bear = ev.direction == "up"      # up-break springs from a down (bearish) OB
        ob_idx = None
        for j in range(ev.index, max(-1, ev.index - 6), -1):
            cdl = candles[j]
            if (want_bear and cdl.bearish) or (not want_bear and cdl.bullish):
                ob_idx = j
                break
        if ob_idx is None:
            continue
        ob = candles[ob_idx]
        direction = "long" if ev.direction == "up" else "short"
        entry = ob.high if direction == "long" else ob.low
        i = first_touch(candles, ev.index + 1, ev.index + params.pullback_window,
                        entry, direction,
                        require_close=params.require_close_confirmation)
        if i is None:
            continue
        if direction == "long":
            sl = ob.low - params.sl_buffer
            tp = entry + (entry - sl) * params.rr
        else:
            sl = ob.high + params.sl_buffer
            tp = entry - (sl - entry) * params.rr
        zone = Zone("OB", top=ob.high, bottom=ob.low, start_index=ob_idx, end_index=ob_idx)
        s = simulate_setup(candles, direction, i, entry, sl, tp, params,
                           strategy="ict_order_block", trigger_index=ev.index,
                           trigger_level=round(ev.level, 5), zone=zone,
                           note=f"{ev.kind} {ev.direction} OB retrace")
        if s:
            setups.append(s)
    return setups
