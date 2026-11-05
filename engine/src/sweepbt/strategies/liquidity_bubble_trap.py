"""Liquidity Sweep + Volume Bubble Trap (Bookmap Absorption Strategy):
Exploits institutional absorption and trapped breakout traders at key liquidity swing levels.

Core Mechanics:
1. Liquidity Pool Identification:
   - Tracks swing highs and swing lows using causal pivot detection (swing_strength = 5).
2. Volume Bubble Surge (Bookmap Absorption):
   - Candle volume must surge >= 1.35x of the rolling 20-period average volume, signaling
     heavy aggressive market orders running stops or chasing breakouts.
3. Absorption Rejection Wick:
   - For Bear Trap (Short): Price sweeps above recent swing high, but upper wick is >= 45%
     of candle range and candle closes back inside (<= swing high).
   - For Bull Trap (Long): Price sweeps below recent swing low, but lower wick is >= 45%
     of candle range and candle closes back inside (>= swing low).
4. Trend Alignment (Pullback in Trend):
   - Bear Trap occurs when EMA 20 <= EMA 50 (pullback into resistance within downtrend/neutral).
   - Bull Trap occurs when EMA 20 >= EMA 50 (pullback into support within uptrend/neutral).
5. Active High-Liquidity Window:
   - Focused on London & New York sessions (07:00 - 18:00 UTC).
"""
from __future__ import annotations

from typing import List

from ..models import Candle, Setup
from ..params import Params
from ..simulate import simulate_setup
from ..swings import find_swings
from ..trend import ema


def run(candles: List[Candle], params: Params) -> List[Setup]:
    if not candles or len(candles) < 30:
        return []

    p_strength = params.swing_strength if params.swing_strength and params.swing_strength > 0 else 5
    swings = find_swings(candles, p_strength)
    vols = [c.volume if (c.volume and c.volume > 0) else 1.0 for c in candles]
    closes = [c.close for c in candles]
    ema20 = ema(closes, 20)
    ema50 = ema(closes, 50)
    atrs = [max(c.high - c.low, candles[i - 1].high - candles[i - 1].low) if i > 0 else 1.0 for i, c in enumerate(candles)]

    rr_mult = params.rr if (params.rr and params.rr > 0) else 1.0
    max_risk_cap = params.max_risk if (params.max_risk and params.max_risk > 0) else 4.0
    min_risk_floor = 0.15

    setups: List[Setup] = []

    for i in range(30, len(candles)):
        c = candles[i]

        # London & NY active session (07:00 - 18:00 UTC)
        if c.timestamp and (c.timestamp.hour < 7 or c.timestamp.hour > 18):
            continue

        # Volume Bubble Surge Check (1.35x 20-period average)
        recent_v = vols[i - 20:i]
        avg_v = sum(recent_v) / 20.0
        vol = c.volume if (c.volume and c.volume > 0) else 1.0
        if vol < avg_v * 1.35:
            continue

        c_range = c.high - c.low
        if c_range <= 0.05:
            continue

        atr = atrs[i]
        upper_wick = c.high - max(c.open, c.close)
        lower_wick = min(c.open, c.close) - c.low

        for sw in reversed(swings):
            # Causal verification: swing must be fully formed before current bar
            if sw.index + p_strength > i:
                continue
            # Lookback window: only consider recent swings within 50 bars
            if i - sw.index > 50:
                break

            # 1. Bearish Trap (Short): Sweep Swing High + Absorption Rejection Wick
            if sw.kind == "high" and ema20[i] <= ema50[i]:
                if c.high > sw.price and c.close <= sw.price and (upper_wick / c_range) >= 0.45:
                    sl = c.high + atr * 0.25
                    risk = sl - c.close
                    if min_risk_floor <= risk <= max_risk_cap:
                        tp = c.close - risk * rr_mult
                        s = simulate_setup(
                            candles, "short", i, c.close, sl, tp, params,
                            strategy="liquidity_bubble_trap",
                            trigger_index=i,
                            trigger_level=sw.price,
                            note=f"Bubble Bear Trap Short @ {c.close:.2f} (SwingHigh={sw.price:.2f}, Vol={vol:.0f}/{avg_v:.0f})",
                            resolve_from=i + 1
                        )
                        if s:
                            setups.append(s)
                            break

            # 2. Bullish Trap (Long): Sweep Swing Low + Absorption Rejection Wick
            elif sw.kind == "low" and ema20[i] >= ema50[i]:
                if c.low < sw.price and c.close >= sw.price and (lower_wick / c_range) >= 0.45:
                    sl = c.low - atr * 0.25
                    risk = c.close - sl
                    if min_risk_floor <= risk <= max_risk_cap:
                        tp = c.close + risk * rr_mult
                        s = simulate_setup(
                            candles, "long", i, c.close, sl, tp, params,
                            strategy="liquidity_bubble_trap",
                            trigger_index=i,
                            trigger_level=sw.price,
                            note=f"Bubble Bull Trap Long @ {c.close:.2f} (SwingLow={sw.price:.2f}, Vol={vol:.0f}/{avg_v:.0f})",
                            resolve_from=i + 1
                        )
                        if s:
                            setups.append(s)
                            break

    return setups
