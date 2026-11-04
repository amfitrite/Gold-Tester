"""Make ``src/`` importable and expose a tiny candle builder for tests."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sweepbt.models import Candle  # noqa: E402


def mk(o, h, l, c, i=0, v=0):
    """Build a Candle, asserting OHLC sanity so fixtures stay honest."""
    assert h >= max(o, c) and l <= min(o, c) and h >= l, f"bad candle {(o,h,l,c)}"
    return Candle(index=i, open=o, high=h, low=l, close=c, volume=v)


def series(rows):
    """rows: list of (o,h,l,c) -> indexed Candle list."""
    return [mk(*r, i=idx) for idx, r in enumerate(rows)]
