"""Prior-day volume-profile failed auction (London-morning snap-back).

Concept
-------
A volume profile is a histogram of traded volume at each price.  The prior
day's profile gives three important levels:

* POC  - the price with the most traded volume (the day's fair value)
* VAL  - the lower edge of the 80% value area
* VAH  - the upper edge of the 80% value area

During the London morning (09:00-11:59 UTC), a candle that trades **outside the
prior day's value area** but closes back **inside** it has failed to auction in
that direction.  When the prior close was already inside the value area, the
rejection is treated as a snap-back toward fair value.  The trade is
deliberately taken with a small 0.5R target: the edge is the high-probability
reversion, not a large trend continuation.

The long side fades a failed breakdown below VAL when POC is overhead.  The
short side is its mirror: it fades a failed rally above VAH when POC is below
the signal close.  Both directions share the same session and prior-day
filters.

Rules
-----
1. Build a 5.0 USD volume profile from the previous trading day (Sunday bars
   are ignored).  Value area = 80% of prior-day volume.
2. Signal window: 09:00-11:59 UTC only.  One position at a time.
3. Long signal on a closed M5 candle when:
   * prior close is inside [VAL, VAH];
   * low < VAL and close > VAL (failed breakdown);
   * close > open (bullish rejection);
   * POC > close (room back toward fair value).
   The short signal is the mirror image:
   * high > VAH and close < VAH (failed rally);
   * close < open (bearish rejection);
   * POC < close.
4. Enter at the next bar's open with a 0.12 USD adverse half-spread.
5. Long: SL = signal-bar low - 0.50 x ATR(14); TP = entry + 0.50 x risk.
   Short: SL = signal-bar high + 0.50 x ATR(14); TP = entry - 0.50 x risk.
6. Time stop: 48 M5 bars (4 hours).  One position at a time.

The strategy is self-filtered: it has its own session, direction and
prior-day-profile filters, so the generic EMA-20/50 trend filter in
``engine.run`` must not be applied on top of it.

Validation note
---------------
The defaults were chosen during the 12-month XAUUSD M5 research pass and are
reported on a 9/3 train/test split (2025-11-05 .. 2026-11-04).  The final three
months are a holdout-style check, not a strictly untouched out-of-sample test.
They are not a claim that the edge survives every regime; the report documents
the split and cost-stress results.
"""
from __future__ import annotations

from datetime import date
from typing import Dict, List, Optional, Tuple

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_time_exit

STRATEGY_NAME = "volume_profile_failed_auction"

BIN_SIZE = 5.0                 # USD per volume-profile row
VALUE_AREA = 0.80              # share of prior-day volume in the value area
SESSION_START_HOUR = 9         # inclusive, UTC
SESSION_END_HOUR = 11          # inclusive, UTC
ATR_PERIOD = 14
SL_ATR = 0.50                  # stop buffer beyond the rejection extreme
TARGET_RR = 0.50               # fixed target as a fraction of actual risk
MAX_HOLD_BARS = 48             # 4 hours on M5
HALF_SPREAD = 0.12             # USD per side on XAUUSD
ALLOW_SHORT = True             # mirror the failed auction above VAH

Profile = Tuple[float, float, float]  # (POC, VAL, VAH)


def _atr(candles: List[Candle], period: int = ATR_PERIOD) -> List[Optional[float]]:
    """Wilder ATR, causal and ``None`` until the first full window."""
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


def _build_profile(candles: List[Candle], indices: List[int]) -> Optional[Profile]:
    """Build one prior-day volume profile from the given candle indices."""
    bins: Dict[int, float] = {}
    total = 0.0
    for i in indices:
        c = candles[i]
        typical = (c.high + c.low + c.close) / 3.0
        key = round(typical / BIN_SIZE)
        weight = c.volume if c.volume and c.volume > 0 else 1.0
        bins[key] = bins.get(key, 0.0) + weight
        total += weight
    if total <= 0 or not bins:
        return None

    poc_key = max(bins, key=bins.get)
    poc = poc_key * BIN_SIZE
    chosen: List[int] = []
    accumulated = 0.0
    for key, volume in sorted(bins.items(), key=lambda kv: kv[1], reverse=True):
        chosen.append(key)
        accumulated += volume
        if accumulated >= VALUE_AREA * total:
            break
    return poc, min(chosen) * BIN_SIZE, max(chosen) * BIN_SIZE


