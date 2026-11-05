"""Hand-checked tests for the prior-day volume-profile failed-auction strategy."""
from datetime import datetime, timedelta

from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies import SELF_FILTERED
from sweepbt.strategies.volume_profile_failed_auction import (
    MAX_HOLD_BARS,
    TARGET_RR,
    _build_profile,
    run,
)


def _flat_bar(index: int, ts: datetime, price: float, volume: float = 1.0,
              spread: float = 0.5) -> Candle:
    return Candle(index=index, timestamp=ts, open=price,
                  high=price + spread, low=price - spread,
                  close=price, volume=volume)


def _profile_day(day: datetime, start_hour: int = 9) -> list[Candle]:
    """A prior day whose profile is POC=110, VAL=105, VAH=115.

    The last close is 107, i.e. inside the value area, so the next day's
    prior-close filter is satisfied.
    """
    out: list[Candle] = []
    ts = day.replace(hour=start_hour, minute=0, second=0, microsecond=0)
    # 12 bars at 105, 12 at 110 (2.5 volume each), 11 at 115, then a final
    # 107 bar.  The 80% value area is [105, 115] and POC is 110.
    for price, volume in ([(105.0, 1.0)] * 12
                          + [(110.0, 2.5)] * 12
                          + [(115.0, 1.0)] * 11
                          + [(107.0, 0.1)]):
        out.append(_flat_bar(len(out), ts, price, volume))
        ts += timedelta(minutes=5)
    return out


def _day_with_signal(day: datetime, signal_hour: int = 9,
                     signal_minute: int = 5) -> list[Candle]:
    # Flat bars from 08:00 to 14:00; the signal bar is replaced below.
    out: list[Candle] = []
    ts = day.replace(hour=8, minute=0, second=0, microsecond=0)
    while ts.hour < 14:
        out.append(_flat_bar(len(out), ts, 108.0, 1.0))
        ts += timedelta(minutes=5)

    signal_ts = day.replace(hour=signal_hour, minute=signal_minute,
                            second=0, microsecond=0)
    signal_idx = next(i for i, c in enumerate(out) if c.timestamp == signal_ts)
    out[signal_idx] = Candle(
        index=signal_idx, timestamp=signal_ts,
        open=106.0, high=109.0, low=100.0, close=108.0, volume=1.0,
    )
    # Entry is the next bar; the bar after that reaches the 0.5R target.
    follow_idx = signal_idx + 2
    if follow_idx < len(out):
        follow_ts = out[follow_idx].timestamp
        out[follow_idx] = Candle(
            index=follow_idx, timestamp=follow_ts,
            open=108.0, high=113.0, low=108.0, close=112.0, volume=1.0,
        )
    return out


def _day_with_short_signal(day: datetime, signal_hour: int = 9,
                           signal_minute: int = 5) -> list[Candle]:
    """A failed rally above VAH, then a lower entry bar that reaches the target."""
    out: list[Candle] = []
    ts = day.replace(hour=8, minute=0, second=0, microsecond=0)
    while ts.hour < 14:
        out.append(_flat_bar(len(out), ts, 108.0, 1.0))
        ts += timedelta(minutes=5)

    signal_ts = day.replace(hour=signal_hour, minute=signal_minute,
                            second=0, microsecond=0)
    signal_idx = next(i for i, c in enumerate(out) if c.timestamp == signal_ts)
    out[signal_idx] = Candle(
        index=signal_idx, timestamp=signal_ts,
        open=118.0, high=120.0, low=111.0, close=112.0, volume=1.0,
    )
    entry_idx = signal_idx + 1
    old = out[entry_idx]
    out[entry_idx] = Candle(
        index=entry_idx, timestamp=old.timestamp,
        open=112.0, high=112.5, low=110.0, close=111.0, volume=1.0,
    )
    follow_idx = signal_idx + 2
    if follow_idx < len(out):
        follow_ts = out[follow_idx].timestamp
        out[follow_idx] = Candle(
            index=follow_idx, timestamp=follow_ts,
            open=111.0, high=111.0, low=105.0, close=106.0, volume=1.0,
        )
    return out


def _series(signal_hour: int = 9, signal_minute: int = 5,
            sunday: bool = False) -> list[Candle]:
    friday = datetime(2026, 10, 2)
    day = datetime(2026, 10, 4) if sunday else datetime(2026, 10, 5)
    candles = _profile_day(friday) + _day_with_signal(
        day, signal_hour=signal_hour, signal_minute=signal_minute)
    for i, c in enumerate(candles):
        if c.index != i:
            candles[i] = Candle(index=i, timestamp=c.timestamp, open=c.open,
                               high=c.high, low=c.low, close=c.close,
                               volume=c.volume)
    return candles


