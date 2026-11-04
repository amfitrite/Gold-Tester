#!/usr/bin/env python3
"""One-command runner.

  python run.py                 # backtest the bundled sample data -> report.html
  python run.py data/*.csv --timeframe M15 --rr 2 --out report.html
  python run.py --help          # all options

Any arguments are forwarded to sweepbt.cli; with no file arguments it falls back
to the bundled sample dataset.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))

from sweepbt.cli import main  # noqa: E402

if __name__ == "__main__":
    argv = sys.argv[1:]
    has_files = any(not a.startswith("-") for a in argv)
    if not has_files:
        sample = [
            os.path.join("data", "xauusd_m15_2026-05-27.csv"),
            os.path.join("data", "xauusd_m15_2026-05-28.csv"),
        ]
        argv = sample + argv
        if "--timeframe" not in argv:
            argv += ["--timeframe", "M15"]
    raise SystemExit(main(argv))
