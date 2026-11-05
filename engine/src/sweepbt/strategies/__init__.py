"""Strategy registry. Each strategy maps candles + params -> List[Setup].

Add new strategies here as the tester grows.
"""
from __future__ import annotations

from typing import Callable, Dict, List

from ..models import Candle, Setup
from ..params import Params
from .liquidity_imbalance import run as _liq
from .prev_day_breakout import run as _pdb
from .orb import run as _orb
from .rsi_reversal import run as _rsi
from .support_resistance import run as _sr
from .momentum_breakout import run as _mbo
from .momentum_pullback import run as _mpb
from .ict_fvg import run as _fvg
from .ict_ifvg import run as _ifvg
from .ict_order_block import run as _iob
from .smart_money import run as _smc
from .supply_demand import run as _sd
from .order_flow import run as _of
from .bollinger_bands import run as _bb
from .bollinger_bands_2 import run as _bb2
from .bollinger_rsi_reversion import run as _bb_rsi
from .session_gap import run as _sg
from .vwap_bounce import run as _vwap
from .vwap_bounce_2 import run as _vwap2
from .gold_session_sweep import run as _gold_session_sweep
from .london_ny_vwap_pullback import run as _ln_vwap
from .london_sweep_trap import run as _lst
from .liquidity_bubble_trap import run as _liq_bubble
from .variance_ratio_reversion import run as _variance_ratio_regime
from .volume_profile_failed_auction import run as _vp_failed_auction
from .doji_ride import run as _doji_ride
from .adaptive_selective_entry import run as _ase

StrategyFn = Callable[[List[Candle], Params], List[Setup]]

# Strategies that already apply their own bias/session filter.  The generic
# EMA-20/50 trend filter in engine.run would double-filter (and silently
# discard) their setups, so it is skipped for these names.
SELF_FILTERED = {
    "london_sweep_trap",
    "vwap_bounce",
    "vwap_bounce_2",
    "doji_ride",
    "volume_profile_failed_auction",
    "liquidity_bubble_trap",
    "bollinger_bands",
    "bollinger_bands_2",
    "prev_day_breakout",
    "london_ny_vwap_pullback",
    "variance_ratio_regime",
    "adaptive_selective_entry"
}

REGISTRY: Dict[str, StrategyFn] = {
    "liquidity_imbalance": _liq,
    "prev_day_breakout": _pdb,
    "orb": _orb,
    "rsi_reversal": _rsi,
    "support_resistance": _sr,
    "momentum_breakout": _mbo,
    "momentum_pullback": _mpb,
    "ict_fvg": _fvg,
    "ict_ifvg": _ifvg,
    "ict_order_block": _iob,
    "smart_money": _smc,
    "supply_demand": _sd,
    "order_flow": _of,
    "bollinger_bands": _bb,
    "bollinger_bands_2": _bb2,
    "bollinger_rsi_reversion": _bb_rsi,
    "session_gap": _sg,
    "vwap_bounce": _vwap,
    "vwap_bounce_2": _vwap2,
    "gold_session_sweep": _gold_session_sweep,
    "london_ny_vwap_pullback": _ln_vwap,
    "london_sweep_trap": _lst,
    "liquidity_bubble_trap": _liq_bubble,
    "variance_ratio_regime": _variance_ratio_regime,
    "volume_profile_failed_auction": _vp_failed_auction,
    "doji_ride": _doji_ride,
    "adaptive_selective_entry": _ase,
}

LABELS = {
    "liquidity_imbalance": "Liquidity Sweep + Imbalance",
    "prev_day_breakout": "Previous-Day High/Low Breakout",
    "orb": "Opening-Range Breakout (ORB)",
    "rsi_reversal": "RSI Oversold / Overbought Reversal",
    "support_resistance": "Support / Resistance Bounce",
    "momentum_breakout": "Momentum Breakout",
    "momentum_pullback": "Momentum Pullback (Trend)",
    "ict_fvg": "ICT Fair Value Gap",
    "ict_ifvg": "ICT Inverse Fair Value Gap",
    "ict_order_block": "ICT Order Block",
    "smart_money": "Smart Money (Sweep + CHoCH + OB)",
    "supply_demand": "Supply / Demand Zones",
    "order_flow": "Order Flow (Effort vs Result)",
    "bollinger_bands": "Bollinger Bands (v1 Baseline)",
    "bollinger_bands_2": "Bollinger Bands 2 (Trend Reversal)",
    "bollinger_rsi_reversion": "Bollinger Bands + RSI (Documented Loss)",
    "session_gap": "Session Gap Fade",
    "vwap_bounce": "VWAP Bounce (v1 Baseline)",
    "vwap_bounce_2": "VWAP Bounce 2 (Optimized)",
    "gold_session_sweep": "Gold Rolling Liquidity Sweep + 50% Rejection Retest",
    "london_ny_vwap_pullback": "London/NY VWAP Trend Pullback",
    "london_sweep_trap": "London Sweep Trap (Institutional Judas Trap)",
    "liquidity_bubble_trap": "Liquidity Sweep + Volume Bubble Trap (Bookmap Absorption)",
    "variance_ratio_regime": "Variance-Ratio Regime Strategy",
    "volume_profile_failed_auction": "Volume-Profile Failed Auction (London Long)",
    "doji_ride": "Doji Ride (Structural Liquidity Sweep & Momentum Breakout)",
    "adaptive_selective_entry": "Adaptive Selective Entry (GoldWave-inspired, transparent rules)",
}

