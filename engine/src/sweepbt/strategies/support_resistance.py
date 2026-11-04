"""Support / resistance bounce.

Cluster prior swing levels into S/R zones (a level touched >= 2 times). When
price later trades into a support zone and CLOSES back above it -> long; into a
resistance zone and closes back below -> short. Only swings that formed BEFORE
the test define the zone, so the level is always known in advance. Each zone is
traded at most once.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..swings import find_swings
from ..structure import support_resistance
from ..simulate import simulate_setup


def run(candles: List[Candle], params: Params) -> List[Setup]:
    swings = find_swings(candles, params.swing_strength)
    tol = max(params.min_fvg_size * 2.0, params.sl_buffer * 2.0)
    setups: List[Setup] = []
    for z in support_resistance(swings, tolerance=tol):
        lo, hi, mid = z["lo"], z["hi"], z["price"]
        # The zone is only "known" once its last contributing swing has formed.
        ready = max((s.index for s in swings
                     if lo <= s.price <= hi), default=0) + params.swing_strength + 1
        done = False
        for i in range(ready, len(candles)):
            if done:
                break
            c = candles[i]
            # Bounce up off support: dipped into the zone but closed back above.
            if c.low <= hi and c.close > hi:
                sl = lo - params.sl_buffer
                s = simulate_setup(candles, "long", i, c.close, sl,
                                   c.close + (c.close - sl) * params.rr, params,
                                   strategy="support_resistance", trigger_index=i,
                                   trigger_level=mid, note=f"bounce off support {mid:.2f}",
                                   resolve_from=i + 1)
                if s:
                    setups.append(s)
                done = True
            elif c.high >= lo and c.close < lo:
                sl = hi + params.sl_buffer
                s = simulate_setup(candles, "short", i, c.close, sl,
                                   c.close - (sl - c.close) * params.rr, params,
                                   strategy="support_resistance", trigger_index=i,
                                   trigger_level=mid, note=f"reject resistance {mid:.2f}",
                                   resolve_from=i + 1)
                if s:
                    setups.append(s)
                done = True
    return setups
