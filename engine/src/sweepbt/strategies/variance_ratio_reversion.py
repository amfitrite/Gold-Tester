"""Variance-ratio regime strategy.

This strategy uses return persistence rather than session levels, liquidity
sweeps, bands, or oscillators. In mean-reverting regimes it fades unusual
multi-bar moves; in persistent regimes it follows them.
"""
from __future__ import annotations

import math
from typing import List, Optional

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_time_exit

STRATEGY_NAME = "variance_ratio_regime"
RET_WINDOW = 96
DISPLACEMENT_BARS = 12
VARIANCE_LAG = 4
Z_ENTRY = 2.0
VR_MAX = 0.80
MODE = "reversion"
STOP_ATR = 1.0
MAX_HOLD_BARS = 12
HALF_SPREAD = 0.12


def _atr(candles: List[Candle], period: int = 14) -> List[Optional[float]]:
    n = len(candles)
    if n <= period:
        return [None] * n
    tr: List[Optional[float]] = [None] * n
    for i in range(1, n):
        c, prev = candles[i], candles[i - 1]
        tr[i] = max(c.high-c.low, abs(c.high-prev.close), abs(c.low-prev.close))
    out: List[Optional[float]] = [None] * n
    out[period] = sum(v for v in tr[1:period+1] if v is not None) / period
    for i in range(period+1, n):
        out[i] = (out[i-1] * (period-1) + tr[i]) / period
    return out


def _prefix(values: List[float]):
    sums, squares = [0.0], [0.0]
    for v in values:
        sums.append(sums[-1] + v)
        squares.append(squares[-1] + v*v)
    return sums, squares


def _variance(sums, squares, start: int, end: int) -> float:
    n = end - start
    if n <= 1:
        return 0.0
    total = sums[end] - sums[start]
    total2 = squares[end] - squares[start]
    return max(0.0, (total2 - total*total/n) / n)


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if len(candles) < RET_WINDOW + DISPLACEMENT_BARS + 5:
        return []

    returns = [0.0]
    for i in range(1, len(candles)):
        prev, curr = candles[i-1].close, candles[i].close
        returns.append(math.log(curr / prev) if prev > 0 and curr > 0 else 0.0)
    rsum, rsq = _prefix(returns)
    lagged = [0.0] * len(returns)
    for i in range(VARIANCE_LAG, len(returns)):
        lagged[i] = sum(returns[i-VARIANCE_LAG+1:i+1])
    lsum, lsq = _prefix(lagged)
    atr = _atr(candles)

    setups: List[Setup] = []
    busy_until = -1
    z_threshold = Z_ENTRY
    vr_threshold = VR_MAX
    stop_atr = STOP_ATR
    rr = params.rr if params.rr and params.rr > 0 else 0.65

    for i in range(max(RET_WINDOW, DISPLACEMENT_BARS), len(candles)-1):
        if i <= busy_until:
            continue
        a = atr[i]
        if a is None or a <= 0:
            continue

        start = i - RET_WINDOW + 1
        variance_1 = _variance(rsum, rsq, start, i+1)
        variance_lag = _variance(lsum, lsq, start, i+1)
        if variance_1 <= 0:
            continue
        vr = variance_lag / (VARIANCE_LAG * variance_1)
        sigma = math.sqrt(variance_1)
        displacement = rsum[i+1] - rsum[i-DISPLACEMENT_BARS+1]
        z = displacement / (sigma * math.sqrt(DISPLACEMENT_BARS))

        if abs(z) < z_threshold:
            continue
        if MODE == "reversion":
            if vr > vr_threshold:
                continue
            direction = "long" if z < 0 else "short"
        else:
            if vr < vr_threshold:
                continue
            direction = "long" if z > 0 else "short"
        entry_index = i + 1
        entry = candles[entry_index].open + (HALF_SPREAD if direction == "long" else -HALF_SPREAD)
        risk = stop_atr * a
        if direction == "long":
            sl, tp = entry-risk, entry+rr*risk
        else:
            sl, tp = entry+risk, entry-rr*risk

        setup = simulate_time_exit(
            candles, entry_index, direction, entry, sl, tp,
            MAX_HOLD_BARS, params,
            strategy=STRATEGY_NAME,
            trigger_index=i,
            trigger_level=candles[i].close,
            note=f"{MODE} regime: {DISPLACEMENT_BARS}-bar z={z:.2f}, variance ratio={vr:.2f}",
            resolve_from=entry_index,
            half_spread=HALF_SPREAD,
        )
        if setup is not None:
            setups.append(setup)
            busy_until = setup.exit_index if setup.exit_index is not None else entry_index

    return setups
