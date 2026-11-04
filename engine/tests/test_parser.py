from sweepbt.parser import parse_lines


def test_parses_mt5_two_space_gap_and_skips_header():
    lines = [
        "Date Time,Open,High,Low,Close,Volume,Spread",
        "2026.05.27  01:00,4536.97000,4538.67000,4501.25000,4504.80000,2815,0",
        "2026.05.27  01:15,4504.80000,4510.12000,4502.78000,4504.53000,1993,0",
    ]
    r = parse_lines(lines)
    assert len(r.candles) == 2
    c0 = r.candles[0]
    # exact to the cent
    assert (c0.open, c0.high, c0.low, c0.close) == (4536.97, 4538.67, 4501.25, 4504.80)
    assert c0.volume == 2815 and c0.spread == 0
    assert c0.timestamp.hour == 1 and c0.timestamp.minute == 0
    assert not r.bad_rows


def test_tab_and_whitespace_and_missing_timestamp():
    lines = [
        "2026.05.27\t01:30\t4504.5\t4506\t4500\t4503\t10\t1",   # tab, split date/time
        "4500 4502 4498 4501 9 0",                              # whitespace, no ts
    ]
    r = parse_lines(lines)
    assert len(r.candles) == 2
    assert r.candles[0].timestamp is not None       # tab date+time rejoined
    assert r.candles[1].timestamp is None            # numbered candle
    assert r.candles[1].label == "#1"


def test_flags_bad_rows_with_line_numbers():
    lines = [
        "2026.05.27  01:00,10,12,8,11,5,0",   # ok  (line 1)
        "2026.05.27  01:15,10,8,12,9,5,0",    # high<low (line 2)
        "garbage,row",                         # too few numbers (line 3)
    ]
    r = parse_lines(lines)
    assert len(r.candles) == 1
    bad_lines = {b.line_no for b in r.bad_rows}
    assert bad_lines == {2, 3}
    assert any("high" in b.reason for b in r.bad_rows)
