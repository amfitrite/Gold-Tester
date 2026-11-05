from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies.adaptive_selective_entry import run, _value_area


def _candles(rows):
    return [Candle(index=i, open=o, high=h, low=l, close=c, volume=v)
            for i, (o, h, l, c, v) in enumerate(rows)]


def test_ase_does_not_trade_flat_market():
    candles = _candles([(100.0, 100.2, 99.8, 100.0, 100.0)] * 160)
    assert run(candles, Params.for_timeframe("M5")) == []


def test_ase_value_area_uses_only_completed_reference_bars():
    rows = [(100.0, 100.2, 99.8, 100.0, 100.0)] * 20
    rows.append((110.0, 111.0, 109.0, 110.0, 10000.0))
    candles = _candles(rows)
    profile = _value_area(candles, 20, 20, 0.5, 0.70)
    assert profile is not None
    poc, val, vah = profile
    assert 99.0 <= val <= poc <= vah <= 101.0


def test_ase_respects_atr_regime_filter_and_returns_valid_setups():
    # A broad, gently oscillating sample gives the indicators enough warm-up.
    rows = []
    for i in range(180):
        center = 2000.0 + (0.015 * i)
        wave = 1.4 if i % 2 == 0 else -1.4
        o = center - wave * 0.25
        c = center + wave * 0.25
        rows.append((o, max(o, c) + 0.8, min(o, c) - 0.8, c, 100 + (i % 7) * 5))
    candles = _candles(rows)
    params = Params.for_timeframe(
        "M5",
        ase_atr_min_ratio=0.0,
        ase_atr_max_ratio=10.0,
        ase_min_channel_width_atr=0.0,
        ase_min_body_efficiency=0.0,
    )
    setups = run(candles, params)
    for setup in setups:
        assert setup.strategy == "adaptive_selective_entry"
        assert setup.risk > 0
        if setup.direction == "long":
            assert setup.stop_loss < setup.entry_price < setup.take_profit
        else:
            assert setup.take_profit < setup.entry_price < setup.stop_loss
