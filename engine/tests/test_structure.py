"""Structure markings: BOS/CHoCH, S/R clustering, inverse FVG, breakers."""
from conftest import series

from sweepbt.models import Swing
from sweepbt.swings import find_swings
from sweepbt.imbalance import find_fvgs
from sweepbt.structure import (find_structure_events, support_resistance,
                               inverse_fvgs, find_breakers)


def test_first_break_is_choch_then_bos():
    # strength=1. Index 1 is a strict swing high (15). A later candle closes
    # above it: the first up-break flips trend (CHoCH).
    cs = series([
        (10, 11, 9, 10),
        (10, 15, 9, 14),    # swing high @15
        (13, 14, 12, 13),
        (14, 17, 14, 16),   # CHoCH up @15
        (12, 13, 11, 12),   # pullback, forms a new swing low region
        (12, 20, 11, 19),   # closes above prior high again -> BOS up
    ])
    swings = find_swings(cs, strength=1)
    assert any(s.kind == "high" and s.price == 15 for s in swings)
    events = find_structure_events(cs, swings, strength=1)
    ups = [e for e in events if e.direction == "up"]
    assert ups, "expected at least one up break"
    assert ups[0].kind == "CHoCH"
    assert ups[0].level == 15


def test_support_resistance_clusters_within_tolerance():
    swings = [
        Swing(index=0, price=10.0, kind="low"),
        Swing(index=1, price=10.4, kind="low"),   # within tol of 10.0
        Swing(index=2, price=20.0, kind="high"),  # lonely -> dropped (<2 touches)
    ]
    zones = support_resistance(swings, tolerance=1.0)
    assert len(zones) == 1
    z = zones[0]
    assert z["touches"] == 2
    assert round(z["price"], 2) == 10.2
    assert z["lo"] == 10.0 and z["hi"] == 10.4


def test_inverse_fvg_flips_when_closed_through():
    # Bullish (long) FVG: low[2] > high[0]. Then a later candle closes below the
    # gap bottom -> it inverts to short.
    cs = series([
        (10, 11, 9, 10.5),   # 0  high 11
        (12, 13, 11, 12.5),  # 1
        (13, 14, 12, 13.5),  # 2  low 12 > high[0] 11 -> bullish FVG (12..11? )
        (12, 12.5, 9, 9.5),  # 3  closes 9.5 < gap bottom 11 -> inverse
    ])
    fvgs = find_fvgs(cs, min_size=0.5)
    assert fvgs and fvgs[0][1] == "long"
    inv = inverse_fvgs(cs, fvgs)
    assert inv and inv[0]["new_dir"] == "short"
    assert inv[0]["violated"] == 3


def test_breaker_is_last_opposite_candle_before_choch():
    cs = series([
        (10, 11, 9, 10),
        (10, 15, 9, 14),
        (14, 14, 11, 12),   # bearish candle just before the up-break
        (12, 17, 12, 16),   # bullish CHoCH up
        (12, 13, 11, 12),
        (12, 20, 11, 19),
    ])
    swings = find_swings(cs, strength=1)
    events = find_structure_events(cs, swings, strength=1)
    breakers = find_breakers(cs, events)
    assert breakers, "expected a breaker for the CHoCH"
    assert breakers[0]["dir"] == "up"