def _prior_day_profiles(candles: List[Candle],
                        valid_indices: List[int]) -> List[Optional[Profile]]:
    """Map each bar to the profile of the previous non-Sunday trading day."""
    profiles: List[Optional[Profile]] = [None] * len(candles)
    by_day: Dict[date, List[int]] = {}
    for i in valid_indices:
        ts = candles[i].timestamp
        if ts is None or ts.weekday() == 6:
            continue
        by_day.setdefault(ts.date(), []).append(i)

    days = sorted(by_day)
    cache: Dict[date, Optional[Profile]] = {}
    for k in range(1, len(days)):
        previous = days[k - 1]
        current = days[k]
        if previous not in cache:
            cache[previous] = _build_profile(candles, by_day[previous])
        profile = cache[previous]
        if profile is None:
            continue
        for i in by_day[current]:
            profiles[i] = profile
    return profiles


def run(candles: List[Candle], params: Params) -> List[Setup]:
    """Generate non-overlapping failed-auction setups in both directions."""
    if len(candles) < ATR_PERIOD + 3:
        return []

    # The research validation dropped Sunday bars before computing ATR and the
    # prior-day profile.  Keep the same treatment here, while retaining original
    # candle indices so entries and exits still reference the real series.
    valid_indices = [
        i for i, c in enumerate(candles)
        if c.timestamp is not None and c.timestamp.weekday() != 6
    ]
    if len(valid_indices) < ATR_PERIOD + 3:
        return []

    valid_candles = [candles[i] for i in valid_indices]
    valid_atr = _atr(valid_candles)
    atr_by_index: Dict[int, Optional[float]] = {
        original: value for original, value in zip(valid_indices, valid_atr)
    }
    profiles = _prior_day_profiles(candles, valid_indices)

    setups: List[Setup] = []
    busy_until = -1

    for k in range(ATR_PERIOD + 1, len(valid_indices) - 1):
        i = valid_indices[k]
        if i < busy_until:
            continue
        candle = candles[i]
        ts = candle.timestamp
        if ts is None or ts.weekday() == 6:
            continue
        if not (SESSION_START_HOUR <= ts.hour <= SESSION_END_HOUR):
            continue

        a = atr_by_index.get(i)
        profile = profiles[i]
        if a is None or a <= 0 or profile is None:
            continue
        poc, val, vah = profile
        previous_close = valid_candles[k - 1].close

        # The prior close must already be inside value.  A failed breakdown
        # below VAL is a long; the mirror failed rally above VAH is a short.
        if not (val <= previous_close <= vah):
            continue

        direction: Optional[str] = None
        if (candle.low < val and candle.close > val
                and candle.close > candle.open and poc > candle.close):
            direction = "long"
        elif (ALLOW_SHORT
              and candle.high > vah and candle.close < vah
              and candle.close < candle.open and poc < candle.close):
            direction = "short"
        if direction is None:
            continue

        entry_index = i + 1
        if entry_index >= len(candles):
            continue
        raw_entry = candles[entry_index].open
        if direction == "long":
            entry = raw_entry + HALF_SPREAD
            sl = candle.low - SL_ATR * a
            risk = entry - sl
            if risk <= 0:
                continue
            tp = entry + TARGET_RR * risk
            trigger_level = round(val, 5)
            note = (f"Failed auction below prior VAL {val:.2f} "
                    f"(POC {poc:.2f}, VAH {vah:.2f}, ATR {a:.2f})")
        else:
            entry = raw_entry - HALF_SPREAD
            sl = candle.high + SL_ATR * a
            risk = sl - entry
            if risk <= 0:
                continue
            tp = entry - TARGET_RR * risk
            trigger_level = round(vah, 5)
            note = (f"Failed auction above prior VAH {vah:.2f} "
                    f"(POC {poc:.2f}, VAL {val:.2f}, ATR {a:.2f})")

        setup = simulate_time_exit(
            candles, entry_index, direction, entry, sl, tp,
            MAX_HOLD_BARS, params,
            strategy=STRATEGY_NAME,
            trigger_index=i,
            trigger_level=trigger_level,
            note=note,
            resolve_from=entry_index,
            half_spread=HALF_SPREAD,
        )
        if setup is None:
            continue
        setups.append(setup)
        busy_until = setup.exit_index if setup.exit_index is not None else entry_index

    setups.sort(key=lambda s: s.entry_index)
    return setups
