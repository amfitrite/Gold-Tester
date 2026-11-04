"""Momentum pullback (trend continuation).

Trade with the moving-average trend after a shallow counter-trend dip. In an
uptrend (close above the MA) wait for a short run of lower candles, then the
first bullish candle that closes back up is the entry; mirror for downtrends.
The stop sits below the pullback's low (long) / above its high (short), so risk
is the depth of the dip. This buys the dip in a trend rather than chasing
breakouts.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..indicators import moving_average
from ..simulate import simulate_setup


def run(candles: List[Candle], params: Params) -> List[Setup]:
    closes = [c.close for c in candles]
    ma = moving_average(closes, params.ma_period, params.ma_kind)
    setups: List[Setup] = []
    for i in range(2, len(candles)):
        m = ma[i]
        if m is None:
            continue
        c, p1, p2 = candles[i], candles[i - 1], candles[i - 2]
        up_trend = c.close > m and p1.close > (ma[i - 1] or m)
        dn_trend = c.close < m and p1.close > 0 and p1.close < (ma[i - 1] or m)
        # Long: two-candle dip then a bullish reclaim, all above the MA.
        if up_trend and p2.bearish and p1.bearish and c.bullish and c.close > p1.high:
            sl = min(p1.low, p2.low) - params.sl_buffer
            s = simulate_setup(candles, "long", i, c.close, sl,
                               c.close + (c.close - sl) * params.rr, params,
                               strategy="momentum_pullback", trigger_index=i,
                               trigger_level=round(m, 5), note="dip-buy in MA uptrend",
                               resolve_from=i + 1)
            if s:
                setups.append(s)
        elif dn_trend and p2.bullish and p1.bullish and c.bearish and c.close < p1.low:
            sl = max(p1.high, p2.high) + params.sl_buffer
            s = simulate_setup(candles, "short", i, c.close, sl,
                               c.close - (sl - c.close) * params.rr, params,
                               strategy="momentum_pullback", trigger_index=i,
                               trigger_level=round(m, 5), note="rally-sell in MA downtrend",
                               resolve_from=i + 1)
            if s:
                setups.append(s)
    return setups
