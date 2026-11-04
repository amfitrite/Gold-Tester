"""Build setups from sweeps + zones and simulate fixed-RR outcomes.

The simulation is candle-by-candle hindsight on past data: it reports what the
rules WOULD have flagged, not a prediction. When a single candle's range spans
both stop and target we resolve it as a LOSS (pessimistic tie-break), since we
cannot know intrabar order from OHLC alone.
"""
from __future__ import annotations

from typing import List, Optional

from .models import Candle, Setup, Sweep, Zone
from .params import Params
from .imbalance import select_zone


def find_entry(candles: List[Candle], sweep: Sweep, zone: Zone, params: Params
               ) -> Optional[int]:
    """First candle (within the pullback window) at which price enters the zone.

    Default: a wick touch of the proximal edge fills the entry. With
    ``require_close_confirmation`` the candle must also CLOSE back through that
    edge in the trade direction (rejection), which cuts fast counter-trend wicks.
    """
    direction = sweep.direction
    entry = zone.proximal(direction)
    # No lookahead: the pullback can only be sought once the zone candle(s) have
    # fully formed, i.e. strictly after zone.end_index.
    start = max(sweep.index + 1, zone.end_index + 1)
    end = min(len(candles) - 1, sweep.index + params.pullback_window)
    for i in range(start, end + 1):
        c = candles[i]
        if direction == "long":
            touched = c.low <= entry
            confirmed = c.close > entry
        else:
            touched = c.high >= entry
            confirmed = c.close < entry
        if touched and (confirmed or not params.require_close_confirmation):
            return i
    return None


def simulate_outcome(candles: List[Candle], entry_index: int, direction: str,
                     entry: float, sl: float, tp: float):
    """Walk forward from the entry candle. Returns (verdict, exit_index, exit_price)."""
    for i in range(entry_index, len(candles)):
        c = candles[i]
        if direction == "long":
            hit_sl = c.low <= sl
            hit_tp = c.high >= tp
        else:
            hit_sl = c.high >= sl
            hit_tp = c.low <= tp
        if hit_sl and hit_tp:
            return "loss", i, sl          # pessimistic tie-break
        if hit_tp:
            return "win", i, tp
        if hit_sl:
            return "loss", i, sl
    return "unresolved", None, None


def simulate_setup(candles, direction, entry_index, entry, sl, tp, params, *,
                   strategy, trigger_index, trigger_level, note="", sweep=None, zone=None,
                   resolve_from=None):
    """Shared builder: validate risk, run the walk-forward, return a Setup or None.

    Used by every strategy so the entry/SL/TP/RR accounting and win/loss
    resolution are identical across them. ``resolve_from`` lets a strategy that
    fills at a candle's close start the walk-forward on the next candle.
    """
    risk = abs(entry - sl)
    if risk <= 0:
        return None
    if params.max_risk is not None and risk > params.max_risk:
        return None
    resolve_index = resolve_from if resolve_from is not None else entry_index
    verdict, exit_index, exit_price = simulate_outcome(
        candles, resolve_index, direction, entry, sl, tp)
    r = 0.0 if verdict == "unresolved" else (params.rr if verdict == "win" else -1.0)
    return Setup(direction=direction, entry_index=entry_index, entry_price=entry,
                 stop_loss=sl, take_profit=tp, risk=risk, verdict=verdict,
                 strategy=strategy, trigger_index=trigger_index, trigger_level=trigger_level,
                 note=note, sweep=sweep, zone=zone, resolve_index=resolve_index,
                 exit_index=exit_index, exit_price=exit_price, r_multiple=r)


def build_setup(candles: List[Candle], sweep: Sweep, params: Params) -> Optional[Setup]:
    """Build one setup for a sweep, or None if no valid zone/entry/risk."""
    zone = select_zone(candles, sweep, ob_lookahead=params.ob_lookahead,
                        fvg_lookahead=params.fvg_lookahead, min_fvg_size=params.min_fvg_size)
    if zone is None:
        return None

    direction = sweep.direction
    entry = zone.proximal(direction)
    if direction == "long":
        sl = min(sweep.wick, zone.bottom) - params.sl_buffer
    else:
        sl = max(sweep.wick, zone.top) + params.sl_buffer

    risk = abs(entry - sl)
    if risk <= 0:
        return None
    if params.max_risk is not None and risk > params.max_risk:
        return None  # guardrail: reject bloated zones

    tp = entry + risk * params.rr if direction == "long" else entry - risk * params.rr

    entry_index = find_entry(candles, sweep, zone, params)
    if entry_index is None:
        return None  # never pulled back into the zone within the window

    return simulate_setup(candles, direction, entry_index, entry, sl, tp, params,
                          strategy="liquidity_imbalance", trigger_index=sweep.index,
                          trigger_level=sweep.level, sweep=sweep, zone=zone,
                          note=f"{sweep.side}-side sweep + {zone.kind}")


def build_setups(candles: List[Candle], sweeps: List[Sweep], params: Params) -> List[Setup]:
    setups = []
    for sw in sweeps:
        s = build_setup(candles, sw, params)
        if s is not None:
            setups.append(s)
    setups.sort(key=lambda s: s.entry_index)
    return setups
