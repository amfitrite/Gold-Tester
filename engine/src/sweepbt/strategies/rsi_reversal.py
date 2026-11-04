"""RSI oversold / overbought reversal.

Wait for RSI to leave an extreme: the first candle that closes back ABOVE
``rsi_short_min`` after having been oversold goes long; the first close back
BELOW ``rsi_long_max`` after overbought goes short. We trade the snap-back, not
the extreme itself, so a single deep print does not fire repeatedly. Entry is
the confirming candle's close; the stop sits beyond that candle's extreme.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..indicators import rsi
from ..simulate import simulate_setup


def run(candles: List[Candle], params: Params) -> List[Setup]:
    closes = [c.close for c in candles]
    r = rsi(closes, params.rsi_period)
    setups: List[Setup] = []
    was_os = was_ob = False           # were we oversold / overbought on the prior bar?
    for i in range(1, len(candles)):
        v, prev = r[i], r[i - 1]
        if v is None or prev is None:
            continue
        c = candles[i]
        if was_os and prev <= params.rsi_short_min and v > params.rsi_short_min:
            sl = c.low - params.sl_buffer
            s = simulate_setup(candles, "long", i, c.close, sl,
                               c.close + (c.close - sl) * params.rr, params,
                               strategy="rsi_reversal", trigger_index=i,
                               trigger_level=round(params.rsi_short_min, 1),
                               note=f"RSI up through {params.rsi_short_min:.0f}",
                               resolve_from=i + 1)
            if s:
                setups.append(s)
        if was_ob and prev >= params.rsi_long_max and v < params.rsi_long_max:
            sl = c.high + params.sl_buffer
            s = simulate_setup(candles, "short", i, c.close, sl,
                               c.close - (sl - c.close) * params.rr, params,
                               strategy="rsi_reversal", trigger_index=i,
                               trigger_level=round(params.rsi_long_max, 1),
                               note=f"RSI down through {params.rsi_long_max:.0f}",
                               resolve_from=i + 1)
            if s:
                setups.append(s)
        was_os = v <= params.rsi_short_min
        was_ob = v >= params.rsi_long_max
    return setups
