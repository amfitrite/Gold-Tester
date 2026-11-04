from conftest import series
from sweepbt.swings import find_swings
from sweepbt.sweeps import find_sweeps


def test_sell_side_sweep_wick_above_close_back():
    rows = [
        (8, 10, 7, 9),
        (9, 12, 8, 11),    # swing high = 12
        (10, 11, 9, 10),
        (10, 13, 9, 11),   # high 13 > 12, close 11 < 12  -> sell-side sweep
    ]
    cs = series(rows)
    sweeps = find_sweeps(cs, find_swings(cs, strength=1))
    assert len(sweeps) == 1
    s = sweeps[0]
    assert s.index == 3 and s.side == "sell" and s.level == 12 and s.direction == "short"
    assert s.wick == 13


def test_buy_side_sweep_wick_below_close_back():
    rows = [
        (10, 11, 9, 10),
        (9, 10, 5, 8),     # swing low = 5
        (8, 9, 7, 8),
        (8, 9, 4, 7),      # low 4 < 5, close 7 > 5 -> buy-side sweep
    ]
    cs = series(rows)
    sweeps = find_sweeps(cs, find_swings(cs, strength=1))
    assert len(sweeps) == 1
    s = sweeps[0]
    assert s.index == 3 and s.side == "buy" and s.level == 5 and s.direction == "long"
    assert s.wick == 4


def test_close_beyond_level_is_a_break_not_a_sweep():
    rows = [
        (8, 10, 7, 9),
        (9, 12, 8, 11),    # swing high = 12
        (10, 11, 9, 10),
        (10, 13, 9, 12.5), # closes ABOVE 12 -> break, not a sweep
    ]
    cs = series(rows)
    assert find_sweeps(cs, find_swings(cs, strength=1)) == []


def test_only_first_sweep_of_a_level_is_taken():
    rows = [
        (8, 10, 7, 9),
        (9, 12, 8, 11),    # swing high = 12
        (10, 11, 9, 10),
        (10, 13, 9, 11),   # first sweep
        (10, 13, 9, 11),   # would sweep again - ignored
    ]
    cs = series(rows)
    sweeps = find_sweeps(cs, find_swings(cs, strength=1))
    assert len(sweeps) == 1 and sweeps[0].index == 3
