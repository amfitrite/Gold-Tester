from conftest import series
from sweepbt.models import Sweep
from sweepbt.params import Params
from sweepbt.simulate import build_setup, simulate_setup

# A buy-side sweep -> long. Fixed head:
#   1: sweep candle (wick to 9.0)
#   2: bearish OB  -> zone [9.2, 9.7]
#   3: bullish impulse away
# => entry (proximal/top) = 9.70, SL = min(9.0, 9.2) - 0.5 = 8.50,
#    risk = 1.20, TP = 9.70 + 2*1.20 = 12.10
HEAD = [
    (10, 10.2, 9.8, 10.0),
    (9.9, 10.0, 9.0, 9.6),    # sweep (bearish)
    (9.6, 9.7, 9.2, 9.3),     # OB (bearish)
    (10.0, 10.5, 9.95, 10.4), # impulse (bullish)
]
SWEEP = Sweep(index=1, level=9.2, swing_index=0, side="buy", wick=9.0)


def setup_for(tail, **overrides):
    cs = series(HEAD + tail)
    return build_setup(cs, SWEEP, Params(**overrides))


def test_levels_computed_exactly():
    s = setup_for([(10.4, 10.5, 9.6, 9.9), (9.9, 12.2, 9.8, 12.0)])
    assert s.direction == "long"
    assert s.entry_price == 9.70 and s.stop_loss == 8.50
    assert round(s.risk, 4) == 1.20 and round(s.take_profit, 4) == 12.10


def test_win_when_tp_first():
    s = setup_for([(10.4, 10.5, 9.6, 9.9), (9.9, 12.2, 9.8, 12.0)])
    assert s.entry_index == 4 and s.verdict == "win" and s.r_multiple == 2.0
    assert s.exit_index == 5 and round(s.exit_price, 4) == 12.10


def test_loss_when_sl_first():
    s = setup_for([(10.4, 10.5, 9.6, 9.9), (9.9, 9.95, 8.4, 8.6)])
    assert s.verdict == "loss" and s.r_multiple == -1.0 and s.exit_price == 8.50


def test_unresolved_excluded():
    s = setup_for([(10.4, 10.5, 9.6, 9.9), (9.9, 10.0, 9.5, 9.8)])
    assert s.verdict == "unresolved" and s.r_multiple == 0.0


def test_same_candle_tie_resolves_as_loss():
    s = setup_for([(10.4, 10.5, 9.6, 9.9), (9.9, 12.3, 8.4, 9.0)])
    assert s.verdict == "loss" and s.exit_price == 8.50


def test_close_confirmation_filters_wick_only_entry():
    # only wick touches, price keeps falling, never closes back above the zone edge
    tail = [(10.4, 10.5, 9.6, 9.65), (9.65, 9.7, 9.0, 9.1), (9.1, 9.2, 8.3, 8.4)]
    assert setup_for(tail) is not None                       # wick touch fills
    assert setup_for(tail, require_close_confirmation=True) is None  # guardrail cuts it


def test_max_risk_guardrail_rejects_wide_setups():
    tail = [(10.4, 10.5, 9.6, 9.9), (9.9, 12.2, 9.8, 12.0)]
    assert setup_for(tail) is not None
    assert setup_for(tail, max_risk=1.0) is None             # risk 1.2 > 1.0



def test_win_uses_actual_target_distance_not_configured_rr():
    # Risk = 1.20, but the target is only 0.60 away: realized result is +0.5R.
    candles = series(HEAD + [(9.7, 10.4, 9.6, 10.2)])
    s = simulate_setup(
        candles, "long", 4, 9.70, 8.50, 10.30, Params(rr=2.0),
        strategy="accounting_test", trigger_index=1, trigger_level=9.2,
        resolve_from=4,
    )
    assert s is not None
    assert s.verdict == "win"
    assert round(s.r_multiple, 6) == 0.5


def test_simulator_rejects_target_on_wrong_side_of_entry():
    candles = series(HEAD + [(9.7, 10.0, 9.6, 9.8)])
    s = simulate_setup(
        candles, "long", 4, 9.70, 8.50, 9.60, Params(rr=2.0),
        strategy="invalid_target_test", trigger_index=1, trigger_level=9.2,
        resolve_from=4,
    )
    assert s is None
