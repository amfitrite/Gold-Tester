"""Smart-money concept: sweep -> change of character -> order block.

The full SMC sequence: price first sweeps a liquidity level (stops run), THEN
shifts structure in the opposite direction (a CHoCH confirms the reversal), and
we enter on the retrace into the order block that drove that shift. Requiring the
CHoCH after the sweep is the discretionary "confirmation" leg the bare liquidity
strategy skips, so this fires less often but with structure behind it.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup, Zone
from ..params import Params
from ..swings import find_swings
from ..sweeps import find_sweeps
from ..structure import find_structure_events
from ..simulate import simulate_setup
from ._common import first_touch


def run(candles: List[Candle], params: Params) -> List[Setup]:
    swings = find_swings(candles, params.swing_strength)
    sweeps = find_sweeps(candles, swings)
    events = find_structure_events(candles, swings, params.swing_strength)
    window = params.pullback_window
    setups: List[Setup] = []
    for sw in sweeps:
        direction = sw.direction
        want = "up" if direction == "long" else "down"
        # First CHoCH in the reversal direction shortly after the sweep.
        choch = next((e for e in events if e.kind == "CHoCH" and e.direction == want
                      and sw.index < e.index <= sw.index + window), None)
        if choch is None:
            continue
        want_bear = direction == "long"        # long springs from a bearish OB
        ob_idx = None
        for j in range(choch.index, max(-1, choch.index - 6), -1):
            cdl = candles[j]
            if (want_bear and cdl.bearish) or (not want_bear and cdl.bullish):
                ob_idx = j
                break
        if ob_idx is None:
            continue
        ob = candles[ob_idx]
        entry = ob.high if direction == "long" else ob.low
        i = first_touch(candles, choch.index + 1, choch.index + window, entry, direction,
                        require_close=params.require_close_confirmation)
        if i is None:
            continue
        if direction == "long":
            sl = min(ob.low, sw.wick) - params.sl_buffer
            tp = entry + (entry - sl) * params.rr
        else:
            sl = max(ob.high, sw.wick) + params.sl_buffer
            tp = entry - (sl - entry) * params.rr
        zone = Zone("OB", top=ob.high, bottom=ob.low, start_index=ob_idx, end_index=ob_idx)
        s = simulate_setup(candles, direction, i, entry, sl, tp, params,
                           strategy="smart_money", trigger_index=sw.index,
                           trigger_level=round(sw.level, 5), sweep=sw, zone=zone,
                           note=f"{sw.side}-sweep -> CHoCH -> OB")
        if s:
            setups.append(s)
    return setups
