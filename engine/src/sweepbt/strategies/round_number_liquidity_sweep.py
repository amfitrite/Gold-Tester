"""Round-number liquidity sweep (research candidate).

This module is a direct implementation of the preliminary round-number idea:
sweep a $25 multiple, close back inside, then trade a 2.0 x ATR stop against a
0.5 x ATR target.  It was tested on 12 months of XAUUSD M5 before being
rejected for production because the high win rate did not survive realistic
costs (negative expectancy, large drawdown).

The module is kept as a reproducible research candidate; it is not part of the
production registry unless explicitly re-enabled.
"""
from __future__ import annotations

import math
from typing import List, Optional

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_time_exit

STRATEGY_NAME = "round_number_liquidity_sweep"
LEVEL_STEP = 25.0
SESSION_START_HOUR = 7
SESSION_END_HOUR = 17
ATR_PERIOD = 14
WICK_ATR = 0.20
CLOSE_ATR = 0.05
SL_ATR = 2.0
TP_ATR = 0.5
MAX_HOLD_BARS = 12
HALF_SPREAD = 0.12


def _atr(candles: List[Candle], period: int = ATR_PERIOD) -> List[Optional[float]]:
    n = len(candles)
    if n < period + 1:
        return [None] * n
    trs: List[Optional[float]] = [None] * n
    for i in range(1, n):
        c, prev = candles[i], candles[i - 1]
        trs[i] = max(c.high - c.low, abs(c.high - prev.close),
                     abs(c.low - prev.close))
    atr: List[Optional[float]] = [None] * n
    atr[period] = sum(trs[1:period + 1]) / period
    for i in range(period + 1, n):
        atr[i] = (atr[i - 1] * (period - 1) + trs[i]) / period
    return atr


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if len(candles) < ATR_PERIOD + 3:
        return []
    valid_indices = [
        i for i, c in enumerate(candles)
        if c.timestamp is not None and c.timestamp.weekday() != 6
    ]
    if len(valid_indices) < ATR_PERIOD + 3:
        return []
    valid_candles = [candles[i] for i in valid_indices]
    valid_atr = _atr(valid_candles)
    atr_by_index = dict(zip(valid_indices, valid_atr))

    setups: List[Setup] = []
    busy_until = -1
    for k in range(ATR_PERIOD + 1, len(valid_indices) - 1):
        i = valid_indices[k]
        if i < busy_until:
            continue
        candle = candles[i]
        ts = candle.timestamp
        if ts is None or not (SESSION_START_HOUR <= ts.hour <= SESSION_END_HOUR):
            continue
        a = atr_by_index.get(i)
        if a is None or a <= 0:
            continue

        long_level = math.floor(candle.close / LEVEL_STEP) * LEVEL_STEP
        long_signal = (
            long_level < candle.close
            and long_level > candle.low
            and (long_level - candle.low) >= WICK_ATR * a
            and (candle.close - long_level) >= CLOSE_ATR * a
            and candle.close > candle.open
        )
        short_level = math.ceil(candle.close / LEVEL_STEP) * LEVEL_STEP
        short_signal = (
            short_level > candle.close
            and short_level < candle.high
            and (candle.high - short_level) >= WICK_ATR * a
            and (short_level - candle.close) >= CLOSE_ATR * a
            and candle.close < candle.open
        )
        if long_signal == short_signal:
            continue

        direction = "long" if long_signal else "short"
        entry_index = i + 1
        raw_entry = candles[entry_index].open
        entry = (raw_entry + HALF_SPREAD if direction == "long"
                 else raw_entry - HALF_SPREAD)
        if direction == "long":
            sl = entry - SL_ATR * a
            tp = entry + TP_ATR * a
        else:
            sl = entry + SL_ATR * a
            tp = entry - TP_ATR * a

        setup = simulate_time_exit(
            candles, entry_index, direction, entry, sl, tp,
            MAX_HOLD_BARS, params,
            strategy=STRATEGY_NAME,
            trigger_index=i,
            trigger_level=long_level if direction == "long" else short_level,
            note=f"{direction.title()} sweep of round level",
            resolve_from=entry_index,
            half_spread=HALF_SPREAD,
        )
        if setup is None:
            continue
        setups.append(setup)
        busy_until = setup.exit_index if setup.exit_index is not None else entry_index

    setups.sort(key=lambda s: s.entry_index)
    return setups
