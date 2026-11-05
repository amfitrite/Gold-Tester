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
from .session_gap import run as _sg
from .vwap_bounce import run as _vwap
from .gold_session_sweep import run as _gold_session_sweep
from .adaptive_selective_entry import run as _ase

StrategyFn = Callable[[List[Candle], Params], List[Setup]]

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
    "session_gap": _sg,
    "vwap_bounce": _vwap,
    "gold_session_sweep": _gold_session_sweep,
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
    "bollinger_bands": "Bollinger Bands Mean Reversion",
    "session_gap": "Session Gap Fade",
    "vwap_bounce": "VWAP Bounce",
    "gold_session_sweep": "Gold Rolling Liquidity Sweep + 50% Rejection Retest",
    "adaptive_selective_entry": "Adaptive Selective Entry (GoldWave-inspired)",
}

DESCRIPTIONS = {
    "liquidity_imbalance": "Wait for a swing high/low to be swept, then enter the reversal off the order block / FVG.",
    "prev_day_breakout": "Trade the first close beyond the prior day's high or low.",
    "orb": "Mark the opening range, then trade the first close that breaks out.",
    "rsi_reversal": "Fade exhaustion as RSI snaps back out of an extreme.",
    "support_resistance": "Buy support bounces and sell resistance rejections.",
    "momentum_breakout": "Trade an expansion candle that closes beyond the recent range.",
    "momentum_pullback": "Trade a pullback with the moving-average trend.",
    "ict_fvg": "Trade the first pullback that fills a three-candle fair-value gap.",
    "ict_ifvg": "Trade a retest after an FVG flips polarity.",
    "ict_order_block": "Enter the retrace into the order block behind a structure break.",
    "smart_money": "Sweep, change of character, then order-block entry.",
    "supply_demand": "Trade the first return into a base after a strong departure.",
    "order_flow": "Detect high-volume rejection and enter after directional confirmation.",
    "bollinger_bands": "Trade mean reversion from an outer band toward the middle.",
    "session_gap": "Fade gaps around configured session transitions.",
    "vwap_bounce": "Trade price reclaiming or rejecting cumulative VWAP.",
    "gold_session_sweep": "Sweep a rolling high/low, close back inside, then enter a rejection-wick retrace.",
    "adaptive_selective_entry": "Classify Donchian regime, filter by ATR and candle-body efficiency, then trade VWAP trend reclaims or rolling Value Area edge rejections with a structural target and hard stop.",
}


def run_strategy(name: str, candles: List[Candle], params: Params) -> List[Setup]:
    if name not in REGISTRY:
        raise ValueError(f"unknown strategy {name!r}; choices: {list(REGISTRY)}")
    setups = REGISTRY[name](candles, params)
    setups.sort(key=lambda s: s.entry_index)
    return setups
