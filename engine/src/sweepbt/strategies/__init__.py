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
    "session_gap": "Gold trades 24/5 across sessions (Asia, London, NY). Fade gaps between "
        "session opens — expect reversion when a new session gaps away from the previous close.",
    "vwap_bounce": "Volume-weighted average price shows the market's true balance. Trade price "
        "bouncing off VWAP: entry at the bounce, stop at 0.5× recent range, target the VWAP level.",
    "gold_session_sweep": "Sweep a configurable rolling high/low, close back inside, then place a limit "
        "entry inside the rejection wick; optional EMA filter and FVG confluence.",
}


def run_strategy(name: str, candles: List[Candle], params: Params) -> List[Setup]:
    if name not in REGISTRY:
        raise ValueError(f"unknown strategy {name!r}; choices: {list(REGISTRY)}")
    setups = REGISTRY[name](candles, params)
    setups.sort(key=lambda s: s.entry_index)
    return setups
