"""Market-structure markings: BOS / CHoCH, support/resistance, inverse FVG, breaker.

These are analytical *markings* layered on the chart (and used as context), not
standalone tradeable signals. All are computed causally (a swing is only "known"
``strength`` candles after its pivot) so nothing peeks into the future.
"""
from __future__ import annotations

from typing import List, NamedTuple, Optional, Tuple

from .models import Candle, Swing, Zone, Direction


class StructureEvent(NamedTuple):
    index: int            # candle where the break closed
    level: float          # the swing level that was broken
    kind: str             # 'BOS' (continuation) or 'CHoCH' (change of character)
    direction: str        # 'up' or 'down'


def find_structure_events(candles: List[Candle], swings: List[Swing],
                          strength: int = 3) -> List[StructureEvent]:
    highs = [s for s in swings if s.kind == "high"]
    lows = [s for s in swings if s.kind == "low"]
    events: List[StructureEvent] = []
    trend: Optional[str] = None
    last_hi_idx = last_lo_idx = -1

    for i, c in enumerate(candles):
        known_highs = [s for s in highs if s.index <= i - strength]
        known_lows = [s for s in lows if s.index <= i - strength]
        if known_highs:
            lsh = known_highs[-1]
            if c.close > lsh.price and lsh.index != last_hi_idx:
                kind = "BOS" if trend == "up" else "CHoCH"
                events.append(StructureEvent(i, lsh.price, kind, "up"))
                trend, last_hi_idx = "up", lsh.index
        if known_lows:
            lsl = known_lows[-1]
            if c.close < lsl.price and lsl.index != last_lo_idx:
                kind = "BOS" if trend == "down" else "CHoCH"
                events.append(StructureEvent(i, lsl.price, kind, "down"))
                trend, last_lo_idx = "down", lsl.index
    return events


def support_resistance(swings: List[Swing], tolerance: float) -> List[dict]:
    """Cluster swing levels that sit within ``tolerance`` price units; a cluster
    touched >= 2 times is an S/R zone."""
    clusters: List[List[float]] = []
    for s in sorted(swings, key=lambda s: s.price):
        if clusters and abs(s.price - (sum(clusters[-1]) / len(clusters[-1]))) <= tolerance:
            clusters[-1].append(s.price)
        else:
            clusters.append([s.price])
    return [{"price": sum(cl) / len(cl), "touches": len(cl),
             "lo": min(cl), "hi": max(cl)} for cl in clusters if len(cl) >= 2]


def inverse_fvgs(candles: List[Candle],
                 fvgs: List[Tuple[Zone, Direction]]) -> List[dict]:
    """An FVG that price later CLOSES through flips polarity (inverse FVG / IFVG)."""
    out: List[dict] = []
    for zone, direction in fvgs:
        for i in range(zone.end_index + 1, len(candles)):
            c = candles[i]
            if direction == "long" and c.close < zone.bottom:
                out.append({"top": zone.top, "bottom": zone.bottom,
                            "start": zone.start_index, "violated": i, "new_dir": "short"})
                break
            if direction == "short" and c.close > zone.top:
                out.append({"top": zone.top, "bottom": zone.bottom,
                            "start": zone.start_index, "violated": i, "new_dir": "long"})
                break
    return out


def find_breakers(candles: List[Candle], events: List[StructureEvent]) -> List[dict]:
    """A breaker block = the last opposite-color candle before a CHoCH move."""
    out: List[dict] = []
    for ev in events:
        if ev.kind != "CHoCH":
            continue
        want_bear = ev.direction == "up"   # bullish CHoCH springs from a down candle
        for j in range(ev.index, max(-1, ev.index - 5), -1):
            cdl = candles[j]
            if (want_bear and cdl.bearish) or (not want_bear and cdl.bullish):
                out.append({"top": cdl.high, "bottom": cdl.low, "index": j,
                            "dir": ev.direction})
                break
    return out