def _short_series(signal_hour: int = 9, signal_minute: int = 5,
                  sunday: bool = False) -> list[Candle]:
    friday = datetime(2026, 10, 2)
    day = datetime(2026, 10, 4) if sunday else datetime(2026, 10, 5)
    candles = _profile_day(friday) + _day_with_short_signal(
        day, signal_hour=signal_hour, signal_minute=signal_minute)
    for i, c in enumerate(candles):
        if c.index != i:
            candles[i] = Candle(index=i, timestamp=c.timestamp, open=c.open,
                               high=c.high, low=c.low, close=c.close,
                               volume=c.volume)
    return candles


def _params() -> Params:
    return Params(timeframe="M5", rr=TARGET_RR, swing_strength=3,
                  min_fvg_size=0.5, sl_buffer=0.0, pullback_window=16)


def test_prior_day_profile_levels_are_hand_checked():
    candles = _profile_day(datetime(2026, 10, 2))
    assert _build_profile(candles, list(range(len(candles)))) == (
        110.0, 105.0, 115.0
    )


def test_long_failed_auction_enters_next_bar_and_hits_half_r_target():
    candles = _series()
    setups = run(candles, _params())
    assert len(setups) == 1
    s = setups[0]
    assert s.strategy == "volume_profile_failed_auction"
    assert s.direction == "long"
    assert s.trigger_index == 49          # Monday 09:05, after the Friday profile
    assert s.entry_index == 50             # next M5 bar (09:10)
    assert s.resolve_index == 50
    assert s.verdict == "win"
    assert s.exit_index == 51              # 09:15 bar reaches TP
    assert s.trigger_level == 105.0        # prior VAL, not a current-day level
    assert round(s.entry_price, 2) == 108.12
    risk = s.take_profit - s.entry_price
    assert abs(risk / (s.entry_price - s.stop_loss) - TARGET_RR) < 1e-12
    assert s.stop_loss < s.entry_price < s.take_profit
    assert s.r_multiple > 0


def test_short_failed_auction_enters_next_bar_and_hits_half_r_target():
    setups = run(_short_series(), _params())
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "short"
    assert s.trigger_index == 49          # Monday 09:05, after the Friday profile
    assert s.entry_index == 50             # next M5 bar (09:10)
    assert s.resolve_index == 50
    assert s.verdict == "win"
    assert s.exit_index == 51              # 09:15 bar reaches TP
    assert s.trigger_level == 115.0        # prior VAH
    assert round(s.entry_price, 2) == 111.88
    risk = s.entry_price - s.take_profit
    assert abs(risk / (s.stop_loss - s.entry_price) - TARGET_RR) < 1e-12
    assert s.take_profit < s.entry_price < s.stop_loss
    assert s.r_multiple > 0


def test_no_signal_outside_london_morning():
    # The signal bars are valid failed auctions but are outside 09:00-11:59.
    assert run(_series(signal_hour=12, signal_minute=5), _params()) == []
    assert run(_series(signal_hour=8, signal_minute=55), _params()) == []
    assert run(_short_series(signal_hour=12, signal_minute=5), _params()) == []
    assert run(_short_series(signal_hour=8, signal_minute=55), _params()) == []


def test_sunday_bars_are_ignored():
    assert run(_series(sunday=True), _params()) == []


def test_current_day_volume_does_not_change_the_prior_day_profile():
    candles = _series()
    # 08:00 on the signal day.  A current-day profile would put almost all
    # volume in the 110 bin and make the setup impossible; the prior-day
    # profile must ignore it.
    old = candles[36]
    candles[36] = Candle(index=36, timestamp=old.timestamp, open=108.0,
                         high=108.5, low=107.5, close=108.0, volume=1e9)
    setups = run(candles, _params())
    assert len(setups) == 1
    assert setups[0].trigger_level == 105.0


def test_prior_close_outside_value_area_blocks_the_signal():
    candles = _series()
    old = candles[48]  # Monday 09:00, the bar immediately before the signal
    candles[48] = Candle(index=48, timestamp=old.timestamp, open=100.5,
                         high=101.0, low=99.5, close=100.0, volume=0.1)
    assert run(candles, _params()) == []


def test_time_stop_closes_after_48_bars_when_levels_are_not_touched():
    candles = _series()
    # Replace every bar from 09:10 onward with a tight flat range between SL/TP.
    for i in range(50, len(candles)):
        old = candles[i]
        candles[i] = Candle(index=i, timestamp=old.timestamp, open=108.0,
                            high=108.5, low=107.5, close=108.0, volume=1.0)
    setups = run(candles, _params())
    assert len(setups) == 1
    s = setups[0]
    assert s.entry_index == 50
    assert s.exit_index == 50 + MAX_HOLD_BARS
    assert s.verdict in ("win", "loss")


def test_no_timestamps_means_no_trades():
    candles = [
        Candle(index=i, open=108.0, high=108.5, low=107.5, close=108.0,
               volume=1.0)
        for i in range(120)
    ]
    assert run(candles, _params()) == []


def test_strategy_is_registered_as_self_filtered():
    assert "volume_profile_failed_auction" in SELF_FILTERED
