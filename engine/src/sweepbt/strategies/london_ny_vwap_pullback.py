"""London/NY VWAP trend pullback.

Concept
-------
Gold's most liquid hours (07:00-17:59 UTC) usually produce the cleanest
intraday trends.  The session VWAP is the market's average price for the day;
when price pulls back to it and a candle closes back on the trend side, the
pullback has a high probability of resuming in the direction of the larger
bias.

Rules
-----
1. Bias: close above the 200-EMA = long only, close below = short only.
2. Session: only signals whose candle timestamp is 07:00-17:59 UTC.
3. Long: the candle trades through session VWAP (low <= VWAP), closes back
   above it (close > VWAP), and closes bullish (close > open).
   Short: mirror image (high >= VWAP, close < VWAP, close < open).
4. Enter at the next bar's open.  Stop and target are 1.25 x ATR(14) from the
   entry, i.e. a 1:1 reward/risk trade.  Close at the close after 24 bars
   (2 hours on M5) if neither level was touched.
5. Only one position at a time.

The fixed 1:1 target is intentional: it keeps the win rate and equity curve
smooth, which is the opposite of the usual "small wins, rare huge losses"
profile.  A small half-spread cost is charged to every fill so the backtest
does not rely on perfect execution.

This strategy is self-filtered (EMA-200 + session + VWAP), so the generic
EMA-20/50 trend filter in ``engine.run`` is deliberately skipped for it.
"""
from __future__ import annotations

from typing import List, Optional

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_time_exit
from ..trend import ema

STRATEGY_NAME = "london_ny_vwap_pullback"
SESSION_START_HOUR = 7          # inclusive, UTC
SESSION_END_HOUR = 17           # inclusive, UTC
EMA_PERIOD = 200
ATR_PERIOD = 14
SL_ATR = 1.25
TP_ATR = 1.25
MAX_HOLD_BARS = 24              # 2 hours on M5
HALF_SPREAD = 0.12              # $0.12 per side on XAUUSD


def _atr(candles: List[Candle], period: int = ATR_PERIOD) -> List[Optional[float]]:
    """Wilder ATR, causal and ``None`` until the first full window."""
    n = len(candles)
    if n < period + 1:
        return [None] * n

    trs: List[Optional[float]] = [None] * n
    for i in range(1, n):
        c, prev = candles[i], candles[i - 1]
        trs[i] = max(c.high - c.low, abs(c.high - prev.close),
                     abs(c.low - prev.close))

    atr: List[Optional[float]] = [None] * n
    atr[period] = sum(trs[1:period + 1]) / period
    for i in range(period + 1, n):
        atr[i] = (atr[i - 1] * (period - 1) + trs[i]) / period
    return atr


def _session_vwap(candles: List[Candle]) -> List[Optional[float]]:
    """Cumulative VWAP, reset at each UTC date boundary."""
    out: List[Optional[float]] = [None] * len(candles)
    current_day = object()
    pv = 0.0
    vol = 0.0
    for i, c in enumerate(candles):
        day = c.timestamp.date() if c.timestamp is not None else None
        if day != current_day:
            current_day = day
            pv = 0.0
            vol = 0.0
        typical = (c.high + c.low + c.close) / 3.0
        weight = c.volume if c.volume and c.volume > 0 else 1.0
        pv += typical * weight
        vol += weight
        out[i] = pv / vol if vol > 0 else typical
    return out


def _in_session(candle: Candle) -> bool:
    if candle.timestamp is None:
        return False
    return SESSION_START_HOUR <= candle.timestamp.hour <= SESSION_END_HOUR


def run(candles: List[Candle], params: Params) -> List[Setup]:
    """Generate non-overlapping session-VWAP pullback setups."""
    if len(candles) < EMA_PERIOD + 2:
        return []

    closes = [c.close for c in candles]
    ema200 = ema(closes, EMA_PERIOD)
    atr = _atr(candles)
    vwap = _session_vwap(candles)

    setups: List[Setup] = []
    busy_until = -1

    for i in range(EMA_PERIOD, len(candles) - 1):
        if i < busy_until:
            continue
        candle = candles[i]
        if not _in_session(candle):
            continue

        v, a, bias = vwap[i], atr[i], ema200[i]
        if v is None or a is None or a <= 0 or bias is None:
            continue

        long_signal = (
            candle.low <= v
            and candle.close > v
            and candle.close > candle.open
            and candle.close > bias
        )
        short_signal = (
            candle.high >= v
            and candle.close < v
            and candle.close < candle.open
            and candle.close < bias
        )
        if long_signal == short_signal:      # no signal, or both (ambiguous)
            continue

        direction = "long" if long_signal else "short"
        entry_index = i + 1
        raw_entry = candles[entry_index].open
        entry = (raw_entry + HALF_SPREAD if direction == "long"
                 else raw_entry - HALF_SPREAD)
        if direction == "long":
            sl = entry - SL_ATR * a
            tp = entry + TP_ATR * a
        else:
            sl = entry + SL_ATR * a
            tp = entry - TP_ATR * a

        setup = simulate_time_exit(
            candles, entry_index, direction, entry, sl, tp,
            MAX_HOLD_BARS, params,
            strategy=STRATEGY_NAME,
            trigger_index=i,
            trigger_level=round(v, 5),
            note=(f"{'Long' if direction == 'long' else 'Short'} VWAP reclaim "
                  f"@ {v:.2f} (EMA200={bias:.2f}, ATR={a:.2f})"),
            resolve_from=entry_index,
            half_spread=HALF_SPREAD,
        )
        if setup is None:
            continue
        setups.append(setup)
        busy_until = setup.exit_index if setup.exit_index is not None else entry_index

    setups.sort(key=lambda s: s.entry_index)
    return setups
