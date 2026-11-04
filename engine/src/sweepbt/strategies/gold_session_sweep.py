"""Gold Session Sweep + Displacement + FVG Retest.

Designed for XAUUSD M5. Timestamps are interpreted as UTC (Dukascopy convention):
- Build the Asia range from 00:00 up to, but excluding, 07:00 UTC.
- From 07:00 to 20:00 UTC, wait for price to sweep one side and close back inside.
- Within the next four bars, require a directional displacement candle.
- Prefer a 50% retrace of that displacement; FVG is recorded as confluence when
  present, but is not mandatory.

No future candle is used to define a signal: the Asia range is complete before
the trading window, ATR uses only earlier candles, displacement/FVG are known at
their close, and the retrace must happen strictly afterwards. One trade maximum
per UTC day to avoid duplicate entries and same-day signal clustering.
"""
from __future__ import annotations

from typing import List, Optional, Tuple

from ..daygroups import group_by_day
from ..models import Candle, Setup, Zone
from ..params import Params
from ..simulate import simulate_setup
from ._common import first_touch

ASIA_START_HOUR = 0
ASIA_END_HOUR = 7
TRADE_START_HOUR = 7
TRADE_END_HOUR = 20
ATR_PERIOD = 14
# Loosened after the first implementation produced too few/no setups in practice.
DISPLACEMENT_ATR_MULTIPLE = 0.75
MIN_BODY_FRACTION = 0.45
MAX_DISPLACEMENT_BARS = 4


def _true_range(candle: Candle, previous_close: Optional[float]) -> float:
    """True range for one completed candle."""
    value = candle.high - candle.low
    if previous_close is not None:
        value = max(value, abs(candle.high - previous_close),
                    abs(candle.low - previous_close))
    return value


def _atr_before(candles: List[Candle], index: int) -> Optional[float]:
    """ATR ending at index-1; the candidate displacement bar is excluded."""
    start = max(1, index - ATR_PERIOD)
    if index - start < ATR_PERIOD:
        return None
    ranges = [
        _true_range(candles[j], candles[j - 1].close)
        for j in range(start, index)
    ]
    return sum(ranges) / len(ranges) if ranges else None


def _asia_range(day: List[Candle]) -> Optional[Tuple[float, float, int]]:
    """Return (high, low, last Asia index) from completed 00:00-06:59 UTC bars."""
    asia = [
        (i, c) for i, c in enumerate(day)
        if c.timestamp is not None
        and ASIA_START_HOUR <= c.timestamp.hour < ASIA_END_HOUR
    ]
    if len(asia) < 5:
        return None
    return (
        max(c.high for _, c in asia),
        min(c.low for _, c in asia),
        asia[-1][0],
    )


def _displacement_direction(
    candles: List[Candle], index: int, direction: str
) -> bool:
    """Strong, directional displacement confirmed by a close beyond prior bar."""
    c = candles[index]
    previous = candles[index - 1]
    atr = _atr_before(candles, index)
    candle_range = c.high - c.low
    if atr is None or atr <= 0 or candle_range <= 0:
        return False

    body_fraction = abs(c.close - c.open) / candle_range
    if candle_range < atr * DISPLACEMENT_ATR_MULTIPLE:
        return False
    if body_fraction < MIN_BODY_FRACTION:
        return False

    # A directional close beyond the previous close is a softer continuation
    # test than requiring a full break of the previous candle's extreme.
    if direction == "short":
        return c.bearish and c.close < previous.close
    return c.bullish and c.close > previous.close


def _fvg_zone(
    candles: List[Candle], index: int, direction: str, min_size: float
) -> Optional[Zone]:
    """Find a 3-candle FVG completed on index."""
    if index < 2:
        return None
    first = candles[index - 2]
    current = candles[index]

    if direction == "long":
        bottom, top = first.high, current.low
    else:
        bottom, top = current.high, first.low

    if top <= bottom or (top - bottom) < min_size:
        return None
    return Zone(
        "FVG", top=top, bottom=bottom,
        start_index=index - 2, end_index=index,
    )


