"""Gold rolling liquidity sweep + rejection-wick retrace.

Causal XAUUSD setup:
- Build the reference high/low from the previous configurable N candles.
- Require a wick beyond that range and a close back inside it.
- Place a limit entry a configurable fraction back into the rejection wick.
- Entry can only fill on a later candle; optional close confirmation is honored.
- Stop is beyond the sweep extreme; TP is the configured R multiple.

The defaults are a research starting point, not a profitability claim.
"""
from __future__ import annotations

from typing import List, Optional

from ..models import Candle, Setup, Zone
from ..params import Params
from ..simulate import simulate_setup
from ._common import first_touch


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
    """Generate non-overlapping sweep / rejection / limit-retrace trades."""
    setups: List[Setup] = []
    lookback = max(3, int(params.sweep_lookback))
    min_wick_fraction = min(0.95, max(0.0, float(params.sweep_min_wick_fraction)))
    entry_retrace = min(0.95, max(0.05, float(params.sweep_entry_retrace)))
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
        upper_fraction = upper_wick / candle_range
        lower_fraction = lower_wick / candle_range

        swept_high = (
            c.high > range_high
            and c.close < range_high
            and upper_fraction >= min_wick_fraction
        )
        swept_low = (
            c.low < range_low
            and c.close > range_low
            and lower_fraction >= min_wick_fraction
        )

        # A candle that takes both sides has ambiguous intrabar sequencing on OHLC.
        if swept_high == swept_low:
            continue

        if swept_high:
            direction = "short"
            trigger_level = range_high
            # Sell limit above the close, inside the upper rejection wick.
            entry = c.close + upper_wick * entry_retrace
            if not c.close < entry < c.high:
                continue
            sl = c.high + params.sl_buffer
        else:
            direction = "long"
            trigger_level = range_low
            # Buy limit below the close, inside the lower rejection wick.
            entry = c.close - lower_wick * entry_retrace
            if not c.low < entry < c.close:
                continue
            sl = c.low - params.sl_buffer

        entry_index = first_touch(
            candles,
            i + 1,
            min(len(candles) - 1, i + params.pullback_window),
            entry,
            direction,
            require_close=params.require_close_confirmation,
        )
        if entry_index is None:
            continue

        risk = abs(entry - sl)
        if risk <= 0:
            continue
        tp = entry - risk * params.rr if direction == "short" else entry + risk * params.rr

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
                f"rolling {lookback}-bar "
                f"{'high' if swept_high else 'low'} sweep -> rejection -> "
                f"{entry_retrace:.0%} wick retrace"
                f"{' + FVG' if local_zone is not None else ''}"
            ),
            resolve_from=entry_index,
        )
        if setup is None:
            continue

        setups.append(setup)
        # Do not open another setup while this simulated position is active.
        next_allowed_index = (
            setup.exit_index + 1 if setup.exit_index is not None else len(candles)
        )

    return setups
