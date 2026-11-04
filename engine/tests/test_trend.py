from conftest import series
from sweepbt.models import Setup, Sweep, Zone
from sweepbt.params import Params
from sweepbt.trend import ema, ema_bias, apply_trend_filter


def test_ema_basic():
    assert ema([1, 1, 1, 1], 3) == [1, 1, 1, 1]
    out = ema([1, 2, 3, 4], 3)          # k = 0.5
    assert out[0] == 1 and round(out[1], 3) == 1.5 and round(out[2], 3) == 2.25


def test_ema_bias_up_and_down():
    up = series([(i, i + 1, i - 1, i + 0.9) for i in range(1, 60)])
    bias = ema_bias(up, 20, 50)
    assert bias[-1] == "long"
    down = series([(60 - i, 61 - i, 59 - i, 60 - i - 0.9) for i in range(1, 60)])
    bias = ema_bias(down, 20, 50)
    assert bias[-1] == "short"


def _fake_setup(direction, idx):
    z = Zone("OB", top=10, bottom=9, start_index=idx, end_index=idx)
    sw = Sweep(index=idx, level=9, swing_index=0,
               side="buy" if direction == "long" else "sell", wick=9)
    return Setup(direction=direction, sweep=sw, zone=z, entry_index=idx,
                 entry_price=10, stop_loss=8, take_profit=14, risk=2, verdict="win", r_multiple=2)


def test_filter_keeps_aligned_skips_counter_trend():
    # uptrend series; a long at the end is aligned, a short is counter-trend
    up = series([(i, i + 1, i - 1, i + 0.9) for i in range(1, 60)])
    long_s, short_s = _fake_setup("long", 58), _fake_setup("short", 58)
    apply_trend_filter([long_s, short_s], up, Params(trend_method="ema"))
    assert long_s.filter_kept is True
    assert short_s.filter_kept is False
