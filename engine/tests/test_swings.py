from conftest import series
from sweepbt.swings import find_swings


# highs = 10,12, 9,14, 8 ; lows = 5,7, 3,9, 4
ROWS = [
    (8, 10, 5, 9),
    (9, 12, 7, 11),
    (7, 9, 3, 5),
    (10, 14, 9, 12),
    (6, 8, 4, 7),
]


def test_swings_strength_1():
    sw = find_swings(series(ROWS), strength=1)
    got = {(s.index, s.kind) for s in sw}
    assert got == {(1, "high"), (2, "low"), (3, "high")}
    # liquidity side mapping
    high = next(s for s in sw if s.index == 1)
    assert high.side == "sell" and high.price == 12
    low = next(s for s in sw if s.index == 2)
    assert low.side == "buy" and low.price == 3


def test_swings_strength_2_needs_neighbours_both_sides():
    sw = find_swings(series(ROWS), strength=2)
    # only index 2 has 2 neighbours each side; it's a strict swing low
    assert [(s.index, s.kind) for s in sw] == [(2, "low")]


def test_strict_inequality_no_ties():
    # equal highs -> not a strict swing
    rows = [(1, 10, 1, 5), (1, 10, 1, 5), (1, 10, 1, 5)]
    assert find_swings(series(rows), strength=1) == []
