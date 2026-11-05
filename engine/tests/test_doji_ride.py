"""Tests for the Doji Ride strategy."""
from datetime import datetime, timedelta

from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies.doji_ride import run


def _make_day_candles(base_time: datetime, pdh: float, pdl: float, start_idx: int = 0) -> list:
    """Build a day of candles: establishes PDH/PDL."""
    candles = []
    t = base_time
    for i in range(288):
        c_time = t + timedelta(minutes=5 * i)
        mid = (pdh + pdl) / 2.0
        h = pdh if i == 100 else mid + 1.0
        l = pdl if i == 150 else mid - 1.0
        candles.append(Candle(
            index=start_idx + i,
            open=mid,
            high=h,
            low=l,
            close=mid,
            volume=100.0,
            timestamp=c_time
        ))
    return candles


def test_doji_ride_empty_or_short():
    assert run([], Params()) == []
    short_candles = [Candle(i, 2000, 2001, 1999, 2000, 100, 0.0, datetime.now()) for i in range(10)]
    assert run(short_candles, Params()) == []


def test_doji_ride_bullish_sweep():
    # Day 1: Establish PDH=2650.0, PDL=2600.0
    t1 = datetime(2026, 1, 5, 0, 0)
    candles = _make_day_candles(t1, pdh=2650.0, pdl=2600.0, start_idx=0)

    # Day 2: starts at 2026-01-06 00:00
    t2 = datetime(2026, 1, 6, 0, 0)
    idx = len(candles)
    # Asian session: 00:00 to 06:55
    for i in range(84):
        c_time = t2 + timedelta(minutes=5 * i)
        candles.append(Candle(
            index=idx + i,
            open=2620.0,
            high=2625.0,
            low=2615.0,
            close=2620.0,
            volume=100.0,
            timestamp=c_time
        ))

    # At 08:00, price forms a Dragonfly Doji sweeping PDL (2600.0)
    # Range = $4.0, Open=2602.0, Close=2602.1 (body=0.1 <= 0.08*4.0=0.32), High=2603.0, Low=2599.0 (< 2600.0)
    # Lower wick = 2602.0 - 2599.0 = 3.0 (3.0 / 4.0 = 75% >= 50%)
    doji_time = t2 + timedelta(hours=8)
    candles.append(Candle(
        index=len(candles),
        open=2602.0,
        high=2603.0,
        low=2599.0, # Sweeps PDL (2600.0)
        close=2602.1, # Closes above PDL
        volume=150.0,
        timestamp=doji_time
    ))

    # Next candle (08:05): breaks Doji high (2603.0) and reaches target
    next_time = doji_time + timedelta(minutes=5)
    candles.append(Candle(
        index=len(candles),
        open=2602.5,
        high=2607.0, # Breaches 2603.0 and hits TP
        low=2601.5,
        close=2606.0,
        volume=200.0,
        timestamp=next_time
    ))

    # Forward candles to complete walk-forward
    for k in range(2, 30):
        candles.append(Candle(
            index=len(candles),
            open=2606.0,
            high=2608.0,
            low=2604.0,
            close=2607.0,
            volume=100.0,
            timestamp=next_time + timedelta(minutes=5 * k)
        ))

    setups = run(candles, Params(rr=0.40))
    assert len(setups) >= 1
    # Check that any generated setup has valid strategy name and attributes
    for s in setups:
        assert s.strategy == "doji_ride"
        assert s.verdict in ("win", "loss")
        assert s.risk > 0
        assert s.filter_kept is True
