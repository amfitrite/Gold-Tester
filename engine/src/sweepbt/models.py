"""Core data structures for the sweep/imbalance backtester.

Everything downstream of the parser operates on plain ``Candle`` objects and the
small value objects below, so detection logic stays pure and unit-testable
without pandas in the hot path.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Literal, Optional

Side = Literal["buy", "sell"]          # liquidity / sweep side
Direction = Literal["long", "short"]   # resulting trade direction
ZoneKind = Literal["OB", "FVG"]
Verdict = Literal["win", "loss", "unresolved"]


@dataclass(frozen=True)
class Candle:
    """A single OHLC candle. ``index`` is its position in the series (0-based)."""

    index: int
    open: float
    high: float
    low: float
    close: float
    volume: float = 0.0
    spread: float = 0.0
    timestamp: Optional[datetime] = None

    @property
    def bullish(self) -> bool:
        return self.close > self.open

    @property
    def bearish(self) -> bool:
        return self.close < self.open

    @property
    def label(self) -> str:
        return self.timestamp.strftime("%Y-%m-%d %H:%M") if self.timestamp else f"#{self.index}"


@dataclass(frozen=True)
class Swing:
    """A swing point = a resting liquidity level."""

    index: int
    price: float
    kind: Literal["high", "low"]

    @property
    def side(self) -> Side:
        # A swing high sits above price -> sell-side liquidity.
        return "sell" if self.kind == "high" else "buy"


@dataclass(frozen=True)
class Sweep:
    """A liquidity grab: wick beyond ``level`` then close back on the origin side."""

    index: int            # candle that performed the sweep
    level: float          # the swept price level
    swing_index: int      # which swing was swept
    side: Side            # 'sell' = took highs, 'buy' = took lows
    wick: float           # the extreme of the sweeping wick (high for sell, low for buy)

    @property
    def direction(self) -> Direction:
        # Took the lows (buy-side) -> expect long reversal, and vice-versa.
        return "long" if self.side == "buy" else "short"


@dataclass(frozen=True)
class Zone:
    """An imbalance entry zone (order block or fair value gap)."""

    kind: ZoneKind
    top: float
    bottom: float
    start_index: int      # first candle that defines the zone
    end_index: int        # last candle that defines the zone

    @property
    def width(self) -> float:
        return self.top - self.bottom

    def proximal(self, direction: Direction) -> float:
        """Near edge in trade direction (price pulls back to this edge)."""
        return self.top if direction == "long" else self.bottom

    def distal(self, direction: Direction) -> float:
        return self.bottom if direction == "long" else self.top


@dataclass
class Setup:
    """A fully built + simulated setup."""

    direction: Direction
    entry_index: int
    entry_price: float
    stop_loss: float
    take_profit: float
    risk: float                       # price distance entry -> SL
    verdict: Verdict
    # Strategy provenance + the level/candle that triggered the setup. For the
    # liquidity strategy the trigger is the swept level; for breakouts it is the
    # PDH/PDL or opening-range edge.
    strategy: str = "liquidity_imbalance"
    trigger_index: int = 0
    trigger_level: float = 0.0
    note: str = ""
    # Optional, strategy-specific context (None for breakout/ORB).
    sweep: Optional[Sweep] = None
    zone: Optional[Zone] = None
    # Candle the walk-forward starts on (== entry_index unless the fill is at a
    # close and resolution begins next bar). Lets the lab re-walk faithfully.
    resolve_index: Optional[int] = None
    exit_index: Optional[int] = None
    exit_price: Optional[float] = None
    r_multiple: float = 0.0           # realized R (RR on win, -1 on loss, 0 unresolved)
    # Filled in by the trend filter so the report can show keep/skip per setup.
    filter_kept: bool = True
    filter_reason: str = ""

    @property
    def swept_price(self) -> float:
        return self.sweep.level if self.sweep else self.trigger_level
