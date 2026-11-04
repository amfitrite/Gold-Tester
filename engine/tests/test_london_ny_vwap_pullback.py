"""Hand-checked tests for the London/NY VWAP trend-pullback strategy."""
from datetime import datetime, timedelta

from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies.london_ny_vwap_pullback import run


def _timestamps(n: int):
    """Two in-session days of M5 timestamps (07:00-17:55 UTC)."""
    out = []
    day = datetime(2026, 10, 5, 7, 0)
    while len(out) < n:
        if 7 <= day.hour < 18:
            out.append(day)
        day += timedelta(minutes=5)
    return out[:n]


def _flat_series(n=204, price=100.0):
    ts = _timestamps(n)
    return [
        Candle(index=i, timestamp=ts[i], open=price, high=price + 0.5,
               low=price - 0.5, close=price, volume=1.0)
        for i in range(n)
    ]


def _replace(candles, index, o, h, l, c):
    old = candles[index]
    candles[index] = Candle(index=index, timestamp=old.timestamp, open=o,
                            high=h, low=l, close=c, volume=old.volume)


def _params(**overrides):
    values = dict(timeframe="M5", rr=1.0, swing_strength=3,
                  min_fvg_size=0.5, sl_buffer=0.0, pullback_window=24)
    values.update(overrides)
    return Params(**values)


def test_long_vwap_reclaim_enters_next_bar_and_hits_target():
    candles = _flat_series()
    _replace(candles, 200, 100.2, 101.0, 99.0, 100.8)   # reclaim signal
    _replace(candles, 201, 100.8, 101.2, 100.4, 101.0)  # entry bar
    _replace(candles, 202, 101.0, 103.0, 100.9, 102.8)  # target

    setups = run(candles, _params())
    assert len(setups) == 1
    s = setups[0]
    assert s.strategy == "london_ny_vwap_pullback"
    assert s.direction == "long"
    assert s.trigger_index == 200
    assert s.entry_index == 201
    assert s.resolve_index == 201
    assert s.exit_index == 202          # TP hit on the follow-through bar
    assert s.verdict == "win"
    assert s.r_multiple > 0
    # Entry includes the modelled half-spread, so it is above the raw open.
    assert round(s.entry_price, 2) == 100.92
    assert s.stop_loss < s.entry_price < s.take_profit


def test_short_vwap_rejection_enters_next_bar_and_hits_target():
    candles = _flat_series()
    _replace(candles, 200, 99.8, 101.0, 99.0, 99.2)     # rejection signal
    _replace(candles, 201, 99.2, 99.5, 98.8, 99.0)      # entry bar
    _replace(candles, 202, 99.0, 99.2, 97.0, 97.2)      # target

    setups = run(candles, _params())
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "short"
    assert s.trigger_index == 200
    assert s.entry_index == 201
    assert s.verdict == "win"
    assert round(s.entry_price, 2) == 99.08
    assert s.stop_loss > s.entry_price > s.take_profit


def test_time_stop_closes_after_24_bars_when_levels_are_not_touched():
    candles = _flat_series(n=230)
    _replace(candles, 200, 100.2, 101.0, 99.0, 100.8)   # reclaim signal
    # Entry bar + 24 hold bars stay comfortably between SL and TP.
    for i in range(201, 226):
        _replace(candles, i, 100.8, 101.0, 100.0, 100.8)

    setups = run(candles, _params())
    assert len(setups) == 1
    s = setups[0]
    assert s.entry_index == 201
    assert s.exit_index == 225          # entry_index + 24
    assert s.verdict in ("win", "loss")


def test_no_signals_outside_london_ny_session():
    candles = _flat_series()
    # Move every timestamp to 18:00 UTC, outside the allowed window.
    shifted = []
    for c in candles:
        ts = c.timestamp.replace(hour=18)
        shifted.append(Candle(index=c.index, timestamp=ts, open=c.open,
                              high=c.high, low=c.low, close=c.close,
                              volume=c.volume))
    _replace(shifted, 200, 100.2, 101.0, 99.0, 100.8)
    _replace(shifted, 201, 100.8, 101.2, 100.4, 101.0)
    _replace(shifted, 202, 101.0, 103.0, 100.9, 102.8)
    assert run(shifted, _params()) == []


def test_no_timestamps_means_no_session_trades():
    candles = [
        Candle(index=i, open=100.0, high=100.5, low=99.5, close=100.0,
               volume=1.0)
        for i in range(220)
    ]
    assert run(candles, _params()) == []
