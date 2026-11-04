"""Tunable parameters and timeframe presets."""
from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Literal, Optional

Timeframe = Literal["M1", "M5", "M15", "M30", "H1", "H4"]
TrendMethod = Literal["ema", "structure"]


@dataclass
class Params:
    # --- detection ---
    swing_strength: int = 3          # candles on each side for a swing
    min_fvg_size: float = 1.0        # min gap width in price units
    ob_lookahead: int = 3            # OB must sit within N candles of the sweep
    fvg_lookahead: int = 4           # FVG must sit within ~N candles of the sweep

    # --- simulation ---
    rr: float = 2.0                  # take-profit risk:reward multiple
    sl_buffer: float = 0.5           # extra buffer beyond sweep/zone for the stop
    pullback_window: int = 12        # candles after sweep allowed for entry fill

    # --- Gold rolling liquidity sweep (gold_session_sweep only) ---
    sweep_lookback: int = 12         # prior candles defining the rolling liquidity range
    sweep_min_wick_fraction: float = 0.05  # minimum rejection wick / full candle range
    sweep_entry_retrace: float = 0.25      # fraction of rejection wick retraced for limit entry

    # --- breakout / ORB strategies ---
    orb_window: int = 4              # candles forming the opening range
    breakout_min_room: int = 1       # earliest candle index in a day a breakout may trigger

    # --- trend filter / guardrails ---
    trend_method: TrendMethod = "ema"
    ema_fast: int = 20
    ema_slow: int = 50
    require_close_confirmation: bool = False  # entry needs a close back through zone
    max_risk: Optional[float] = None          # reject setups with risk wider than this

    # --- optional indicator filters (composable with the trend filter) ---
    # MA filter: only take longs when entry close is ABOVE the MA, shorts below.
    ma_period: int = 50
    ma_kind: Literal["ema", "sma"] = "ema"
    # RSI filter: skip longs taken when overbought (rsi >= long_max) and shorts
    # taken when oversold (rsi <= short_min) — i.e. avoid chasing exhaustion.
    rsi_period: int = 14
    rsi_long_max: float = 70.0
    rsi_short_min: float = 30.0

    timeframe: Optional[Timeframe] = None

    @classmethod
    def for_timeframe(cls, tf: Timeframe, **overrides) -> "Params":
        base = _PRESETS[tf]
        return replace(base, **overrides)


# Sensible defaults per timeframe. These are starting points, not gospel — gold
# moves differently at M1 vs H1, so the FVG/buffer scale with the timeframe.
_PRESETS = {
    "M1": Params(timeframe="M1", swing_strength=3, min_fvg_size=0.3,
                 sl_buffer=0.2, pullback_window=20, orb_window=60, ema_fast=20, ema_slow=50),
    "M5": Params(timeframe="M5", swing_strength=3, min_fvg_size=0.5,
                 sl_buffer=0.3, pullback_window=16, orb_window=12, ema_fast=20, ema_slow=50),
    "M15": Params(timeframe="M15", swing_strength=3, min_fvg_size=1.0,
                  sl_buffer=0.5, pullback_window=12, orb_window=4, ema_fast=20, ema_slow=50),
    "M30": Params(timeframe="M30", swing_strength=3, min_fvg_size=1.5,
                  sl_buffer=0.8, pullback_window=10, orb_window=2, ema_fast=20, ema_slow=50),
    "H1": Params(timeframe="H1", swing_strength=2, min_fvg_size=2.0,
                 sl_buffer=1.0, pullback_window=8, orb_window=2, ema_fast=20, ema_slow=50),
    "H4": Params(timeframe="H4", swing_strength=2, min_fvg_size=4.0,
                 sl_buffer=2.0, pullback_window=6, orb_window=1, ema_fast=20, ema_slow=50),
}
