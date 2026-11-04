from conftest import series
from sweepbt.models import Sweep
from sweepbt.imbalance import find_fvgs, find_order_block, select_zone


def test_bullish_fvg():
    rows = [(9, 10, 8, 9), (10, 13, 9, 12), (12, 14, 12, 13)]  # c1.high=10, c3.low=12
    fvgs = find_fvgs(series(rows), min_size=1.0)
    assert len(fvgs) == 1
    zone, direction = fvgs[0]
    assert direction == "long" and zone.kind == "FVG"
    assert zone.bottom == 10 and zone.top == 12 and (zone.start_index, zone.end_index) == (0, 2)


def test_bearish_fvg():
    rows = [(21, 22, 20, 21), (20, 21, 16, 18), (17, 17, 15, 16)]  # c1.low=20, c3.high=17
    fvgs = find_fvgs(series(rows), min_size=1.0)
    assert len(fvgs) == 1
    zone, direction = fvgs[0]
    assert direction == "short" and zone.top == 20 and zone.bottom == 17


def test_fvg_min_size_is_strict():
    rows = [(9, 10, 8, 9), (10, 11, 9, 10), (11, 12, 11, 11.5)]  # gap exactly 1.0
    assert find_fvgs(series(rows), min_size=1.0) == []
    assert len(find_fvgs(series(rows), min_size=0.5)) == 1


def test_bullish_order_block():
    rows = [
        (10, 10.2, 9.8, 10),
        (10, 10.5, 9, 9.5),     # bearish
        (9.5, 10, 9, 9.2),      # bearish  <- this is the OB
        (9.2, 11, 9.1, 10.8),   # bullish impulse
    ]
    sweep = Sweep(index=2, level=9.0, swing_index=0, side="buy", wick=9.0)
    z = find_order_block(series(rows), sweep, lookahead=3)
    assert z is not None and z.kind == "OB"
    assert z.top == 10 and z.bottom == 9 and z.start_index == 2


def test_bearish_order_block():
    rows = [
        (9, 9.2, 8.8, 9),
        (9, 10, 8.9, 9.8),      # bullish
        (9.8, 10.2, 9.5, 10),   # bullish  <- OB
        (10, 10.1, 8.5, 8.7),   # bearish impulse
    ]
    sweep = Sweep(index=2, level=10.2, swing_index=0, side="sell", wick=10.2)
    z = find_order_block(series(rows), sweep, lookahead=3)
    assert z is not None and z.top == 10.2 and z.bottom == 9.5 and z.start_index == 2


def test_select_zone_prefers_ob_over_fvg():
    # OB present -> chosen even though an FVG also exists later
    rows = [
        (10, 10.2, 9.8, 10),
        (9.5, 10, 9, 9.2),      # bearish OB
        (9.2, 11, 9.1, 10.8),   # bullish impulse (also c1 of an FVG)
        (10.8, 12, 10.7, 11.5),
        (12, 13, 11.5, 12.5),   # c3.low 11.5 > c1.high 11 -> FVG too
    ]
    sweep = Sweep(index=1, level=9.0, swing_index=0, side="buy", wick=9.0)
    z = select_zone(series(rows), sweep, ob_lookahead=3, fvg_lookahead=4, min_fvg_size=0.3)
    assert z.kind == "OB"
