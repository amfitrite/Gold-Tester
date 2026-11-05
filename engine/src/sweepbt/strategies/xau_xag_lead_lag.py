"""XAUUSD / XAGUSD lead-lag catch-up (research candidate).

Silver sometimes moves first and gold follows on M5.  This candidate measures
the rolling price beta of gold to silver, computes the lag between the gold
move implied by the silver move and the actual gold move, and enters gold in
the direction of that lag when silver's move is statistically large.

The production registry does not include this strategy: on 12 months of M5
data the lead-lag correlation was ~0.015, and the best high-win-rate variant
had essentially zero expectancy after costs.  It is retained as a reproducible
research candidate and to document that the cross-asset hypothesis was tested,
not assumed.

Data requirement
----------------
The primary run must supply XAGUSD M5 through ``Params.aux_file`` (or the
runner's ``--aux-file``).  The runner auto-detects ``xagusd_m5.csv`` next to
the XAUUSD file.  Timestamps are aligned exactly; missing silver bars are
forward-filled for the return calculation.
"""
from __future__ import annotations

from collections import deque
from functools import lru_cache
from math import sqrt
from typing import Deque, Dict, List, Optional, Tuple

from ..models import Candle, Setup
from ..params import Params
from ..parser import parse_file
from ..simulate import simulate_time_exit

STRATEGY_NAME = "xau_xag_lead_lag"
LOOKBACK = 1
BETA_WINDOW = 96
Z_ENTRY = 2.0
LAG_ATR = 0.25
SL_ATR = 1.5
TP_ATR = 0.5
MAX_HOLD_BARS = 12
HALF_SPREAD = 0.12


@lru_cache(maxsize=4)
def _aux_candles(path: str) -> Tuple[Candle, ...]:
    return tuple(parse_file(path).candles)


def _atr(candles: List[Candle], period: int = 14) -> List[Optional[float]]:
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


def _rolling_state(pairs: Deque[Tuple[float, float]]) -> Optional[Tuple[float, float]]:
    """Return (beta, std_y) for the current pairs, or None if too few."""
    n = len(pairs)
    if n < BETA_WINDOW:
        return None
    sx = sy = sxx = syy = sxy = 0.0
    for x, y in pairs:
        sx += x
        sy += y
        sxx += x * x
        syy += y * y
        sxy += x * y
    denom = n - 1
    var_y = (syy - sy * sy / n) / denom
    if var_y <= 0:
        return None
    cov = (sxy - sx * sy / n) / denom
    beta = max(0.0, min(5.0, cov / var_y))
    return beta, sqrt(var_y)


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if not params.aux_file:
        return []
    aux = list(_aux_candles(params.aux_file))
    if not aux:
        return []
    aux_by_ts: Dict[object, Candle] = {
        c.timestamp: c for c in aux
        if c.timestamp is not None and c.timestamp.weekday() != 6
    }

    valid_indices = [
        i for i, c in enumerate(candles)
        if c.timestamp is not None and c.timestamp.weekday() != 6
    ]
    if len(valid_indices) < BETA_WINDOW + 5:
        return []
    valid_candles = [candles[i] for i in valid_indices]
    atr_valid = _atr(valid_candles)

    # Silver closes aligned to the valid gold bars, forward-filled when a
    # timestamp is missing on one side.
    aux_valid: List[Optional[float]] = []
    last: Optional[float] = None
    for i in valid_indices:
        c = aux_by_ts.get(candles[i].timestamp)
        if c is not None:
            last = c.close
        aux_valid.append(last)

    pairs: Deque[Tuple[float, float]] = deque()
    setups: List[Setup] = []
    busy_until = -1

    for k in range(LOOKBACK + 1, len(valid_indices) - 1):
        # Add the previous bar's gold/silver change to the estimation window,
        # so the beta at k uses information available before bar k's close.
        j = k - 1
        if aux_valid[j] is not None and aux_valid[j - LOOKBACK] is not None:
            dxau_j = valid_candles[j].close - valid_candles[j - LOOKBACK].close
            dxag_j = aux_valid[j] - aux_valid[j - LOOKBACK]
            pairs.append((dxau_j, dxag_j))
            if len(pairs) > BETA_WINDOW:
                pairs.popleft()
        state = _rolling_state(pairs)
        if state is None:
            continue
        beta, sd = state
        if sd <= 0 or aux_valid[k] is None or aux_valid[k - LOOKBACK] is None:
            continue

        dxau = valid_candles[k].close - valid_candles[k - LOOKBACK].close
        dxag = aux_valid[k] - aux_valid[k - LOOKBACK]
        z = dxag / sd
        lag = beta * dxag - dxau
        atr = atr_valid[k]
        if atr is None or atr <= 0:
            continue
        if abs(z) < Z_ENTRY or abs(lag) < LAG_ATR * atr:
            continue

        candle = valid_candles[k]
        i = valid_indices[k]
        if i < busy_until:
            continue
        if lag > 0 and candle.close > candle.open:
            direction = "long"
        elif lag < 0 and candle.close < candle.open:
            direction = "short"
        else:
            continue

        entry_index = i + 1
        if entry_index >= len(candles):
            continue
        raw_entry = candles[entry_index].open
        entry = (raw_entry + HALF_SPREAD if direction == "long"
                 else raw_entry - HALF_SPREAD)
        if direction == "long":
            sl = entry - SL_ATR * atr
            tp = entry + TP_ATR * atr
        else:
            sl = entry + SL_ATR * atr
            tp = entry - TP_ATR * atr

        setup = simulate_time_exit(
            candles, entry_index, direction, entry, sl, tp,
            MAX_HOLD_BARS, params,
            strategy=STRATEGY_NAME,
            trigger_index=i,
            trigger_level=round(candle.close, 5),
            note=(f"Silver impulse z={z:.2f}, gold lag={lag:.2f} "
                  f"({lag / atr:.2f} ATR), beta={beta:.2f}"),
            resolve_from=entry_index,
            half_spread=HALF_SPREAD,
        )
        if setup is None:
            continue
        setups.append(setup)
        busy_until = setup.exit_index if setup.exit_index is not None else entry_index

    setups.sort(key=lambda s: s.entry_index)
    return setups
