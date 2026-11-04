"""Gold rolling liquidity sweep + rejection retrace.

An XAUUSD M5 research strategy that does not depend on timestamp/session
interpretation. It continuously looks for a sweep of the previous N-bar high
or low, a rejection close back inside that range, and a later 50% retrace of
the rejection candle.

Rules are causal:
- The reference high/low uses only the N candles before the sweep candle.
- Sweep/rejection is confirmed at the sweep candle close.
- The midpoint entry is only searched on later candles.
- A new setup is not considered until the prior simulated trade has exited.
- FVG is optional chart confluence, never a mandatory gate.
"""
from __future__ import annotations

from typing import List, Optional

from ..models import Candle, Setup, Zone
from ..params import Params
from ..simulate import simulate_setup
from ._common import first_touch


MIN_LOOKBACK = 12
LOOKBACK_MULTIPLIER = 8
MIN_REJECTION_WICK_FRACTION = 0.25


def _optional_fvg(
    candles: List[Candle], index: int, direction: str, min_size: float
) -> Optional[Zone]:
    """Return a completed three-candle FVG when one exists."""
    if index < 2:
        return None
    first, current = candles[index - 2], candles[index]
    if direction == "long":
        bottom, top = first.high, current.low
    else:
        bottom, top = current.high, first.low
    if top <= bottom or top - bottom < min_size:
        return None
    return Zone("FVG", top=top, bottom=bottom,
                start_index=index - 2, end_index=index)


def run(candles: List[Candle], params: Params) -> List[Setup]:
    """Generate non-overlapping sweep/rejection/retrace trades."""
    setups: List[Setup] = []
    lookback = max(MIN_LOOKBACK, params.swing_strength * LOOKBACK_MULTIPLIER)
    next_allowed_index = lookback

    for i in range(lookback, len(candles)):
        if i < next_allowed_index:
            continue

        c = candles[i]
        prior = candles[i - lookback:i]
        range_high = max(x.high for x in prior)
        range_low = min(x.low for x in prior)
        candle_range = c.high - c.low
        if candle_range <= 0:
            continue

        upper_wick = c.high - max(c.open, c.close)
        lower_wick = min(c.open, c.close) - c.low

        swept_high = (
            c.high > range_high
            and c.close < range_high
            and c.bearish
            and upper_wick / candle_range >= MIN_REJECTION_WICK_FRACTION
        )
        swept_low = (
            c.low < range_low
            and c.close > range_low
            and c.bullish
            and lower_wick / candle_range >= MIN_REJECTION_WICK_FRACTION
        )

        # A single candle sweeping both ends is ambiguous on OHLC data.
        if swept_high == swept_low:
            continue

        direction = "short" if swept_high else "long"
        trigger_level = range_high if swept_high else range_low
        entry = (c.high + c.low) / 2.0

        entry_index = first_touch(
            candles,
            i + 1,
            min(len(candles) - 1, i + params.pullback_window),
            entry,
            direction,
            require_close=True,
        )
        if entry_index is None:
            continue

        if direction == "long":
            sl = c.low - params.sl_buffer
            if entry <= sl:
                continue
            tp = entry + (entry - sl) * params.rr
        else:
            sl = c.high + params.sl_buffer
            if entry >= sl:
                continue
            tp = entry - (sl - entry) * params.rr

        local_zone = _optional_fvg(candles, i, direction, params.min_fvg_size)
        setup = simulate_setup(
            candles,
            direction,
            entry_index,
            entry,
            sl,
            tp,
            params,
            strategy="gold_session_sweep",
            trigger_index=i,
            trigger_level=trigger_level,
            zone=local_zone,
            note=(
                f"rolling {lookback}-bar {'high' if swept_high else 'low'} "
                f"sweep -> rejection -> 50% retrace"
                f"{' + FVG' if local_zone is not None else ''}"
            ),
            resolve_from=entry_index,
        )
        if setup is None:
            continue

        setups.append(setup)
        # Prevent overlapping entries. If the trade remains unresolved to the
        # end of available data, there is no later trade to evaluate anyway.
        next_allowed_index = (
            setup.exit_index + 1 if setup.exit_index is not None else len(candles)
        )

    return setups
