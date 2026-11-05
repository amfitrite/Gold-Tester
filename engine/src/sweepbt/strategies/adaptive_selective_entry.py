"""GoldWave-inspired Adaptive Selective Entry (ASE).

This is an original, transparent reconstruction of the public architecture
(regime + momentum + volatility + adaptive exits), not GoldWave source code.
Signals are evaluated on closed candles and filled at the next candle open.
"""
from __future__ import annotations

from typing import List, Optional, Tuple

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_time_exit

STRATEGY_NAME = "adaptive_selective_entry"


def _atr(candles: List[Candle], period: int) -> List[Optional[float]]:
    out: List[Optional[float]] = [None] * len(candles)
    if period < 1 or len(candles) <= period:
        return out
    tr = [0.0] * len(candles)
    for i in range(1, len(candles)):
        c, p = candles[i], candles[i - 1]
        tr[i] = max(c.high - c.low, abs(c.high - p.close), abs(c.low - p.close))
    out[period] = sum(tr[1:period + 1]) / period
    for i in range(period + 1, len(candles)):
        out[i] = ((out[i - 1] * (period - 1)) + tr[i]) / period
    return out


def _donchian(candles: List[Candle], period: int) -> List[Optional[Tuple[float, float, float]]]:
    """Prior-bar channel (current signal candle is excluded to avoid lookahead)."""
    out: List[Optional[Tuple[float, float, float]]] = [None] * len(candles)
    if period < 2:
        return out
    for i in range(period, len(candles)):
        window = candles[i - period:i]
        upper = max(c.high for c in window)
        lower = min(c.low for c in window)
        out[i] = (upper, lower, (upper + lower) / 2.0)
    return out


def _daily_vwap(candles: List[Candle]) -> List[Optional[float]]:
    """Causal daily VWAP; timestamps are interpreted in the CSV's time basis."""
    out: List[Optional[float]] = [None] * len(candles)
    pv = volume = 0.0
    current_day = None
    for i, c in enumerate(candles):
        day = c.timestamp.date() if c.timestamp is not None else None
        if day != current_day:
            pv = volume = 0.0
            current_day = day
        typical = (c.high + c.low + c.close) / 3.0
        weight = c.volume if c.volume is not None and c.volume > 0 else 1.0
        pv += typical * weight
        volume += weight
        out[i] = pv / volume if volume else None
    return out


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if len(candles) < max(params.ase_donchian_period, params.ase_atr_period) + 3:
        return []

    atr = _atr(candles, params.ase_atr_period)
    channels = _donchian(candles, params.ase_donchian_period)
    vwap = _daily_vwap(candles)
    setups: List[Setup] = []
    busy_until = -1

    for i in range(max(params.ase_donchian_period + 1, params.ase_atr_period + 1), len(candles) - 1):
        if i <= busy_until:
            continue
        c = candles[i]
        a = atr[i]
        channel = channels[i]
        prev_channel = channels[i - 1]
        vw = vwap[i]
        if a is None or a <= 0 or channel is None or prev_channel is None or vw is None:
            continue

        upper, lower, mid = channel
        prev_mid = prev_channel[2]
        width_atr = (upper - lower) / a
        if width_atr < params.ase_min_channel_atr or width_atr > params.ase_max_channel_atr:
            continue

        candle_range = c.high - c.low
        if candle_range <= 0:
            continue
        body_efficiency = abs(c.close - c.open) / candle_range
        if body_efficiency < params.ase_min_body_efficiency:
            continue

        # Regime gate: price location and channel-mid slope must agree.
        bullish_regime = c.close > mid and mid >= prev_mid
        bearish_regime = c.close < mid and mid <= prev_mid

        direction = None
        if (bullish_regime and c.low <= vw and c.close > vw and c.close > c.open):
            direction = "long"
        elif (bearish_regime and c.high >= vw and c.close < vw and c.close < c.open):
            direction = "short"
        if direction is None:
            continue

        entry_index = i + 1
        raw_entry = candles[entry_index].open
        half_spread = max(0.0, params.ase_half_spread)
        if direction == "long":
            entry = raw_entry + half_spread
            sl = c.low - params.ase_sl_atr_buffer * a
            risk = entry - sl
            structural_target = upper
            room = structural_target - entry
            trigger = vw
        else:
            entry = raw_entry - half_spread
            sl = c.high + params.ase_sl_atr_buffer * a
            risk = sl - entry
            structural_target = lower
            room = entry - structural_target
            trigger = vw

        if risk <= 0 or room <= 0 or room < params.ase_min_rr * risk:
            continue
        if params.max_risk is not None and risk > params.max_risk:
            continue

        tp = structural_target
        note = (
            f"ASE {direction}: Donchian regime, body efficiency={body_efficiency:.2f}, "
            f"channel/ATR={width_atr:.2f}, daily VWAP rejection; structural target={tp:.2f}"
        )
        setup = simulate_time_exit(
            candles, entry_index, direction, entry, sl, tp,
            params.ase_max_hold_bars, params,
            strategy=STRATEGY_NAME,
            trigger_index=i,
            trigger_level=round(trigger, 5),
            note=note,
            resolve_from=entry_index,
            half_spread=half_spread,
        )
        if setup is None:
            continue
        setups.append(setup)
        busy_until = setup.exit_index if setup.exit_index is not None else entry_index

    return setups
