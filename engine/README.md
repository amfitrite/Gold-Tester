# Gold Strategy Lab (MT5 data)

A local, runnable **multi-strategy backtester** for Gold (XAUUSD) MT5 exports. It
mechanically detects setups for several strategies, simulates a fixed
risk:reward outcome on each, marks the ICT structure on the chart, and lets you
sweep RR / trend-filter / timeframe / session to see **which trades bleed money**.

**17 strategies** ship in the registry (add more by dropping a module in
`strategies/`):

1. **Liquidity sweep → imbalance → reversal** (the original ICT setup).
2. **Previous-day high/low breakout** — first close beyond yesterday's high/low.
3. **Opening-range breakout (ORB)** — first close beyond the day's opening range.
4. **RSI oversold/overbought reversal** — fade exhaustion as RSI snaps back out of an extreme.
5. **Support/resistance bounce** — buy a bounce off a clustered support zone, sell a rejection at resistance.
6. **Momentum breakout** — first expansion candle that closes beyond the recent range.
7. **Momentum pullback** — buy the dip / sell the rally with the moving-average trend.
8. **ICT fair value gap (FVG)** — trade the first pullback that fills a 3-candle gap.
9. **ICT inverse FVG (IFVG)** — trade the retest of an FVG price has closed through (flipped polarity).
10. **ICT order block** — enter the retrace into the OB that drove a BOS/CHoCH.
11. **Smart money (SMC)** — sweep → change of character → order-block entry.
12. **Supply/demand zones** — a quiet base + strong departure, traded on the return.
13. **Order flow** — high-volume rejection candle followed by directional confirmation.
14. **Bollinger bands** — outer-band mean reversion toward the middle band.
15. **Session gap fade** — fade a gap at the next session boundary.
16. **VWAP bounce** — trade a cross/reclaim around cumulative VWAP.
17. **Gold Rolling Sweep** — previous-range liquidity sweep + rejection wick + 50% limit retrace.

Pick any strategy in the lab and a one-line plain-English description plus a
**best-setup recommendation** (the timeframe × RR with the highest expectancy on
the full embedded sample) appear above the chart. Click any row in the **Setups**
table to open a **trade-detail slide** — a zoomed chart around that single trade
with the key level, zone, entry/SL/TP marked, a 4-step narrative, and an exact
trade ticket.

The headline deliverable is **`strategy_lab.html`**: a single self-contained,
interactive page (M5–H4 embedded) where you switch strategy, RR (1:1 … 3:1),
period and trend filter live and watch the stats, chart markings and an
"avoid-losers" optimizer update instantly. A static `report.html` (per-file /
batch) is also produced by the CLI.