# One-line plain-English descriptions, surfaced in the lab when a strategy is
# picked. Keep them to a single sentence.
DESCRIPTIONS = {
    "liquidity_imbalance": "Wait for a swing high/low to be swept (stops run), then "
        "enter the reversal off the order block / FVG the sweep leaves behind.",
    "prev_day_breakout": "Trade the first close beyond the prior day's high (long) or "
        "low (short); stop beyond the breakout candle, target a multiple of that risk.",
    "orb": "Mark the opening-range high/low from the first few candles of the day, "
        "then trade the first close that breaks out of that range.",
    "rsi_reversal": "Fade exhaustion: go long when RSI climbs back out of oversold, "
        "short when it drops back out of overbought — trading the snap-back, not the extreme.",
    "support_resistance": "Cluster repeated swing levels into zones, then buy a bounce off "
        "support (close back above) or sell a rejection at resistance (close back below).",
    "momentum_breakout": "Trade the first expansion candle that closes beyond the recent "
        "high/low range — a breakout with momentum behind it, not a quiet drift through.",
    "momentum_pullback": "With the moving-average trend, buy a shallow dip (or sell a shallow "
        "rally) once a candle closes back in the trend direction.",
    "ict_fvg": "Trade the first pullback that fills a 3-candle fair-value gap in the gap's "
        "own direction; stop on the far side of the gap.",
    "ict_ifvg": "When price closes through an FVG it flips polarity — trade the retest of that "
        "inverted gap as support/resistance in the new direction.",
    "ict_order_block": "After a structure break (BOS/CHoCH), enter on the retrace into the order "
        "block — the last opposite candle that drove the break.",
    "smart_money": "Full SMC sequence: a liquidity sweep, then a change of character confirming "
        "the reversal, then an entry on the order block behind the shift.",
    "supply_demand": "Mark a quiet base candle followed by a strong departure as a supply/demand "
        "zone, then trade the first return into that base.",
    "order_flow": "Detect volume spikes with small body + large wick (rejection): trapped buyers "
        "or sellers. Enter on confirmation after they cover, trading the continuation.",
    "bollinger_bands": "Trade mean reversion: go long when price touches the lower band, "
        "short when it touches the upper band, targeting a bounce to the middle.",
    "bollinger_bands_2": "High-winrate outer band rejection with built-in EMA 20/50 trend confluence, volatility stop buffer, and asymmetric mean reversion target.",
    "bollinger_rsi_reversion": "Dokumentasi baseline ritel: outer band + RSI overbought/oversold, exit middle band. Terbukti gagal di tren kuat emas (WR 36.5%, DD 82.5%).",
    "session_gap": "Gold trades 24/5 across sessions (Asia, London, NY). Fade gaps between "
        "session opens — expect reversion when a new session gaps away from the previous close.",
    "vwap_bounce": "Volume-weighted average price shows the market's true balance. Trade price "
        "bouncing off VWAP: entry at the bounce, stop at 0.5× recent range, target the VWAP level.",
    "vwap_bounce_2": "Optimized VWAP bounce with EMA 20/50 trend confluence, rejection wick confirmation, and dynamic 1.5R-2.0R profit targets.",
    "gold_session_sweep": "Sweep the previous 24-bar high/low, close back inside with a rejection wick, "
        "then trade a later 50% retrace; works without timestamps and FVG is optional.",
    "london_ny_vwap_pullback": "M5 only, recommended risk 1.0-1.5%. During London/NY "
        "(07:00-17:59 UTC), buy a bullish rejection back above session VWAP when price is "
        "above the 200-EMA, or sell the mirror image below it; fixed 1.25xATR stop/target "
        "and a 2-hour time stop.",
    "london_sweep_trap": "Institutional London and NY session VWAP liquidity trap: exploits false breakouts with rapid asymmetric mean reversion (WR>75%, DD<3%).",
    "liquidity_bubble_trap": "Dual-engine institutional liquidity absorption & failed auction fading false breakouts (WR 80.8%, DD < 3.8%).",
    "variance_ratio_regime": "Use a rolling variance ratio to classify return behavior; fade unusually large moves in anti-persistent regimes and follow them in persistent regimes, with ATR-based risk and a time stop.",
    "volume_profile_failed_auction": "M5 only, recommended risk 1.0% (1.25% max). During 09:00-11:59 UTC, buy a failed breakdown below the prior day's 80% volume-area low when the prior close was inside value and the rejection closes back inside; fixed 0.5R target, 0.5xATR stop buffer and a 4-hour time stop.",
    "doji_ride": "Doji Ride (Price Action / Pola Candlestick Ekstrem): Fades structural liquidity sweeps at Prior Day High/Low and Asian Session High/Low with Doji absorption wicks and rides immediate momentum breakout (WR 84.0%, DD < 3.0%).",
    "adaptive_selective_entry": "GoldWave-inspired transparent system: Donchian regime + candle body efficiency + ATR volatility gate + daily VWAP rejection + structural dynamic TP + hard SL; no averaging or martingale.",
}


def run_strategy(name: str, candles: List[Candle], params: Params) -> List[Setup]:
    if name not in REGISTRY:
        raise ValueError(f"unknown strategy {name!r}; choices: {list(REGISTRY)}")
    setups = REGISTRY[name](candles, params)
    setups.sort(key=lambda s: s.entry_index)
    return setups