def run(candles: List[Candle], params: Params) -> List[Setup]:
    """Generate at most one confirmed Asia-range sweep trade per UTC day."""
    setups: List[Setup] = []
    if len(candles) < ATR_PERIOD + 5:
        return setups

    for _, day in group_by_day(candles):
        levels = _asia_range(day)
        if levels is None:
            continue
        asia_high, asia_low, last_asia_index = levels

        # Trade only after the Asia range is complete. Limit signals to London
        # and New York activity; ignore late-session candles after 20:00 UTC.
        trade_indices = [
            i for i, c in enumerate(day)
            if c.timestamp is not None
            and c.timestamp.hour >= TRADE_START_HOUR
            and c.timestamp.hour < TRADE_END_HOUR
            and i > last_asia_index
        ]
        if not trade_indices:
            continue

        active_end_index = max(trade_indices)
        day_trade: Optional[Setup] = None
        for local_i in trade_indices:
            sweep = day[local_i]
            swept_high = sweep.high > asia_high and sweep.close < asia_high
            swept_low = sweep.low < asia_low and sweep.close > asia_low

            # A candle that traverses both edges is ambiguous on OHLC data.
            if swept_high == swept_low:
                continue
            direction = "short" if swept_high else "long"
            trigger_level = asia_high if swept_high else asia_low

            # Require displacement shortly after the sweep. If price reclaims
            # the swept edge before displacement, the setup is invalidated.
            displacement_index = None
            for candidate_i in range(local_i + 1,
                                     min(active_end_index + 1,
                                         local_i + MAX_DISPLACEMENT_BARS + 1)):
                candidate = day[candidate_i]
                reclaimed = (
                    candidate.close > asia_high if direction == "short"
                    else candidate.close < asia_low
                )
                if reclaimed:
                    break
                if _displacement_direction(day, candidate_i, direction):
                    displacement_index = candidate_i
                    break
            if displacement_index is None:
                continue

            # FVG is useful confluence, but it is not a mandatory gate. A
            # displacement can be tradeable even when the three-candle gap is
            # tiny or absent. Use the displacement midpoint for a practical
            # pullback entry in either case.
            zone = _fvg_zone(
                day, displacement_index, direction, params.min_fvg_size
            )
            displacement = day[displacement_index]
            entry = (displacement.high + displacement.low) / 2.0
            entry_index = first_touch(
                day,
                displacement_index + 1,
                min(active_end_index,
                    displacement_index + params.pullback_window),
                entry,
                direction,
                require_close=True,
            )
            if entry_index is None:
                continue

            if direction == "long":
                sl = sweep.low - params.sl_buffer
                tp = entry + (entry - sl) * params.rr
            else:
                sl = sweep.high + params.sl_buffer
                tp = entry - (sl - entry) * params.rr

            # Re-index day-local positions into the original candle series.
            # Candle.index is the stable global index supplied by the parser.
            global_entry = day[entry_index].index
            global_trigger = day[local_i].index
            global_zone = None
            if zone is not None:
                global_zone = Zone(
                    "FVG", top=zone.top, bottom=zone.bottom,
                    start_index=day[zone.start_index].index,
                    end_index=day[zone.end_index].index,
                )
            setup = simulate_setup(
                candles, direction, global_entry, entry, sl, tp, params,
                strategy="gold_session_sweep",
                trigger_index=global_trigger,
                trigger_level=trigger_level,
                zone=global_zone,
                note=f"Asia {'high' if swept_high else 'low'} sweep -> "
                     f"displacement 50% retrace"
                     f"{' + FVG' if global_zone is not None else ''} ({direction})",
                resolve_from=global_entry,
            )
            if setup is not None:
                day_trade = setup
                break

        if day_trade is not None:
            setups.append(day_trade)

    setups.sort(key=lambda setup: setup.entry_index)
    return setups
