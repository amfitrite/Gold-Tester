"""Previous-day high/low breakout: hand-checked over two timestamped days."""
from datetime import datetime

from sweepbt.models import Candle
from sweepbt.params import Params
from sweepbt.strategies.prev_day_breakout import run


def _c(o, h, l, c, i, day):
    return Candle(index=i, open=o, high=h, low=l, close=c,
                  timestamp=datetime(2026, 1, day, 9 + i % 6, 0))


def test_long_breaks_prev_day_high():
    # Day 1 -> PDH=13, PDL=8. Day 2 candle closes 13.5 > 13 -> long.
    # entry=PDH=13, sl=candle.low(11)-0.5=10.5, risk=2.5, tp=13+5=18.
    cs = [
        _c(10, 12, 8, 11, 0, 1),
        _c(11, 13, 9, 12, 1, 1),
        _c(12, 14, 11, 13.5, 2, 2),   # long entry @13
        _c(14, 19, 13, 18, 3, 2),     # high 19 >= tp 18 -> win
    ]
    setups = run(cs, Params(rr=2.0, sl_buffer=0.5))
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "long"
    assert s.strategy == "prev_day_breakout"
    assert round(s.entry_price, 2) == 13.0
    assert round(s.stop_loss, 2) == 10.5
    assert round(s.take_profit, 2) == 18.0
    assert s.verdict == "win"


def test_short_breaks_prev_day_low():
    # Day 1 -> PDH=21, PDL=18. Day 2 closes 17 < 18 -> short.
    # entry=18, sl=candle.high(19)+0.5=19.5, risk=1.5, tp=18-3=15.
    cs = [
        _c(20, 21, 19, 20, 0, 1),
        _c(20, 21, 18, 19, 1, 1),
        _c(19, 19, 16, 17, 2, 2),     # short entry @18
        _c(16, 16, 14, 15, 3, 2),     # low 14 <= tp 15 -> win
    ]
    setups = run(cs, Params(rr=2.0, sl_buffer=0.5))
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "short"
    assert round(s.entry_price, 2) == 18.0
    assert round(s.stop_loss, 2) == 19.5
    assert round(s.take_profit, 2) == 15.0
    assert s.verdict == "win"


def test_first_day_has_no_reference_so_no_setups():
    cs = [_c(10, 12, 8, 11, 0, 1), _c(11, 13, 9, 12, 1, 1)]
    assert run(cs, Params()) == []
