"""Generate deterministic sample MT5 XAUUSD M15 exports for demos/tests.

Produces two days:
  * a strong-downtrend day (sell-side sweeps align with trend),
  * a choppy/range day (where a trend filter tends to cost),
so batch mode and the filter ON/OFF comparison have a realistic sample.

Run: python tools/make_sample.py
"""
from __future__ import annotations

import os
import random
from datetime import datetime, timedelta

OUT = os.path.join(os.path.dirname(__file__), "..", "data")


def gen_day(date: str, n: int, start: float, drift: float, vol: float, seed: int):
    rnd = random.Random(seed)
    t = datetime.strptime(date + " 01:00", "%Y.%m.%d %H:%M")
    price = start
    rows = []
    for i in range(n):
        o = price
        # base step with drift + noise; occasional larger swings create swings/sweeps
        step = drift + rnd.gauss(0, vol)
        if rnd.random() < 0.18:                  # impulsive bar
            step += rnd.choice([-1, 1]) * rnd.uniform(vol, vol * 2.5)
        c = o + step
        # wicks beyond the body — these create the sweep wicks
        hi = max(o, c) + abs(rnd.gauss(0, vol * 0.8))
        lo = min(o, c) - abs(rnd.gauss(0, vol * 0.8))
        vol_n = int(rnd.uniform(800, 3200))
        rows.append((t, o, hi, lo, c, vol_n, 0))
        price = c
        t += timedelta(minutes=15)
    return rows


def write_csv(path: str, rows, header: bool):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        if header:
            fh.write("Date Time,Open,High,Low,Close,Volume,Spread\n")
        for t, o, hi, lo, c, v, s in rows:
            ts = t.strftime("%Y.%m.%d  %H:%M")   # two-space gap, MT5 style
            fh.write(f"{ts},{o:.5f},{hi:.5f},{lo:.5f},{c:.5f},{v},{s}\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    # Downtrend day: negative drift.
    down = gen_day("2026.05.27", 84, start=4536.97, drift=-0.45, vol=3.0, seed=27)
    write_csv(os.path.join(OUT, "xauusd_m15_2026-05-27.csv"), down, header=True)
    # Range/chop day: ~zero drift, header omitted to exercise the parser.
    chop = gen_day("2026.05.28", 84, start=4505.0, drift=0.0, vol=3.2, seed=28)
    write_csv(os.path.join(OUT, "xauusd_m15_2026-05-28.csv"), chop, header=False)
    print("wrote sample data to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
