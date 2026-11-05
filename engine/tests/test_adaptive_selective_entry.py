import os
import sys
import unittest
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from sweepbt.models import Candle
from sweepbt.strategies.adaptive_selective_entry import _daily_vwap, _donchian


class AdaptiveSelectiveEntryIndicatorTests(unittest.TestCase):
    def test_donchian_excludes_current_signal_bar(self):
        candles = [
            Candle(0, 9, 10, 8, 9, 1),
            Candle(1, 10, 12, 9, 11, 1),
            Candle(2, 11, 20, 10, 19, 1),
        ]
        channel = _donchian(candles, 2)[2]
        self.assertEqual(channel, (12, 8, 10))

    def test_daily_vwap_resets_on_new_date(self):
        candles = [
            Candle(0, 9, 11, 9, 10, 2, timestamp=datetime(2026, 1, 1, 10)),
            Candle(1, 10, 12, 10, 11, 1, timestamp=datetime(2026, 1, 1, 11)),
            Candle(2, 19, 21, 19, 20, 4, timestamp=datetime(2026, 1, 2, 10)),
        ]
        values = _daily_vwap(candles)
        self.assertAlmostEqual(values[0], 10.0)
        self.assertAlmostEqual(values[1], (10.0 * 2 + 11.0) / 3.0)
        self.assertAlmostEqual(values[2], 20.0)

    def test_donchian_warmup_is_none(self):
        candles = [Candle(i, 1, 2, 0, 1, 1) for i in range(4)]
        values = _donchian(candles, 3)
        self.assertIsNone(values[0])
        self.assertIsNone(values[1])
        self.assertIsNone(values[2])
        self.assertIsNotNone(values[3])


if __name__ == "__main__":
    unittest.main()
