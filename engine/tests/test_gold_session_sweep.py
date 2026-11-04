from datetime import datetime, timedelta

from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies.gold_session_sweep import run


def _candle(index, timestamp, o, h, l, c):
    return Candle(index=index, timestamp=timestamp, open=o, high=h, low=l, close=c)


def _sample_short_day():
    start = datetime(2026, 10, 5, 0, 0)
    candles = []
    # Asia range: 00:00-06:55 UTC, high=100.20 and low=99.80.
    for i in range(84):
        candles.append(_candle(
            i, start + timedelta(minutes=5 * i),
            100.0, 100.2, 99.8, 100.0
        ))

    # 07:00: sweep Asia high, then close back inside the range.
    rows = [
        (100.1, 100.7, 99.8, 100.1),   # sweep high
        (100.15, 100.3, 100.0, 100.2), # no displacement yet
        (99.65, 99.7, 99.0, 99.05),    # bearish displacement + FVG
        (99.5, 99.7, 99.1, 99.2),      # later rejection retest at 50% displacement
        (96.2, 96.4, 96.0, 96.1),      # hits 2R target
    ]
    for offset, row in enumerate(rows, start=84):
        candles.append(_candle(
            offset, start + timedelta(minutes=5 * offset), *row
        ))
    return candles


def _params(**overrides):
    values = dict(
        timeframe="M5",
        rr=2.0,
        min_fvg_size=0.05,
        sl_buffer=0.1,
        pullback_window=8,
    )
    values.update(overrides)
    return Params(**values)


def test_gold_session_sweep_waits_for_retest_and_resolves_win():
    setups = run(_sample_short_day(), _params())

    assert len(setups) == 1
    setup = setups[0]
    assert setup.strategy == "gold_session_sweep"
    assert setup.direction == "short"
    assert setup.entry_index == 87  # strictly after displacement at index 86
    assert setup.trigger_index == 84
    assert setup.verdict == "win"
    assert setup.r_multiple == 2.0
    assert setup.zone is not None and setup.zone.kind == "FVG"


def test_gold_session_sweep_requires_utc_timestamps():
    candles = [
        Candle(index=i, open=100.0, high=100.2, low=99.8, close=100.0)
        for i in range(100)
    ]
    assert run(candles, _params()) == []


def test_gold_session_sweep_respects_pullback_window():
    # A zero-bar window cannot enter on the displacement candle itself.
    assert run(_sample_short_day(), _params(pullback_window=0)) == []
