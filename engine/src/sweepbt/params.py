"""Tunable parameters and timeframe presets."""
from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Literal, Optional

Timeframe = Literal["M1", "M5", "M15", "M30", "H1", "H4"]
TrendMethod = Literal["ema", "structure"]


@dataclass
class Params:
    # --- detection ---
    swing_strength: int = 3
    min_fvg_size: float = 1.0
    ob_lookahead: int = 3
    fvg_lookahead: int = 4

    # --- simulation ---
    rr: float = 2.0
    sl_buffer: float = 0.5
    pullback_window: int = 12

    # --- Gold rolling liquidity sweep ---
    sweep_lookback: int = 12
    sweep_min_wick_fraction: float = 0.05
    sweep_entry_retrace: float = 0.35

    # --- breakout / ORB strategies ---
    orb_window: int = 4
    breakout_min_room: int = 1

    # --- trend filter / guardrails ---
    trend_method: TrendMethod = "ema"
    ema_fast: int = 20
    ema_slow: int = 50
    require_close_confirmation: bool = False
    max_risk: Optional[float] = None

    # --- optional MA / RSI filters ---
    ma_period: int = 50
    ma_kind: Literal["ema", "sma"] = "ema"
    rsi_period: int = 14
    rsi_long_max: float = 70.0
    rsi_short_min: float = 30.0

    # --- Adaptive Selective Entry (ASE), GoldWave-inspired reconstruction ---
    ase_donchian_period: int = 20
    ase_atr_period: int = 14
    ase_atr_baseline_period: int = 50
    ase_atr_min_ratio: float = 0.65
    ase_atr_max_ratio: float = 1.80
    ase_min_channel_width_atr: float = 1.50
    ase_regime_slope_bars: int = 5
    ase_trend_slope_atr: float = 0.20
    ase_min_body_efficiency: float = 0.55
    ase_rejection_tolerance_atr: float = 0.15
    ase_sl_buffer_atr: float = 0.15
    ase_value_area_period: int = 48
    ase_value_area_fraction: float = 0.70
    ase_profile_bin_size: float = 0.50
    ase_min_target_rr: float = 1.00
    ase_target_rr_max: float = 2.50

    timeframe: Optional[Timeframe] = None

    @classmethod
    def for_timeframe(cls, tf: Timeframe, **overrides) -> "Params":
        base = _PRESETS[tf]
        return replace(base, **overrides)


_PRESETS = {
    "M1": Params(timeframe="M1", swing_strength=3, min_fvg_size=0.3,
                 sl_buffer=0.2, pullback_window=20, orb_window=60, ema_fast=20, ema_slow=50,
                 ase_donchian_period=30, ase_value_area_period=60, ase_profile_bin_size=0.20),
    "M5": Params(timeframe="M5", swing_strength=3, min_fvg_size=0.5,
                 sl_buffer=0.3, pullback_window=16, orb_window=12, ema_fast=20, ema_slow=50,
                 ase_donchian_period=20, ase_value_area_period=48, ase_profile_bin_size=0.50),
    "M15": Params(timeframe="M15", swing_strength=3, min_fvg_size=1.0,
                  sl_buffer=0.5, pullback_window=12, orb_window=4, ema_fast=20, ema_slow=50,
                  ase_donchian_period=20, ase_value_area_period=48, ase_profile_bin_size=0.50),
    "M30": Params(timeframe="M30", swing_strength=3, min_fvg_size=1.5,
                  sl_buffer=0.8, pullback_window=10, orb_window=2, ema_fast=20, ema_slow=50,
                  ase_donchian_period=20, ase_value_area_period=48, ase_profile_bin_size=1.00),
    "H1": Params(timeframe="H1", swing_strength=2, min_fvg_size=2.0,
                 sl_buffer=1.0, pullback_window=8, orb_window=2, ema_fast=20, ema_slow=50,
                 ase_donchian_period=20, ase_value_area_period=48, ase_profile_bin_size=1.00),
    "H4": Params(timeframe="H4", swing_strength=2, min_fvg_size=4.0,
                 sl_buffer=2.0, pullback_window=6, orb_window=1, ema_fast=20, ema_slow=50,
                 ase_donchian_period=20, ase_value_area_period=48, ase_profile_bin_size=2.00),
}
