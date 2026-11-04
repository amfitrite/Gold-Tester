"""Strategy 1: liquidity sweep -> imbalance -> reversal entry (the original)."""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..swings import find_swings
from ..sweeps import find_sweeps
from ..simulate import build_setups


def run(candles: List[Candle], params: Params) -> List[Setup]:
    swings = find_swings(candles, params.swing_strength)
    sweeps = find_sweeps(candles, swings)
    return build_setups(candles, sweeps, params)
