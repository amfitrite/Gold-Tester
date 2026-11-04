from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies.gold_session_sweep import run


def _series(rows):
    return [
        Candle(index=i, open=o, high=h, low=l, close=c, timestamp=None)
        for i, (o, h, l, c) in enumerate(rows)
    ]


def _sweep_series():
    # First 24 candles establish a tight rolling range: 99.80-100.20.
    rows = [(100.0, 100.2, 99.8, 100.0)] * 24

    # Bar 24 sweeps the prior high and closes back inside with bearish rejection.
    rows.append((100.3, 100.7, 99.9, 100.0))
    # Bar 25 retests the sweep candle's 50% level and closes back below it.
    rows.append((100.2, 100.4, 100.1, 100.2))
    # Bar 26 reaches the 2R target.
    rows.append((99.3, 99.4, 99.0, 99.1))
    return _series(rows)


def _params(**overrides):
    values = dict(
        timeframe="M5",
        swing_strength=3,  # lookback = 24 candles
        rr=2.0,
        min_fvg_size=0.5,  # FVG is optional
        sl_buffer=0.1,
        pullback_window=8,
    )
    values.update(overrides)
    return Params(**values)


def test_gold_rolling_sweep_generates_short_without_timestamps_or_fvg():
    setups = run(_sweep_series(), _params())

    assert len(setups) == 1
    setup = setups[0]
    assert setup.strategy == "gold_session_sweep"
    assert setup.direction == "short"
    assert setup.trigger_index == 24
    assert setup.entry_index == 25
    assert setup.verdict == "win"
    assert setup.r_multiple == 2.0
    assert setup.zone is None


def test_gold_rolling_sweep_does_not_trade_flat_data():
    candles = _series([(100.0, 100.2, 99.8, 100.0)] * 100)
    assert run(candles, _params()) == []


def test_gold_rolling_sweep_requires_later_retest():
    assert run(_sweep_series(), _params(pullback_window=0)) == []
