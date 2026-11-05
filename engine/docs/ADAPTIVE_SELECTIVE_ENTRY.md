# Adaptive Selective Entry (ASE)

ASE is a transparent, GoldWave-inspired research strategy for XAUUSD OHLCV data.
It reconstructs the *published architecture* (adaptive regime, momentum/volatility
selection and adaptive exits), not GoldWave's private implementation.

## Entry model

- **Regime:** prior-bar Donchian channel width and midline slope classify the
  environment as trend or range. The signal candle is excluded from Donchian
  reference levels.
- **Momentum quality:** candle body / full range must clear the configured
  efficiency threshold and point in the trade direction.
- **Volatility:** current ATR / baseline ATR must remain inside the allowed band.
- **Trend entry:** in a directional regime, wait for a daily VWAP touch and
  reclaim/rejection in the trend direction.
- **Range entry:** approximate a rolling volume profile and trade rejection at
  VAL / VAH back toward POC.
- **Risk:** hard stop beyond the signal candle extreme plus an ATR buffer.
  No grid, martingale, averaging or position scaling.
- **Exit:** use the next structural target when it offers enough reward; otherwise
  fall back to the configured RR. The structural target is capped by the maximum
  target-R setting.

## Important data limitation

The profile is an OHLCV proxy: each candle's volume is assigned to its typical
price (high + low + close) / 3. It is **not** a true exchange footprint or
per-price traded-volume profile. Daily VWAP resets on the date in the CSV; if
timestamps are absent it remains cumulative over the supplied series. Results
therefore depend on broker feed, timestamp timezone and CSV granularity.

## M5 starting values

| Parameter | Default |
|---|---:|
| Donchian period | 20 |
| ATR period / baseline | 14 / 50 |
| ATR ratio allowed | 0.65–1.80 |
| Minimum channel width | 1.50 ATR |
| Regime slope lookback | 5 bars |
| Trend slope threshold | 0.20 ATR |
| Candle body efficiency | 0.55 |
| Rejection tolerance | 0.15 ATR |
| Stop buffer | 0.15 ATR |
| Value Area lookback / fraction | 48 / 70% |
| Profile bin size | 0.50 price units |
| Minimum / maximum target | 1.0R / 2.5R |

These are research defaults, not optimized or validated performance claims.

## Run and tune

From the engine directory:

\`\`\`powershell
$env:PYTHONPATH="src"
python -m sweepbt.cli "C:/path/to/XAUUSDM5.csv" --timeframe M5 --strategy adaptive_selective_entry --rr 1:2 --out ase-report.html
\`\`\`

Example fine-tuning:

\`\`\`powershell
python -m sweepbt.cli "C:/path/to/XAUUSDM5.csv" --timeframe M5 --strategy adaptive_selective_entry --ase-donchian 24 --ase-atr-period 14 --ase-atr-baseline 60 --ase-atr-min 0.70 --ase-atr-max 1.60 --ase-body-efficiency 0.60 --ase-value-area-period 60 --ase-profile-bin-size 0.25 --ase-target-rr-max 2.0 --out ase-tuned.html
\`\`\`

Run the unit tests with \`python -m pytest tests/test_adaptive_selective_entry.py -q\`.
Compare raw and filtered results, and use chronological out-of-sample periods.
Include spread, commission and slippage before treating a result as tradable.
