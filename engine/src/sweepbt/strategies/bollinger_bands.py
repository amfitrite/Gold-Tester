"""Bollinger Bands Mean Reversion (Trend & Volatility Optimized).

Upgraded with EMA 20/50 trend confluence and volatility stop buffering.
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from .bollinger_bands_2 import run as run_v2


def run(candles: List[Candle], params: Params) -> List[Setup]:
    # Route through the optimized trend-aligned engine
    return run_v2(candles, params)