> **Honesty up front.** Every "win/loss" here is *hindsight on past candles* —
> what the rules **would have flagged**, not a prediction or a live signal
> generator. All prices/levels are computed exactly from the OHLC (verifiable to
> the cent against MT5). When a single candle spans both stop and target, it is
> resolved as a **loss** (we can't know intrabar order from OHLC). A trend filter
> that looks perfect on a trending day will cost you on a chop/range day — so
> filter ON-vs-OFF and multi-day batch testing are first-class here, not an
> afterthought.

## Why this stack

Pure **Python standard library** for the engine + a **self-contained vanilla-JS
canvas** for the chart. No pandas, no numpy, no plotting library, nothing to
`pip install` to run it — `python run.py` works on a bare Python 3.9+. The
detection logic is plain functions over `Candle` objects, which keeps it
trivially unit-testable (see `tests/`). (`pytest` is the only dev dependency.)

## Quick start

### Interactive Strategy Lab (recommended)

Point it at the folder holding your `XAUUSD<TF>.csv` exports — it finds the
M5/M15/M30/H1/H4 files, embeds them, and writes one self-contained page:

```bash
PYTHONPATH=src python -m sweepbt.lab "C:/path/to/csv/folder" --out strategy_lab.html
```

Open `strategy_lab.html` in any browser. No server, no internet (web fonts
degrade gracefully offline). Switch **strategy / RR / timeframe / period / trend
filter** with the controls; the chart, stat cards, hour & direction breakdowns,
and the **avoid-losers optimizer** (best RR × filter for the current window)
recompute live. Changing RR re-walks every trade in the browser using the exact
same win/loss rules as the Python engine.

> M1 is intentionally **not** embedded in the lab (≈100k candles is too much for
> a browser); use the CLI below for M1.

### Static report / CLI (any timeframe incl. M1)

```bash
python run.py                                   # bundled sample days -> report.html
python run.py "data/*.csv" --timeframe M15 --out report.html

# pick a strategy and an RR ratio:
PYTHONPATH=src python -m sweepbt.cli "data/XAUUSDM15.csv" --timeframe M15 \
    --strategy orb --rr 1:2 --out report.html
PYTHONPATH=src python -m sweepbt.cli "data/XAUUSDM1.csv" --timeframe M1 \
    --strategy prev_day_breakout --rr 3:1
```

Run the tests:

```bash
python -m pytest tests/ -q
```

## Live deployment

The `strategy_lab.html` is a **single self-contained file** — no server required. Open it directly in your browser to use it offline.

To **share it live with others**, serve it over HTTP:

```bash
# Start a local HTTP server on port 8888
python -m http.server 8888

# Then expose it publicly via localhost tunnel (free, no auth needed)
npx localtunnel --port 8888
```

You'll get a public URL like `https://xyz123.loca.lt/strategy_lab.html` that works from anywhere.

Alternatively, **deploy to GitHub Pages** from the `strategy_lab.html` artifact, or host on any static server (Netlify, Vercel, AWS S3, etc.).

## Input data format (MT5 "Save As / Export")

One candle per line: `date time, open, high, low, close, volume, spread`, e.g.

```
2026.05.27  01:00,4536.97000,4538.67000,4501.25000,4504.80000,2815,0
```

The parser is forgiving: auto-detects **UTF-16/UTF-8 BOM** encodings (MT5 often
exports UTF-16-LE), handles the `YYYY.MM.DD HH:MM` timestamp (incl. the
two-space gap), tolerates comma / tab / whitespace separation, skips a header
row, ignores trailing columns, and **numbers candles when the timestamp is
missing**. It validates `high >= low` (and that open/close sit inside the range)
and reports every bad row by **source line number** (shown in the report).

Load multiple files / days at once for batch stats — just pass several paths or
a glob.

## Strategy 1 — liquidity sweep → imbalance (what gets detected)

1. **Swing liquidity** — a swing high = `high` strictly greater than the highs of
   `N` candles on *both* sides (`N` = swing strength, default 3); swing lows
   mirror it. Swing highs = sell-side liquidity, swing lows = buy-side.
2. **Sweep** — a later candle wicks *beyond* a prior level but *closes back* on
   the origin side: sell-side `high > level & close < level`; buy-side
   `low < level & close > level`. A mere close beyond the level is a **break**,
   not a sweep, and is ignored. Only the **first** sweep of each level is taken.
3. **Imbalance (entry zone)**, preferred in order:
   - **Order Block (OB)** — the last opposite-color candle immediately before the
     impulse out of the sweep (within `ob_lookahead` candles).
   - **Fair Value Gap (FVG)** — a 3-candle gap (`low[3] > high[1]` bullish /
     `high[3] < low[1]` bearish) exceeding the min-size filter, aligned with the
     trade direction within `fvg_lookahead` candles, used when no OB is present.
4. **Direction** — buy-side sweep (took lows) → **LONG**; sell-side sweep (took
   highs) → **SHORT**.
5. **Entry + simulation** — within the pullback window after the sweep (and only
   *after* the zone has fully formed — no lookahead), price returns into the
   zone. Entry = the near edge of the zone in the trade direction. Stop = beyond
   the sweep wick *and* the zone, plus a buffer. TP = `entry ± risk × RR`. We
   then walk forward candle-by-candle: TP-before-SL = **win**, SL first =
   **loss**, neither before data ends = **unresolved** (excluded from win rate).

## Strategy 2 — previous-day high/low breakout

For each day after the first, yesterday's high (PDH) and low (PDL) are resting
levels. The first candle to **close** above PDH goes **long** (entry at PDH);
the first to close below PDL goes **short** (entry at PDL). Stop sits beyond that
breakout candle's opposite extreme + buffer; TP = `entry ± risk × RR`. One long
and one short attempt per day at most. (Fills at the close, so the walk-forward
resolves from the next candle.)

## Strategy 3 — opening-range breakout (ORB)

The opening range is the high/low of the first `--orb-window` candles of each
day. After that window, the first close above the range high goes **long**, the
first below the range low goes **short**; entry at the broken edge, stop on the
opposite edge + buffer, TP = `entry ± risk × RR`. One of each per day.

## Strategies 4–16 (the remaining original registry strategies)

All share the same engine — entry, fixed-RR stop/target, and the candle-by-candle
walk-forward (same-candle stop+target = loss) — so their stats are directly
comparable. Each is intentionally *selective*:

- **RSI reversal** — trade the bar where RSI closes back *out* of oversold (long)
  or overbought (short); the snap-back, not the extreme. Stop beyond that bar.
- **Support/resistance** — cluster repeated swing levels into zones; long a close
  back above support, short a close back below resistance. Each zone once.
- **Momentum breakout** — an *expansion* candle (range above the recent average)
  that closes beyond the N-bar high/low. Stop at the breakout bar's far side.
- **Momentum pullback** — with the MA trend, a shallow counter-trend dip then a
  close back in the trend direction. Stop below the dip / above the rally.
- **ICT FVG** — first pullback that taps the proximal edge of a 3-candle gap,
  traded in the gap's direction; stop on the far side of the gap.
- **ICT IFVG** — when price *closes through* an FVG it flips; trade the first
  retest of the inverted gap in the new direction.
- **ICT order block** — after a BOS/CHoCH, enter the retrace into the order block
  (last opposite-colour candle before the break).
- **Smart money** — the full sequence: liquidity sweep → CHoCH confirming the
  reversal → entry on the order block behind the shift.
- **Supply/demand** — a quiet base candle + a dominant-body departure marks a
  zone; trade the first return into the base.
- **Order flow** — high-volume rejection and next-bar confirmation.
- **Bollinger bands** — mean reversion from an outer band toward the middle.
- **Session gap** — fade a gap at a configured session transition.
- **VWAP bounce** — trade price reclaiming/crossing cumulative VWAP.

## Chart markings (context, not signals)

Beyond the per-strategy setups, the lab marks the ICT structure so you can read
the context: **swing liquidity**, **sweeps**, **FVG** and **inverse FVG** (an
FVG price later closes through, flipping polarity), **order blocks**,
**breaker blocks**, **BOS / CHoCH** (break of structure vs change of character,
computed causally — a swing is only "known" `strength` candles after its pivot),
**support/resistance** clusters, and the per-day **PDH/PDL / opening-range**
levels used by the breakout strategies. Every marking is a toggleable layer.

## The trend filter (the whole point)

Run raw, the rules happily flag buy-side sweeps as LONGs and get run over on a
trending-down day. The fix is a toggleable **trend filter** that only takes
setups aligned with the prevailing bias:

- `--trend ema` *(default)* — 20/50 EMA: longs only when price > slow EMA and the
  fast EMA is rising; shorts only when price < slow EMA and fast falling.
- `--trend structure` — higher-high/higher-low vs lower-high/lower-low read off
  the detected swing points.

Filtering is **non-destructive**: every setup is tagged keep/skip, and the report
shows **Filter OFF (all setups)** next to **Filter ON (trend-aligned)** so you
can see exactly what the filter costs or saves — per day *and* aggregated.

Two extra guardrails:
- `--close-confirm` — require a *close back through the zone* (not just a wick
  touch) to cut counter-trend bounce entries.
- `--max-risk X` — reject setups whose risk (zone width) exceeds `X` price units
  (bloated zones tend to be low-quality).

### Tunable parameters

| flag | meaning | default |
|---|---|---|
| `--strategy` | any registry name: `liquidity_imbalance`, `prev_day_breakout`, `orb`, `rsi_reversal`, `support_resistance`, `momentum_breakout`, `momentum_pullback`, `ict_fvg`, `ict_ifvg`, `ict_order_block`, `smart_money`, `supply_demand`, `order_flow`, `bollinger_bands`, `session_gap`, `vwap_bounce`, `gold_session_sweep` | liquidity_imbalance |
| `--rr` | take-profit risk:reward — accepts `2`, `2.5`, or ratios `1:2`, `3:1` | 2.0 |
| `--swing-strength` | candles each side for a swing | 3 |
| `--min-fvg` | min FVG size (price units) | 1.0 |
| `--sl-buffer` | buffer beyond sweep/zone for the stop | 0.5 |
| `--pullback` | pullback window (candles) for entry | 12 |
| `--orb-window` | candles forming the opening range (ORB) | per-timeframe |
| `--timeframe` | `M1`/`M5`/`M15`/`M30`/`H1`/`H4` preset (sensible defaults) | — |
| `--trend` | `ema` / `structure` | ema |
| `--close-confirm` | require close back through zone | off |
| `--max-risk` | reject setups wider than this | off |

> `--rr 1:2` means 1 unit of risk for 2 of reward (TP = 2× risk). `--rr 3:1`
> means 3 risk for 1 reward (TP = ⅓× risk) — a high win-rate / low-payoff config.

## Output

### `strategy_lab.html` (interactive)

- **Live controls** — timeframe (M5–H4), strategy (all 17), RR (1:1 … 3:1), three
  **stackable filters** (trend / MA / RSI, combined with AND), and a from/to
  **period** selector.
- **Strategy explainer + best-setup line** — a one-line description of the chosen
  strategy and the timeframe × RR that maximised expectancy on the full sample.
- **Click-through trade detail** — clicking a row in the Setups table opens a
  zoomed, marked-up slide for that one trade (level, zone, entry/SL/TP, a 4-step
  narrative and a trade ticket with the risk:reward bar).
- **Candlestick chart** with toggleable layers: liquidity, sweeps, FVG, inverse
  FVG, order blocks, breakers, BOS/CHoCH, S/R zones, breakout levels, the **MA
  line**, and each trade's entry/SL/TP + win/loss exit dot. Hover shows OHLC.
- **Stat cards + verdict** — trades, win rate, total R, expectancy, with a plain
  English read on whether the config has an edge or is bleeding.
- **Breakdowns** by entry hour and direction (where the losses concentrate).
- **Per-setup filter flags** — every setup is tagged trend / MA / RSI keep-skip,
  so you can see exactly which rule would have removed each loser.
- **Avoid-losers optimizer** — sweeps every RR × filter-combo (none, trend, MA,
  RSI and their mixes) for the current strategy/timeframe/window and ranks them
  by expectancy (≥ 5 resolved trades), so the best configuration is obvious.

### `report.html` (static / batch, from the CLI)

- Interactive candlestick chart (MT5-style) with liquidity / sweep / FVG-OB /
  setup layers and win/loss exit markers; hover shows OHLC + volume.
- **Stats panel** for **filter ON** vs **filter OFF**, per-setup list, and — in
  batch mode — aggregate stats across all files plus a per-day breakdown.

## Project layout

```
gold-sweep-backtester/
├── run.py                  # one-command runner (defaults to sample data)
├── requirements.txt
├── data/                   # bundled sample MT5 exports (a trend day + a chop day)
├── tools/make_sample.py    # regenerates the sample data deterministically
├── src/sweepbt/
│   ├── models.py           # Candle / Swing / Sweep / Zone / Setup
│   ├── params.py           # tunable params + timeframe presets (M1–H4)
│   ├── parser.py           # forgiving MT5 parser (UTF-16/UTF-8 aware)
│   ├── swings.py           # swing detection
│   ├── sweeps.py           # sweep detection
│   ├── imbalance.py        # OB + FVG detection, zone selection
│   ├── structure.py        # BOS/CHoCH, S/R, inverse FVG, breaker markings
│   ├── daygroups.py        # group candles into trading days
│   ├── simulate.py         # entry + walk-forward TP/SL (shared by strategies)
│   ├── strategies/         # one module per strategy + a registry (17 total)
│   │   ├── __init__.py     # REGISTRY + LABELS + DESCRIPTIONS
│   │   ├── _common.py      # shared pullback-entry helper
│   │   ├── liquidity_imbalance.py
│   │   ├── prev_day_breakout.py
│   │   ├── orb.py
│   │   ├── rsi_reversal.py
│   │   ├── support_resistance.py
│   │   ├── momentum_breakout.py
│   │   ├── momentum_pullback.py
│   │   ├── ict_fvg.py
│   │   ├── ict_ifvg.py
│   │   ├── ict_order_block.py
│   │   ├── smart_money.py
│   │   └── supply_demand.py
│   ├── trend.py            # EMA / structure bias + filter
│   ├── report.py           # stats aggregation
│   ├── chart.py            # self-contained static HTML/canvas report
│   ├── lab.py              # interactive multi-strategy Strategy Lab
│   ├── engine.py           # full pipeline + batch
│   └── cli.py              # argparse entry point
└── tests/                  # hand-checked unit tests for every stage
```

## New strategy — Gold Rolling Liquidity Sweep + 50% Rejection Retest

Strategy id: `gold_session_sweep`.

Designed as a more frequent XAUUSD M5 test without reliance on session
timestamps:

1. Use the previous **24 candles** (default when `swing_strength=3`) to define
   a rolling high and low. No current/future candle is included in those levels.
2. A short candidate requires a wick above the prior high, a close back below
   that level, a bearish candle, and an upper wick at least 25% of its range.
   Long conditions mirror this below the rolling low.
3. Wait for a later retest of the rejection candle's **50% range level**. The
   retest must close back in the trade direction.
4. Stop goes beyond the rejection wick plus `--sl-buffer`; target is configured
   by `--rr`. A matching three-candle FVG is recorded as optional confluence,
   not a requirement.
5. A new setup is not evaluated until the previous simulated position exits,
   avoiding overlapping trades.

The signal works with timestamped or untimestamped OHLC data. The lookback is
`max(12, swing_strength × 8)`; with the M5 preset's swing strength of 3 it is
24 bars (about two hours). It is a research candidate, not a proven profitable
system.

Example:

```bash
PYTHONPATH=src python -m sweepbt.cli "data/XAUUSDM5.csv" --timeframe M5 \
    --strategy gold_session_sweep --rr 1:2 --sl-buffer 0.3 --pullback 16
```

---

## Importable engine

```python
import sys; sys.path.insert(0, "src")
from sweepbt.params import Params
from sweepbt.engine import run_file
from sweepbt.lab import discover_files, write_lab

# Backtest one strategy on one file:
result = run_file("data/XAUUSDM15.csv", Params.for_timeframe("M15"),
                  strategy="orb")
print(result.stats_off.as_dict())   # filter OFF
print(result.stats_on.as_dict())    # filter ON (trend-aligned)
for s in result.setups:
    print(s.strategy, s.direction, s.entry_price, s.stop_loss,
          s.take_profit, s.verdict, s.filter_kept)

# Build the interactive lab from a folder of XAUUSD<TF>.csv files:
write_lab("strategy_lab.html", discover_files("C:/path/to/csv"))
```
