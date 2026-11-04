"""ORB strategy: hand-checked opening-range breakouts."""
from conftest import series

from sweepbt.params import Params
from sweepbt.strategies.orb import run


def _p(**kw):
    return Params(orb_window=2, rr=2.0, sl_buffer=0.5, **kw)


def test_long_breakout_wins():
    # OR (first 2 candles): hi=13, lo=9. Candle 2 closes 13.5 > 13 -> long.
    # entry=13, sl=9-0.5=8.5, risk=4.5, tp=13+9=22. Resolves from candle 3.
    cs = series([
        (10, 12, 9, 11),    # 0  OR
        (11, 13, 10, 12),   # 1  OR
        (12, 14, 12, 13.5), # 2  close>OR-hi -> long entry @13
        (14, 23, 13, 22),   # 3  high 23 >= tp 22 -> win
    ])
    setups = run(cs, _p())
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "long"
    assert s.strategy == "orb"
    assert s.entry_index == 2
    assert round(s.entry_price, 2) == 13.0
    assert round(s.stop_loss, 2) == 8.5
    assert round(s.take_profit, 2) == 22.0
    assert s.verdict == "win"
    assert s.exit_index == 3


def test_short_breakout_loss_on_tie():
    # OR: hi=21, lo=19. Candle 2 closes 18 < 19 -> short. entry=19,
    # sl=21+0.5=21.5, risk=2.5, tp=19-5=14. Candle 3 spans BOTH tp(14) and
    # sl(21.5) -> pessimistic loss.
    cs = series([
        (20, 21, 19, 20),   # 0 OR
        (20, 21, 19, 20),   # 1 OR
        (19, 19, 17, 18),   # 2 close<OR-lo -> short entry @19
        (15, 22, 13, 16),   # 3 high22>=21.5 sl AND low13<=14 tp -> loss
    ])
    setups = run(cs, _p())
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "short"
    assert round(s.entry_price, 2) == 19.0
    assert round(s.stop_loss, 2) == 21.5
    assert round(s.take_profit, 2) == 14.0
    assert s.verdict == "loss"


def test_one_long_and_one_short_per_day_max():
    cs = series([
        (10, 12, 9, 11),    # 0 OR  hi=13 lo=9
        (11, 13, 10, 12),   # 1 OR
        (12, 14, 12, 13.5), # 2 long
        (13, 14, 13, 13.6), # 3 still > hi but long already taken
        (9, 9, 7, 8),       # 4 close 8 < lo 9 -> short
        (8, 9, 7, 8),       # 5 short already taken
    ])
    setups = run(cs, _p())
    assert sorted(s.direction for s in setups) == ["long", "short"]
