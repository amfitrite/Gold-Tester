"""Adaptive Selective Entry (ASE): GoldWave-inspired transparent reconstruction.

This is NOT GoldWave's proprietary algorithm. It combines causal Donchian regime
classification, candle-body efficiency, ATR regime gating and VWAP/value-area
rejection with a structural target and a hard stop. OHLCV value-area allocation
is an approximation: each candle's volume is assigned to its typical-price bin.
"""
from __future__ import annotations

from collections import defaultdict
from typing import Dict, List, Optional, Tuple

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup


def _true_ranges(candles: List[Candle]) -> List[float]:
    out: List[float] = []
    prev_close: Optional[float] = None
    for c in candles:
        tr = c.high - c.low
        if prev_close is not None:
            tr = max(tr, abs(c.high - prev_close), abs(c.low - prev_close))
        out.append(max(0.0, tr))
        prev_close = c.close
    return out


def _rolling_mean(values: List[float], period: int) -> List[Optional[float]]:
    out: List[Optional[float]] = [None] * len(values)
    period = max(1, int(period))
    total = 0.0
    for i, value in enumerate(values):
        total += value
        if i >= period:
            total -= values[i - period]
        if i >= period - 1:
            out[i] = total / period
    return out


def _daily_vwap(candles: List[Candle]) -> List[Optional[float]]:
    """Session/day anchored VWAP; rolling-window fallback for timestamp-less data."""
    out: List[Optional[float]] = [None] * len(candles)
    pv = vol = 0.0
    current_day = None
    for i, c in enumerate(candles):
        day = c.timestamp.date() if c.timestamp else None
        if day is not None and day != current_day:
            pv = vol = 0.0
            current_day = day
        v = max(0.0, float(c.volume or 0.0))
        if v == 0:
            v = 1.0
        typical = (c.high + c.low + c.close) / 3.0
        pv += typical * v
        vol += v
        out[i] = pv / vol if vol else typical
    return out


