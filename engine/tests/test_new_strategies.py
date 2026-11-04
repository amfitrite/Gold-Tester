"""Coverage for the 9 added strategies: registry wiring, a hand-checked
momentum breakout, and a no-lookahead invariant shared by all strategies."""
from conftest import series

from sweepbt.params import Params
from sweepbt.strategies import REGISTRY, LABELS, DESCRIPTIONS, run_strategy
from sweepbt.strategies.momentum_breakout import run as momentum_breakout


NEW = ["rsi_reversal", "support_resistance", "momentum_breakout", "momentum_pullback",
       "ict_fvg", "ict_ifvg", "ict_order_block", "smart_money", "supply_demand"]


def test_registry_label_description_in_sync():
    assert set(REGISTRY) == set(LABELS) == set(DESCRIPTIONS)
    for name in NEW:
        assert name in REGISTRY
        assert LABELS[name] and DESCRIPTIONS[name]


def test_every_strategy_runs_on_trivial_series():
    cs = series([(10, 11, 9, 10)] * 30)  # flat: no signals, must not raise
    p = Params()
    for name in REGISTRY:
        assert run_strategy(name, cs, p) == []


def test_momentum_breakout_long_is_hand_checked():
    # 6 quiet bars (range 1), then an expansion bar that closes above the
    # 6-bar high of 11. lookback defaults to ema_fast=20 here, so use a small one.
    p = Params(ema_fast=5, rr=2.0, sl_buffer=0.5)
    cs = series([
        (10, 11, 10, 10),   # 0
        (10, 11, 10, 10),   # 1
        (10, 11, 10, 10),   # 2
        (10, 11, 10, 10),   # 3
        (10, 11, 10, 10),   # 4  (6-bar high so far = 11)
        (11, 16, 11, 15.5), # 5  range 5 >> avg 1, close 15.5 > 11 -> long
        (15, 30, 15, 29),   # 6  high 30 hits tp
    ])
    setups = momentum_breakout(cs, p)
    assert len(setups) == 1
    s = setups[0]
    assert s.direction == "long" and s.strategy == "momentum_breakout"
    assert s.entry_index == 5
    # entry = close 15.5, sl = low 11 - 0.5 = 10.5, risk 5, tp = 15.5 + 10 = 25.5
    assert round(s.entry_price, 2) == 15.5
    assert round(s.stop_loss, 2) == 10.5
    assert round(s.take_profit, 2) == 25.5
    assert s.verdict == "win"


def test_no_setup_resolves_before_its_entry():
    # Invariant for all strategies: the walk-forward must start at or after the
    # entry candle (no peeking at the bar that hasn't formed yet).
    import random
    rnd = random.Random(7)
    rows, price = [], 2000.0
    for _ in range(400):
        o = price
        c = o + rnd.uniform(-5, 5)
        hi = max(o, c) + rnd.uniform(0, 3)
        lo = min(o, c) - rnd.uniform(0, 3)
        rows.append((round(o, 2), round(hi, 2), round(lo, 2), round(c, 2)))
        price = c
    cs = series(rows)
    p = Params()
    for name in REGISTRY:
        for s in run_strategy(name, cs, p):
            ri = s.resolve_index if s.resolve_index is not None else s.entry_index
            assert ri >= s.entry_index, f"{name} resolves before entry"
            assert s.entry_index >= s.trigger_index, f"{name} entry precedes trigger"