def _value_area(candles: List[Candle], end: int, lookback: int,
                bin_size: float, fraction: float) -> Optional[Tuple[float, float, float]]:
    """Approximate rolling volume profile using typical-price volume bins."""
    start = max(0, end - max(2, lookback))
    bins: Dict[int, float] = defaultdict(float)
    step = max(0.01, float(bin_size))
    total = 0.0
    for c in candles[start:end]:
        price = (c.high + c.low + c.close) / 3.0
        key = int(round(price / step))
        volume = max(0.0, float(c.volume or 0.0))
        if volume == 0:
            volume = 1.0
        bins[key] += volume
        total += volume
    if not bins or total <= 0:
        return None
    keys = sorted(bins)
    poc = max(keys, key=lambda k: bins[k])
    lo = hi = poc
    accumulated = bins[poc]
    target = total * min(0.95, max(0.50, float(fraction)))
    while accumulated < target and (lo > keys[0] or hi < keys[-1]):
        below = bins.get(lo - 1, -1.0) if lo > keys[0] else -1.0
        above = bins.get(hi + 1, -1.0) if hi < keys[-1] else -1.0
        if above >= below and hi < keys[-1]:
            hi += 1
            accumulated += max(0.0, bins.get(hi, 0.0))
        elif lo > keys[0]:
            lo -= 1
            accumulated += max(0.0, bins.get(lo, 0.0))
        else:
            break
    return poc * step, lo * step, hi * step


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if len(candles) < max(30, params.ase_donchian_period + 3):
        return []

    n = max(3, int(params.ase_donchian_period))
    atr_n = max(2, int(params.ase_atr_period))
    atr_base_n = max(atr_n, int(params.ase_atr_baseline_period))
    trs = _true_ranges(candles)
    atr = _rolling_mean(trs, atr_n)
    atr_base = _rolling_mean(trs, atr_base_n)
    vwap = _daily_vwap(candles)
    closes = [c.close for c in candles]
    setups: List[Setup] = []
    next_allowed = max(n, atr_base_n)

    for i in range(next_allowed, len(candles)):
        c = candles[i]
        a = atr[i]
        base = atr_base[i]
        if a is None or base is None or a <= 0 or base <= 0:
            continue

        # All reference levels exclude the signal candle.
        window = candles[i - n:i]
        dc_high = max(x.high for x in window)
        dc_low = min(x.low for x in window)
        dc_mid = (dc_high + dc_low) / 2.0
        width_atr = (dc_high - dc_low) / a
        atr_ratio = a / base
        if not (params.ase_atr_min_ratio <= atr_ratio <= params.ase_atr_max_ratio):
            continue
        if width_atr < params.ase_min_channel_width_atr:
            continue

        slope_n = max(2, int(params.ase_regime_slope_bars))
        old_window = candles[max(0, i - n - slope_n):i - slope_n]
        if len(old_window) < n:
            continue
        old_mid = (max(x.high for x in old_window) + min(x.low for x in old_window)) / 2.0
        slope_atr = (dc_mid - old_mid) / a
        trend_up = slope_atr >= params.ase_trend_slope_atr and c.close > dc_mid
        trend_down = slope_atr <= -params.ase_trend_slope_atr and c.close < dc_mid
        regime = "trend" if trend_up or trend_down else "range"

        candle_range = c.high - c.low
        if candle_range <= 0:
            continue
        efficiency = abs(c.close - c.open) / candle_range
        if efficiency < params.ase_min_body_efficiency:
            continue
        tolerance = a * params.ase_rejection_tolerance_atr
        sl_buffer = a * params.ase_sl_buffer_atr

        direction = None
        trigger = 0.0
        target = None
        source = ""

        if regime == "trend":
            level = vwap[i]
            if level is None:
                continue
            if trend_up and c.bullish and c.low <= level + tolerance and c.close > level:
                direction, trigger, source = "long", level, "VWAP trend reclaim"
                target = dc_high
            elif trend_down and c.bearish and c.high >= level - tolerance and c.close < level:
                direction, trigger, source = "short", level, "VWAP trend rejection"
                target = dc_low
        else:
            profile = _value_area(
                candles, i, params.ase_value_area_period,
                params.ase_profile_bin_size, params.ase_value_area_fraction,
            )
            if profile is None:
                continue
            poc, val, vah = profile
            if c.bullish and c.low <= val + tolerance and c.close > val:
                direction, trigger, source, target = "long", val, "VAL rejection", poc
            elif c.bearish and c.high >= vah - tolerance and c.close < vah:
                direction, trigger, source, target = "short", vah, "VAH rejection", poc

        if direction is None:
            continue

        entry = c.close
        if direction == "long":
            sl = c.low - sl_buffer
            risk = entry - sl
            if risk <= 0:
                continue
            fallback = entry + risk * params.rr
            if target is None or target <= entry:
                target = fallback
            else:
                target = min(target, entry + risk * params.ase_target_rr_max)
                if target < entry + risk * params.ase_min_target_rr:
                    target = fallback
        else:
            sl = c.high + sl_buffer
            risk = sl - entry
            if risk <= 0:
                continue
            fallback = entry - risk * params.rr
            if target is None or target >= entry:
                target = fallback
            else:
                target = max(target, entry - risk * params.ase_target_rr_max)
                if target > entry - risk * params.ase_min_target_rr:
                    target = fallback

        setup = simulate_setup(
            candles, direction, i, entry, sl, target, params,
            strategy="adaptive_selective_entry", trigger_index=i,
            trigger_level=trigger,
            note=f"ASE {regime}: {source}; body-efficiency={efficiency:.2f}; "
                 f"ATR-regime={atr_ratio:.2f}",
            resolve_from=i + 1,
        )
        if setup is None:
            continue
        setups.append(setup)
        next_allowed = setup.exit_index + 1 if setup.exit_index is not None else len(candles)

    return setups
