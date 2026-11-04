"""Interactive multi-strategy "Strategy Lab" HTML.

Python does the heavy lifting (parse + every detection + raw setups with the
trend-filter decision, which is independent of RR). The browser only recomputes
the take-profit and the walk-forward win/loss for whatever RR the user picks, so
the live controls (timeframe / strategy / RR / period / trend filter / layers)
are instant *and* stay faithful to the Python engine. The JS walk-forward is a
1:1 mirror of ``simulate.simulate_outcome`` (pessimistic same-candle tie-break).
"""
from __future__ import annotations

import json
import os
from datetime import datetime
from typing import Dict, List

from .params import Params
from .parser import parse_file
from .swings import find_swings
from .sweeps import find_sweeps
from .imbalance import find_fvgs
from .structure import (find_structure_events, support_resistance,
                        inverse_fvgs, find_breakers)
from .strategies import run_strategy, REGISTRY, LABELS, DESCRIPTIONS
from .trend import apply_trend_filter
from .filters import build_context, ma_ok as _ma_ok, rsi_ok as _rsi_ok
from .daygroups import group_by_day, day_high_low

# Timeframes embedded in the interactive app. M1 is intentionally excluded
# (too many candles for a browser) and stays available through the CLI.
APP_TIMEFRAMES = ["M5", "M15", "M30", "H1", "H4"]


def _candle_json(c):
    return {"i": c.index, "t": c.label, "o": c.open, "h": c.high,
            "l": c.low, "c": c.close,
            "d": c.timestamp.strftime("%Y-%m-%d") if c.timestamp else "_all_"}


def _resolve_index(setup) -> int:
    # Each strategy records where its walk-forward starts; fall back to the entry
    # candle for older setups that predate the field.
    return setup.resolve_index if setup.resolve_index is not None else setup.entry_index


def _setup_json(s) -> dict:
    z = s.zone
    return {
        "dir": s.direction,
        "entry_index": s.entry_index,
        "entry": round(s.entry_price, 5),
        "sl": round(s.stop_loss, 5),
        "resolve_index": _resolve_index(s),
        "trigger_index": s.trigger_index,
        "trigger_level": round(s.trigger_level, 5),
        "note": s.note,
        "kept": s.filter_kept,
        "reason": s.filter_reason,
        "zone": ({"kind": z.kind, "top": round(z.top, 5), "bottom": round(z.bottom, 5),
                  "start": z.start_index, "end": z.end_index} if z else None),
    }


def _filter_flags(s, ctx) -> dict:
    # MA / RSI gates at the entry candle. None ("no opinion", e.g. warm-up) is
    # encoded as null so the JS treats it as a pass, same as the Python engine.
    m, r = _ma_ok(s, ctx), _rsi_ok(s, ctx)
    return {"ma_ok": m, "rsi_ok": r}


def _strategy_setups(candles, params, swings, ctx) -> Dict[str, list]:
    out: Dict[str, list] = {}
    for name in REGISTRY:
        setups = run_strategy(name, candles, params)
        apply_trend_filter(setups, candles, params, swings)
        rows = []
        for s in setups:
            row = _setup_json(s)
            row.update(_filter_flags(s, ctx))
            rows.append(row)
        out[name] = rows
    return out


def _markings(candles, params, swings, sweeps, fvgs) -> dict:
    ifvg = inverse_fvgs(candles, fvgs)
    events = find_structure_events(candles, swings, params.swing_strength)
    breakers = find_breakers(candles, events)
    tol = max(params.min_fvg_size * 2.0, params.sl_buffer * 2.0)
    sr = support_resistance(swings, tolerance=tol)

    # Per-day reference levels for the breakout / ORB strategies.
    days = group_by_day(candles)
    pdhl = []
    for d in range(1, len(days)):
        key, today = days[d]
        pdh, pdl = day_high_low(days[d - 1][1])
        pdhl.append({"date": str(key), "pdh": round(pdh, 5), "pdl": round(pdl, 5),
                     "from_index": today[0].index, "to_index": today[-1].index})
    w = max(1, params.orb_window)
    orb = []
    for key, today in days:
        if len(today) <= w + 1:
            continue
        hi = max(c.high for c in today[:w])
        lo = min(c.low for c in today[:w])
        orb.append({"date": str(key), "hi": round(hi, 5), "lo": round(lo, 5),
                    "start_index": today[0].index, "end_index": today[w - 1].index,
                    "to_index": today[-1].index})

    return {
        "swings": [{"i": s.index, "price": round(s.price, 5), "kind": s.kind} for s in swings],
        "sweeps": [{"i": s.index, "level": round(s.level, 5), "side": s.side,
                    "dir": s.direction, "wick": round(s.wick, 5)} for s in sweeps],
        "fvgs": [{"top": round(z.top, 5), "bottom": round(z.bottom, 5),
                  "start": z.start_index, "end": z.end_index, "dir": d}
                 for z, d in fvgs],
        "ifvgs": [{"top": round(x["top"], 5), "bottom": round(x["bottom"], 5),
                   "start": x["start"], "violated": x["violated"], "new_dir": x["new_dir"]}
                  for x in ifvg],
        "structure": [{"i": e.index, "level": round(e.level, 5),
                       "kind": e.kind, "dir": e.direction} for e in events],
        "breakers": [{"top": round(b["top"], 5), "bottom": round(b["bottom"], 5),
                      "i": b["index"], "dir": b["dir"]} for b in breakers],
        "sr": [{"price": round(z["price"], 5), "touches": z["touches"],
                "lo": round(z["lo"], 5), "hi": round(z["hi"], 5),
                "i": max([s.index for s in swings if z["lo"] <= s.price <= z["hi"]], default=0)}
               for z in sr],
        "pdhl": pdhl,
        "orb": orb,
    }


def build_tf_payload(candles, params: Params) -> dict:
    swings = find_swings(candles, params.swing_strength)
    sweeps = find_sweeps(candles, swings)
    fvgs = find_fvgs(candles, params.min_fvg_size)
    dates = sorted({c.timestamp.strftime("%Y-%m-%d") for c in candles if c.timestamp})
    ctx = build_context(candles, params, swings)
    return {
        "candles": [_candle_json(c) for c in candles],
        "dates": dates,
        "orb_window": max(1, params.orb_window),
        "ma_period": params.ma_period, "ma_kind": params.ma_kind,
        "rsi_period": params.rsi_period,
        "rsi_long_max": params.rsi_long_max, "rsi_short_min": params.rsi_short_min,
        "ma": [round(v, 3) if v is not None else None for v in ctx.ma],
        "markings": _markings(candles, params, swings, sweeps, fvgs),
        "strategies": _strategy_setups(candles, params, swings, ctx),
    }


def build_payload(files: Dict[str, str], base_overrides: dict = None) -> dict:
    """``files`` maps timeframe -> csv path. Each timeframe uses its own preset."""
    base_overrides = base_overrides or {}
    data: Dict[str, dict] = {}
    bad: Dict[str, list] = {}
    for tf, path in files.items():
        if tf not in APP_TIMEFRAMES:
            continue
        pr = parse_file(path)
        params = Params.for_timeframe(tf, **base_overrides)
        data[tf] = build_tf_payload(pr.candles, params)
        bad[tf] = [{"line": b.line_no, "reason": b.reason} for b in pr.bad_rows]
    return {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "timeframes": [tf for tf in APP_TIMEFRAMES if tf in data],
        "labels": LABELS,
        "descriptions": DESCRIPTIONS,
        "data": data,
        "bad": bad,
    }


def discover_files(folder: str) -> Dict[str, str]:
    """Find XAUUSD<TF>.csv (any symbol) for each app timeframe in a folder."""
    found: Dict[str, str] = {}
    for fn in os.listdir(folder):
        up = fn.upper()
        if not up.endswith(".CSV"):
            continue
        for tf in APP_TIMEFRAMES:
            if up.endswith(tf + ".CSV"):
                found[tf] = os.path.join(folder, fn)
    return found


def build_html(payload: dict) -> str:
    return _TEMPLATE.replace("/*__DATA__*/", json.dumps(payload, separators=(",", ":")))


def write_lab(out_path: str, files: Dict[str, str], base_overrides: dict = None) -> str:
    payload = build_payload(files, base_overrides)
    if not payload["timeframes"]:
        raise SystemExit("no M5–H4 csv files found to embed")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(build_html(payload))
    return out_path


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(
        description="Build the interactive Gold Strategy Lab (M5–H4) from MT5 csv exports.")
    ap.add_argument("source", nargs="?", default=".",
                    help="folder containing XAUUSD<TF>.csv files (default: current dir)")
    ap.add_argument("--out", default="strategy_lab.html")
    args = ap.parse_args(argv)

    files = discover_files(args.source)
    if not files:
        print(f"no M5–H4 csv files found in {args.source!r} "
              f"(expected names ending in {', '.join(t + '.csv' for t in APP_TIMEFRAMES)})")
        return 2
    out = write_lab(args.out, files)
    print(f"Embedded: {', '.join(sorted(files))}")
    print(f"Strategy Lab written to {out} — open it in a browser.")
    return 0


_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Gold Strategy Lab</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<style>
 :root{
   --bg:#0c0f14; --panel:#141a22; --panel2:#0f141b; --line:#262d38; --line2:#333c4a;
   --fg:#e6edf3; --mut:#8b97a7; --faint:#5b6675;
   --up:#3fb950; --down:#f0524a; --long:#58a6ff; --short:#e3a008;
   --win:#3fb950; --loss:#f0524a; --gold:#e8b339; --accent:#7ee0c9;
   --serif:'Fraunces',Georgia,serif; --mono:'JetBrains Mono',ui-monospace,Consolas,monospace;
 }
 *{box-sizing:border-box}
 body{margin:0;background:radial-gradient(1200px 600px at 70% -10%,#16202c 0%,var(--bg) 60%);
   color:var(--fg);font:13px/1.5 var(--mono);min-height:100vh}
 a{color:var(--long)}
 header{padding:18px 24px 10px;display:flex;gap:16px;align-items:flex-end;flex-wrap:wrap;
   border-bottom:1px solid var(--line)}
 header .title{font-family:var(--serif);font-weight:600;font-size:26px;letter-spacing:.2px;
   background:linear-gradient(90deg,var(--gold),#f5d77a);-webkit-background-clip:text;
   background-clip:text;color:transparent;line-height:1}
 header .sub{color:var(--mut);font-size:12px}
 .wrap{padding:18px 24px 60px;max-width:1500px;margin:0 auto}
 .mut{color:var(--mut)} .faint{color:var(--faint)}
 .note{background:linear-gradient(90deg,rgba(232,179,57,.08),rgba(232,179,57,.01));
   border:1px solid rgba(232,179,57,.25);border-left:3px solid var(--gold);
   padding:10px 14px;border-radius:8px;margin:14px 0;color:#cdb88a;font-size:12px}
 /* controls */
 .controls{display:flex;gap:18px;flex-wrap:wrap;align-items:flex-end;padding:14px 16px;
   background:var(--panel);border:1px solid var(--line);border-radius:12px;margin:12px 0}
 .ctl{display:flex;flex-direction:column;gap:5px}
 .ctl label{font-size:10px;text-transform:uppercase;letter-spacing:.7px;color:var(--mut)}
 select,.seg button{font-family:var(--mono);font-size:12px}
 select{background:var(--panel2);color:var(--fg);border:1px solid var(--line2);
   border-radius:8px;padding:6px 10px;min-width:120px}
 .seg{display:flex;border:1px solid var(--line2);border-radius:8px;overflow:hidden}
 .seg button{background:var(--panel2);color:var(--mut);border:0;padding:6px 11px;cursor:pointer}
 .seg button+button{border-left:1px solid var(--line2)}
 .seg button.on{background:linear-gradient(180deg,#243140,#1a232e);color:var(--fg);box-shadow:inset 0 -2px 0 var(--gold)}
 /* layer chips */
 .layers{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0 4px}
 .chip{display:inline-flex;gap:6px;align-items:center;cursor:pointer;user-select:none;
   background:var(--panel2);border:1px solid var(--line);border-radius:999px;padding:4px 11px;
   font-size:11px;color:var(--mut)}
 .chip input{display:none}
 .chip.on{color:var(--fg);border-color:var(--line2);background:var(--panel)}
 .sw{width:11px;height:11px;border-radius:3px;display:inline-block}
 /* cards */
 .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:14px 0}
 .card{background:linear-gradient(180deg,var(--panel),var(--panel2));border:1px solid var(--line);
   border-radius:12px;padding:13px 15px}
 .card .k{font-size:10px;text-transform:uppercase;letter-spacing:.7px;color:var(--mut)}
 .card .v{font-family:var(--serif);font-weight:600;font-size:26px;margin-top:4px;line-height:1}
 .card .s{font-size:11px;color:var(--faint);margin-top:3px}
 .pos{color:var(--win)} .neg{color:var(--loss)}
 /* verdict */
 .verdict{border-radius:12px;padding:14px 18px;margin:14px 0;border:1px solid var(--line);
   font-size:13px;display:flex;gap:14px;align-items:center;flex-wrap:wrap}
 .verdict.good{background:rgba(63,185,80,.08);border-color:rgba(63,185,80,.35)}
 .verdict.bad{background:rgba(240,82,74,.07);border-color:rgba(240,82,74,.32)}
 .verdict.warn{background:rgba(232,179,57,.07);border-color:rgba(232,179,57,.3)}
 .verdict b{font-family:var(--serif);font-size:15px}
 /* chart */
 .chartwrap{position:relative;background:var(--panel2);border:1px solid var(--line);
   border-radius:12px;padding:8px}
 canvas{width:100%;display:block;border-radius:8px}
 .legend{display:flex;gap:16px;flex-wrap:wrap;font-size:11px;color:var(--mut);padding:8px 6px 2px}
 .legend span{display:inline-flex;gap:5px;align-items:center}
 /* tables */
 .panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin-top:16px}
 .panel h2{font-family:var(--serif);font-weight:600;font-size:15px;margin:0 0 10px;color:var(--fg)}
 .panel h2 .mut{font-family:var(--mono);font-size:11px;font-weight:400}
 table{border-collapse:collapse;width:100%;font-size:12px}
 th,td{padding:6px 9px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
 th:first-child,td:first-child{text-align:left}
 th{color:var(--mut);font-weight:500;font-size:10px;text-transform:uppercase;letter-spacing:.5px}
 tr:hover td{background:rgba(255,255,255,.02)}
 .badge{padding:1px 7px;border-radius:5px;font-size:10px;font-weight:500}
 .b-long{background:rgba(88,166,255,.16);color:var(--long)}
 .b-short{background:rgba(227,160,8,.18);color:var(--short)}
 .b-win{background:rgba(63,185,80,.16);color:var(--win)}
 .b-loss{background:rgba(240,82,74,.16);color:var(--loss)}
 .b-unresolved{background:rgba(139,151,167,.16);color:var(--mut)}
 .b-keep{background:rgba(63,185,80,.12);color:var(--win)}
 .b-skip{background:rgba(139,151,167,.16);color:var(--mut)}
 .grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px}
 @media(max-width:900px){.grid2{grid-template-columns:1fr}}
 .barwrap{display:flex;align-items:center;gap:8px}
 .bar{height:8px;border-radius:4px;background:var(--line)}
 #tip{position:fixed;pointer-events:none;background:#0a0e13;border:1px solid var(--line2);
   border-radius:8px;padding:7px 9px;font-size:11px;display:none;z-index:20;white-space:pre;
   box-shadow:0 6px 24px rgba(0,0,0,.5)}
 .best{background:linear-gradient(90deg,rgba(126,224,201,.1),transparent);border-left:3px solid var(--accent)}
 .scrollx{overflow-x:auto}
 .clk{cursor:pointer}
 tr.clk:hover td{background:rgba(126,224,201,.07)}
 /* trade detail modal */
 #modal{position:fixed;inset:0;background:rgba(6,9,13,.78);backdrop-filter:blur(3px);
   display:none;z-index:50;overflow:auto;padding:28px 16px}
 #modal.on{display:block}
 .sheet{max-width:1040px;margin:0 auto;background:linear-gradient(180deg,var(--panel),var(--panel2));
   border:1px solid var(--line2);border-radius:16px;box-shadow:0 24px 80px rgba(0,0,0,.6);overflow:hidden}
 .sheet>header{padding:16px 22px;border-bottom:1px solid var(--line);display:flex;align-items:flex-end;gap:14px}
 .sheet .htitle{font-family:var(--serif);font-weight:600;font-size:22px;line-height:1.1}
 .sheet .hclose{margin-left:auto;cursor:pointer;color:var(--mut);border:1px solid var(--line2);
   border-radius:8px;padding:5px 11px;background:var(--panel2);font-size:11px}
 .sheet .hclose:hover{color:var(--fg)}
 .sbody{padding:18px 22px}
 #dcanvas{width:100%;display:block;border-radius:10px;background:var(--panel2);border:1px solid var(--line)}
 .steps{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px;margin:16px 0}
 .step{background:var(--panel2);border:1px solid var(--line);border-radius:10px;padding:11px 13px}
 .step .n{font-family:var(--serif);font-size:13px;color:var(--gold);font-weight:600}
 .step .b{margin-top:5px;color:var(--fg);font-size:12px;line-height:1.45}
 .ticket{border:1px solid var(--line2);border-radius:10px;overflow:hidden;display:grid;
   grid-template-columns:1fr 1fr;align-content:start}
 .ticket>div{padding:9px 13px;border-bottom:1px solid var(--line)}
 .ticket .tk{color:var(--mut);font-size:10px;text-transform:uppercase;letter-spacing:.6px}
 .ticket .tv{font-family:var(--serif);font-size:17px;margin-top:2px;line-height:1}
 .rrbar{display:flex;height:13px;border-radius:6px;overflow:hidden;margin-top:6px;border:1px solid var(--line2)}
 .rrbar .risk{background:var(--loss)} .rrbar .rew{background:var(--win)}
</style>
</head>
<body>
<header>
 <div>
   <div class="title">Gold Strategy Lab</div>
 </div>
 <div class="sub" style="margin-left:auto" id="genline"></div>
</header>
<div class="wrap">
 <div class="controls">
   <div class="ctl"><label>Timeframe</label><div class="seg" id="tfseg"></div></div>
   <div class="ctl"><label>Strategy</label><select id="stratsel"></select></div>
   <div class="ctl"><label>Risk : Reward</label><div class="seg" id="rrseg"></div></div>
   <div class="ctl"><label>Filters (stack with AND)</label><div class="seg" id="filtseg">
     <button data-f="trend">Trend</button><button data-f="ma" id="mabtn">MA</button><button data-f="rsi" id="rsibtn">RSI</button></div></div>
   <div class="ctl"><label>From</label><select id="fromsel"></select></div>
   <div class="ctl"><label>To</label><select id="tosel"></select></div>
   <div class="ctl"><label>&nbsp;</label><div class="seg"><button id="resetbtn">Reset period</button></div></div>
 </div>

 <div class="controls">
   <div class="ctl"><label>Initial Balance ($)</label><input type="number" id="initbalance" value="1000" min="100" step="100"></div>
   <div class="ctl"><label>Lot Size (standard = 0.1)</label><input type="number" id="lotsize" value="0.1" min="0.01" step="0.01" max="10"></div>
   <div class="ctl"><label>Breakeven Profit %</label><select id="breakevensel" style="width:100px">
     <option value="0">Disabled</option>
     <option value="20">20%</option>
     <option value="30">30%</option>
     <option value="40">40%</option>
     <option value="50">50%</option>
   </select></div>
 </div>

 <div id="stratinfo" class="note" style="border-left-color:var(--accent);background:linear-gradient(90deg,rgba(126,224,201,.07),transparent);color:#bfe6db"></div>

 <div class="layers" id="layers"></div>

 <div class="cards" id="cards"></div>
 <div class="verdict" id="verdict"></div>

 <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px;align-items:start">
   <div class="panel" style="margin:0;display:flex;flex-direction:column;max-height:420px">
     <h2 style="margin-top:0;margin-bottom:4px">Candlestick Chart</h2>
     <div style="font-size:12px;color:var(--mut);margin-bottom:12px" id="chartdaterange">Loading dates...</div>
     <canvas id="chart" height="420" style="width:100%;border:1px solid #30363d;border-radius:4px"></canvas>
   </div>
   <div class="panel" style="margin:0;display:flex;flex-direction:column;max-height:420px">
     <h2 style="margin-top:0;margin-bottom:4px">P&L Chart</h2>
     <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px">
       <div><span class="mut">Balance</span><div style="font-size:16px;font-weight:bold" id="moneycurrent">$1,000</div></div>
       <div><span class="mut">Return</span><div style="font-size:16px;font-weight:bold" id="moneyreturn">0%</div></div>
     </div>
     <canvas id="pnlchart" height="355" style="width:100%;border:1px solid #30363d;border-radius:4px"></canvas>
   </div>
 </div>

 <div class="faint" id="viewhint" style="padding:5px 6px 0;font-size:11px"></div>
 <div class="legend" id="legend"></div>

 <div class="panel">
   <h2>Money & P&L Summary</h2>
   <div style="display:grid;grid-template-columns:1fr 1fr 1fr 1fr;gap:12px">
     <div><span class="mut">Starting</span><div style="font-size:18px;font-weight:bold" id="moneystart">$1,000</div></div>
     <div><span class="mut">Current</span><div style="font-size:18px;font-weight:bold;color:var(--buy)" id="moneycurrent2">$1,000</div></div>
     <div><span class="mut">P&L</span><div style="font-size:18px;font-weight:bold" id="moneypnl">$0</div></div>
     <div><span class="mut">W/L Ratio</span><div style="font-size:18px;font-weight:bold" id="moneywl">-</div></div>
   </div>
 </div>

 <div class="panel">
   <h2>Setups <span class="mut" id="setupcount"></span></h2>
   <div class="scrollx" id="setups"></div>
 </div>

 <div class="grid2">
   <div class="panel"><h2>By hour of day <span class="mut">(entry hour, current settings)</span></h2><div class="scrollx" id="byhour"></div></div>
   <div class="panel"><h2>By direction</h2><div id="bydir"></div></div>
 </div>

 <div class="panel best">
   <h2>Avoid-losers optimizer <span class="mut">(best RR &times; trend-filter for this strategy &amp; timeframe)</span></h2>
   <div class="scrollx" id="optimizer"></div>
 </div>

 <div class="panel" id="badpanel" style="display:none">
   <h2>Bad rows skipped</h2><div id="bad"></div>
 </div>
</div>
<div id="modal"><div class="sheet">
  <header><div><div class="htitle" id="dtitle"></div><div class="sub mut" id="dsub"></div></div>
    <div class="hclose" id="dclose">close &times;</div></header>
  <div class="sbody">
    <canvas id="dcanvas" height="360"></canvas>
    <div class="legend" id="dlegend"></div>
    <div class="steps" id="dsteps"></div>
    <div class="grid2">
      <div class="ticket" id="dticket"></div>
      <div class="note" id="dnote" style="margin:0"></div>
    </div>
  </div>
</div></div>
<div id="tip"></div>
<script>
const DATA = /*__DATA__*/;
document.getElementById('genline').textContent = 'generated ' + DATA.generated;

// ---- state ----
const RRS = [[1,1],[1,2],[1,3],[2,1],[3,1]];
const LAYERS = [
  ['swings','Liquidity','#6e7681'], ['sweeps','Sweeps','#bc8cff'],
  ['fvg','FVG','#388bfd'], ['ifvg','Inverse FVG','#e3a008'],
  ['ob','Order block','#bc8cff'], ['breaker','Breaker','#7ee0c9'],
  ['structure','BOS / CHoCH','#f0524a'], ['sr','S/R zones','#8b97a7'],
  ['breakout','Breakout levels','#58a6ff'], ['ma','MA line','#d2a8ff'],
  ['setups','Trades (E/SL/TP)','#3fb950'],
];
const S = {
  tf: DATA.timeframes[0],
  strat: 'liquidity_imbalance',
  rr: [1,2],
  filters: {trend:false, ma:false, rsi:false},
  from: null, to: null,
  vStart: null, vSpan: null,   // chart viewport (candle index window); defaults to ~24h
  layers: {swings:1,sweeps:1,fvg:1,ifvg:0,ob:1,breaker:0,structure:1,sr:0,breakout:1,ma:0,setups:1},
};
// Marking lines/zones only span this many candles from their anchor, so turning
// on liquidity / OB / S/R doesn't smear lines across the whole chart.
const LEVEL_SPAN = 6;
// A setup survives the active filters (AND). null == "no opinion" == pass,
// mirroring filters.keep() in Python.
function passCombo(s, fl){
  if(fl.trend && !s.kept) return false;
  if(fl.ma && s.ma_ok===false) return false;
  if(fl.rsi && s.rsi_ok===false) return false;
  return true;
}
function passes(s){ return passCombo(s, S.filters); }
function anyFilter(){ return S.filters.trend||S.filters.ma||S.filters.rsi; }
function filterLabel(){
  const on=Object.keys(S.filters).filter(k=>S.filters[k]);
  return on.length?on.map(k=>k==='ma'?'MA':k==='rsi'?'RSI':'trend').join('+'):'none';
}

const cv = document.getElementById('chart'), ctx = cv.getContext('2d');
const tip = document.getElementById('tip');
let hover = -1;
const PAD = {l:62,r:14,t:14,b:24};

// --- Money & P&L tracking ---
let moneyState = {initBalance: 1000, lotSize: 0.1};
let pnlHistory = [];  // [{setupIndex, pnl, balance}, ...]
function updateMoneyInputs(){
  moneyState.initBalance = parseFloat(document.getElementById('initbalance').value) || 1000;
  moneyState.lotSize = parseFloat(document.getElementById('lotsize').value) || 0.1;
  recalculatePnL();
}
function recalculatePnL(){
  const candles = tfd().candles;
  pnlHistory = [];
  let balance = moneyState.initBalance;
  const breakeven = parseFloat(document.getElementById('breakevensel').value) || 0;
  VIEW.forEach((s, i) => {
    // XAUUSD P&L calculation: convert price units to pips, then calculate money
    // Gold: risk is in price units (0.22 = 22 pips since gold trades in 0.01)
    const risk_pips = Math.abs(s.entry - s.sl) / 0.01;  // convert to pips
    const pip_value = moneyState.lotSize * 1;  // $1 per pip per standard lot (0.1 lot = $0.1/pip)
    const rrMultiple = S.rr[1] / S.rr[0];
    let pnl = 0;
    let isWin = s.v === 'win';
    let isLoss = s.v === 'loss';

    if (isWin) {
      const winning_pnl = risk_pips * rrMultiple * pip_value;
      pnl = winning_pnl;
    } else if (isLoss) {
      const loss_pnl = -risk_pips * pip_value;
      // Apply breakeven: if loss would exceed breakeven %, convert to win
      if (breakeven > 0 && balance > moneyState.initBalance) {
        const profit_to_breakeven = (moneyState.initBalance * breakeven / 100);
        if (Math.abs(loss_pnl) < profit_to_breakeven) {
          pnl = 0;  // touch breakeven
          isLoss = false;
        } else {
          pnl = loss_pnl;
        }
      } else {
        pnl = loss_pnl;
      }
    }
    balance += pnl;
    pnlHistory.push({setupIndex: i, pnl, balance, entry: s.entry, close: candles[s.ei] ? candles[s.ei].c : null, risk_pips});
  });
  renderMoneyPanel();
}
function renderMoneyPanel(){
  const final = pnlHistory.length > 0 ? pnlHistory[pnlHistory.length - 1] : null;
  const pnl = final ? (final.balance - moneyState.initBalance) : 0;
  const ret = final ? ((pnl / moneyState.initBalance) * 100) : 0;
  const wins = VIEW.filter(s => s.v === 'win').length;
  const losses = VIEW.filter(s => s.v === 'loss').length;
  const wl = losses > 0 ? (wins / losses).toFixed(2) : (wins > 0 ? wins.toFixed(1) : '-');

  document.getElementById('moneystart').textContent = '$' + moneyState.initBalance.toFixed(2);
  document.getElementById('moneycurrent').textContent = '$' + (final ? final.balance.toFixed(2) : moneyState.initBalance.toFixed(2));
  document.getElementById('moneycurrent2').textContent = '$' + (final ? final.balance.toFixed(2) : moneyState.initBalance.toFixed(2));
  document.getElementById('moneypnl').textContent = (pnl >= 0 ? '+' : '') + '$' + pnl.toFixed(2);
  document.getElementById('moneyreturn').textContent = (ret >= 0 ? '+' : '') + ret.toFixed(1) + '%';
  document.getElementById('moneywl').textContent = wins + 'W / ' + losses + 'L = ' + wl;

  const pnlEl = document.getElementById('moneypnl');
  const retEl = document.getElementById('moneyreturn');
  if (pnlEl) { pnlEl.style.color = pnl >= 0 ? 'var(--buy)' : 'var(--sell)'; }
  if (retEl) { retEl.style.color = ret >= 0 ? 'var(--buy)' : 'var(--sell)'; }
  drawPnLChart();
}
function drawPnLChart(){
  const pcv = document.getElementById('pnlchart');
  if (!pcv) return;
  const pctx = pcv.getContext('2d', {antialias: true});
  const dpr = window.devicePixelRatio || 1;
  const rect = pcv.getBoundingClientRect();
  const w = rect.width;
  const h = rect.height;

  // Set canvas resolution for crisp rendering
  pcv.width = w * dpr;
  pcv.height = h * dpr;
  pctx.scale(dpr, dpr);

  pctx.fillStyle = '#0d1117';
  pctx.fillRect(0, 0, w, h);
  if (pnlHistory.length < 2) return;

  const pad = {l: 40, r: 20, t: 5, b: 25};
  const balances = pnlHistory.map(p => p.balance);
  const minB = Math.min(...balances, moneyState.initBalance);
  const maxB = Math.max(...balances, moneyState.initBalance);
  const range = maxB - minB || 1;
  const buffer = range * 0.1;

  const plotH = h - pad.t - pad.b;
  const plotW = w - pad.l - pad.r;
  const x = (i) => pad.l + (i / Math.max(1, pnlHistory.length - 1)) * plotW;
  const y = (bal) => pad.t + (1 - (bal - minB + buffer) / (range + buffer * 2)) * plotH;

  // Grid lines and labels
  pctx.strokeStyle = '#30363d';
  pctx.fillStyle = '#7d8590';
  pctx.font = '11px monospace';
  pctx.textAlign = 'right';
  for (let i = 0; i <= 4; i++) {
    const bal = minB + (range / 4) * i;
    const yy = y(bal);
    pctx.lineWidth = 0.5;
    pctx.setLineDash([2, 2]);
    pctx.beginPath();
    pctx.moveTo(pad.l, yy);
    pctx.lineTo(w - pad.r, yy);
    pctx.stroke();
    pctx.setLineDash([]);
    pctx.fillText('$' + bal.toFixed(0), pad.l - 5, yy + 4);
  }

  // Starting balance line (highlight)
  const startY = y(moneyState.initBalance);
  pctx.strokeStyle = '#3fb950';
  pctx.lineWidth = 1.5;
  pctx.setLineDash([6, 3]);
  pctx.beginPath();
  pctx.moveTo(pad.l, startY);
  pctx.lineTo(w - pad.r, startY);
  pctx.stroke();
  pctx.setLineDash([]);

  // Draw smooth P&L line with shadows/glow
  pctx.strokeStyle = '#3fb950';
  pctx.lineWidth = 3.5;
  pctx.lineCap = 'round';
  pctx.lineJoin = 'round';
  pctx.beginPath();
  for (let i = 0; i < pnlHistory.length; i++) {
    const xx = x(i);
    const yy = y(pnlHistory[i].balance);
    if (i === 0) pctx.moveTo(xx, yy);
    else pctx.lineTo(xx, yy);
  }
  pctx.stroke();

  // Draw points (wins/losses colored)
  pnlHistory.forEach((p, i) => {
    const xx = x(i);
    const yy = y(p.balance);
    const isWin = p.pnl >= 0;
    pctx.fillStyle = isWin ? '#3fb950' : '#f85149';
    pctx.beginPath();
    pctx.arc(xx, yy, 4, 0, Math.PI * 2);
    pctx.fill();
    // White outline for clarity
    pctx.strokeStyle = '#fff';
    pctx.lineWidth = 1;
    pctx.stroke();
  });

  // Legend/info
  pctx.fillStyle = '#8b9399';
  pctx.font = '10px monospace';
  pctx.textAlign = 'left';
  pctx.fillText('Equity Curve', pad.l + 5, h - 8);
}
document.getElementById('initbalance').addEventListener('change', updateMoneyInputs);
document.getElementById('lotsize').addEventListener('change', updateMoneyInputs);
document.getElementById('breakevensel').addEventListener('change', ()=>{recalculatePnL(); renderMoneyPanel();});

function tfd(){ return DATA.data[S.tf]; }
function fmt(x){ return x==null?'-':(+x).toFixed(2); }
function pct(x){ return (x*100).toFixed(1)+'%'; }
function rrMult(){ return S.rr[1]/S.rr[0]; }   // reward per 1 risk

// ---- build controls ----
const tfseg = document.getElementById('tfseg');
DATA.timeframes.forEach(tf=>{
  const b=document.createElement('button'); b.textContent=tf; b.dataset.tf=tf;
  if(tf===S.tf) b.classList.add('on');
  b.onclick=()=>{
    const prevFrom = S.from, prevTo = S.to;  // preserve dates
    S.tf=tf; S.vStart=S.vSpan=null;  // don't reset S.from/S.to
    setSeg(tfseg,'tf',tf); fillPeriods();
    // Try to keep same dates if they exist in new timeframe
    const dates = tfd().dates;
    if (prevFrom && prevTo) {
      if (dates.includes(prevFrom)) S.from = prevFrom;
      if (dates.includes(prevTo)) S.to = prevTo;
    }
    recompute();
  };
  tfseg.appendChild(b);
});
const stratsel = document.getElementById('stratsel');
Object.keys(DATA.labels).forEach(k=>{
  const o=document.createElement('option'); o.value=k; o.textContent=DATA.labels[k]; stratsel.appendChild(o);
});
stratsel.value=S.strat; stratsel.onchange=()=>{S.strat=stratsel.value; recompute();};

const rrseg = document.getElementById('rrseg');
RRS.forEach(rr=>{
  const b=document.createElement('button'); b.textContent=rr[0]+':'+rr[1]; b.dataset.rr=rr.join(':');
  if(rr[0]===S.rr[0]&&rr[1]===S.rr[1]) b.classList.add('on');
  b.onclick=()=>{S.rr=rr; setSeg(rrseg,'rr',rr.join(':')); recompute();};
  rrseg.appendChild(b);
});
document.getElementById('filtseg').querySelectorAll('button').forEach(b=>{
  b.onclick=()=>{ const k=b.dataset.f; S.filters[k]=!S.filters[k];
    b.classList.toggle('on', S.filters[k]); recompute(); };
});
// Label the MA / RSI buttons with the periods baked into the payload.
document.getElementById('mabtn').textContent = 'MA'+tfd().ma_period;
document.getElementById('rsibtn').textContent = 'RSI'+tfd().rsi_period;
function setSeg(seg,key,val){ seg.querySelectorAll('button').forEach(b=>b.classList.toggle('on', b.dataset[key]===val)); }

const layersEl = document.getElementById('layers');
LAYERS.forEach(([id,label,color])=>{
  const l=document.createElement('label'); l.className='chip'+(S.layers[id]?' on':'');
  l.innerHTML=`<input type="checkbox" ${S.layers[id]?'checked':''}><span class="sw" style="background:${color}"></span>${label}`;
  l.querySelector('input').onchange=e=>{S.layers[id]=e.target.checked?1:0; l.classList.toggle('on',e.target.checked); draw();};
  layersEl.appendChild(l);
});
const legend=document.getElementById('legend');
legend.innerHTML = LAYERS.map(([id,label,color])=>`<span><span class="sw" style="background:${color}"></span>${label}</span>`).join('');

const fromsel=document.getElementById('fromsel'), tosel=document.getElementById('tosel');
function fillPeriods(){
  const dates=tfd().dates;
  fromsel.innerHTML=''; tosel.innerHTML='';
  dates.forEach(d=>{
    fromsel.appendChild(new Option(d,d)); tosel.appendChild(new Option(d,d));
  });
  // default to a readable window: last ~8 sessions (or all if fewer)
  const startIdx = Math.max(0, dates.length-8);
  S.from = S.from||dates[startIdx]; S.to = S.to||dates[dates.length-1];
  fromsel.value=S.from; tosel.value=S.to;
}
fromsel.onchange=()=>{S.from=fromsel.value; S.vStart=S.vSpan=null; recompute();};
tosel.onchange=()=>{S.to=tosel.value; S.vStart=S.vSpan=null; recompute();};
document.getElementById('resetbtn').onclick=()=>{
  const dates=tfd().dates; S.from=dates[0]; S.to=dates[dates.length-1];
  S.vStart=S.vSpan=null; fromsel.value=S.from; tosel.value=S.to; recompute();
};

// ---- simulation (mirror of simulate.simulate_outcome) ----
function tpOf(s){
  const risk=Math.abs(s.entry-s.sl), m=rrMult();
  return s.dir==='long' ? s.entry+risk*m : s.entry-risk*m;
}
function resolve(s, candles){
  const tp=tpOf(s);
  for(let i=s.resolve_index; i<candles.length; i++){
    const c=candles[i];
    let hitSL,hitTP;
    if(s.dir==='long'){ hitSL=c.l<=s.sl; hitTP=c.h>=tp; }
    else { hitSL=c.h>=s.sl; hitTP=c.l<=tp; }
    if(hitSL&&hitTP) return {v:'loss',ei:i,ep:s.sl,tp};
    if(hitTP) return {v:'win',ei:i,ep:tp,tp};
    if(hitSL) return {v:'loss',ei:i,ep:s.sl,tp};
  }
  return {v:'unresolved',ei:null,ep:null,tp};
}
function rOf(v){ return v==='win'?rrMult():(v==='loss'?-1:0); }

// in-period filter on the trigger/entry candle's date
function inPeriod(idx){ const c=tfd().candles[idx]; return c.d>=S.from && c.d<=S.to; }

// update the date range display for the candlestick chart
function updateDateRange(){
  const from = S.from || '____-__-__';
  const to = S.to || '____-__-__';
  // Convert YYYY-MM-DD to YYYY.MM.DD format
  const formatDate = (dateStr) => dateStr.replace(/-/g, '.');
  const el = document.getElementById('chartdaterange');
  if(el) el.textContent = `showing dates ${formatDate(from)} to ${formatDate(to)}`;
}

// resolved + filtered view of current strategy
let VIEW = [];
function recompute(){
  const d=tfd(), candles=d.candles;
  const raw=d.strategies[S.strat]||[];
  VIEW = raw.filter(s=> inPeriod(s.entry_index) && passes(s))
    .map(s=>{ const r=resolve(s,candles); const hour=candles[s.entry_index].t.slice(11,13);
      return {...s, ...r, r:rOf(r.v), hour}; });
  recalculatePnL();
  updateDateRange();
  renderAll();
}

function statsOf(rows){
  const res=rows.filter(s=>s.v!=='unresolved');
  const wins=res.filter(s=>s.v==='win').length, losses=res.filter(s=>s.v==='loss').length;
  const totalR=res.reduce((a,s)=>a+s.r,0);
  return {n:rows.length, resolved:res.length, wins, losses,
    unresolved:rows.length-res.length,
    wr: res.length?wins/res.length:0,
    totalR, exp: res.length?totalR/res.length:0};
}

// ---- render: cards + verdict ----
function renderCards(st){
  const cls=st.totalR>=0?'pos':'neg';
  const final = pnlHistory.length > 0 ? pnlHistory[pnlHistory.length - 1] : null;
  const pnl = final ? (final.balance - moneyState.initBalance) : 0;
  const pnlCls = pnl >= 0 ? 'pos' : 'neg';
  const cards=[
    ['Trades', st.n, st.unresolved?`${st.unresolved} unresolved`:'all resolved'],
    ['Win rate', pct(st.wr), `${st.wins}W / ${st.losses}L`],
    ['Total', st.totalR.toFixed(2)+'R', 'sum of outcomes', cls],
    ['Expectancy', st.exp.toFixed(3)+'R', 'per trade', cls],
    ['RR', S.rr[0]+':'+S.rr[1], `reward = ${rrMult().toFixed(2)}× risk`],
    ['P&L', (pnl >= 0 ? '+' : '') + '$' + pnl.toFixed(2), 'money outcome', pnlCls],
  ];
  document.getElementById('cards').innerHTML = cards.map(([k,v,s,c])=>
    `<div class="card"><div class="k">${k}</div><div class="v ${c||''}">${v}</div><div class="s">${s}</div></div>`).join('');
}
function renderVerdict(st){
  const el=document.getElementById('verdict'); let cls='warn', msg;
  if(st.resolved<5){ cls='warn'; msg=`<b>Thin sample.</b> Only ${st.resolved} resolved trades in this window &mdash; widen the period before trusting the edge.`; }
  else if(st.exp>0.05 && st.totalR>0){ cls='good';
    msg=`<b>Positive expectancy.</b> ${st.exp.toFixed(3)}R/trade over ${st.resolved} trades (${pct(st.wr)} win). At ${S.rr[0]}:${S.rr[1]} you needed ${pct(1/(1+rrMult()))} just to break even.`; }
  else if(st.totalR<0){ cls='bad';
    msg=`<b>Bleeding.</b> ${st.totalR.toFixed(2)}R over ${st.resolved} trades. Break-even win rate at ${S.rr[0]}:${S.rr[1]} is ${pct(1/(1+rrMult()))}; you're at ${pct(st.wr)}. Stack a filter (trend / MA / RSI) or change RR &mdash; the optimizer below ranks every combination.`; }
  else { cls='warn'; msg=`<b>Roughly flat.</b> ${st.exp.toFixed(3)}R/trade. The edge (if any) is small &mdash; check the hour/direction breakdowns for where it leaks.`; }
  el.className='verdict '+cls; el.innerHTML=msg;
}

// ---- breakdown tables ----
function breakdown(rows, keyf, label){
  const groups={};
  rows.forEach(s=>{ const k=keyf(s); (groups[k]=groups[k]||[]).push(s); });
  const keys=Object.keys(groups).sort();
  let h=`<table><tr><th>${label}</th><th>Trades</th><th>W/L</th><th>Win%</th><th>Total R</th><th>Exp</th><th></th></tr>`;
  keys.forEach(k=>{ const st=statsOf(groups[k]); const c=st.totalR>=0?'pos':'neg';
    const w=Math.min(100,Math.abs(st.totalR)*12);
    h+=`<tr><td>${k}</td><td>${st.n}</td><td>${st.wins}/${st.losses}</td><td>${pct(st.wr)}</td>
      <td class="${c}">${st.totalR.toFixed(2)}R</td><td class="${c}">${st.exp.toFixed(3)}</td>
      <td><div class="barwrap"><div class="bar" style="width:${w}px;background:${st.totalR>=0?'var(--win)':'var(--loss)'}"></div></div></td></tr>`; });
  return h+'</table>';
}

// ---- optimizer: sweep RR x filter-combo for current strat/tf in period ----
const COMBOS = [
  ['none', {}], ['trend', {trend:1}], ['MA', {ma:1}], ['RSI', {rsi:1}],
  ['trend+MA', {trend:1,ma:1}], ['trend+RSI', {trend:1,rsi:1}],
  ['MA+RSI', {ma:1,rsi:1}], ['trend+MA+RSI', {trend:1,ma:1,rsi:1}],
];
function renderOptimizer(){
  const d=tfd(), candles=d.candles, raw=d.strategies[S.strat]||[];
  const inP=raw.filter(s=>inPeriod(s.entry_index));
  let rows=[];
  RRS.forEach(rr=>{ const m=rr[1]/rr[0];
    COMBOS.forEach(([label,fl])=>{
      const sub=inP.filter(s=>passCombo(s,fl));
      const res=sub.map(s=>{ const tp=s.dir==='long'?s.entry+Math.abs(s.entry-s.sl)*m:s.entry-Math.abs(s.entry-s.sl)*m;
        let v='unresolved';
        for(let i=s.resolve_index;i<candles.length;i++){const c=candles[i];
          let hs,ht; if(s.dir==='long'){hs=c.l<=s.sl;ht=c.h>=tp;}else{hs=c.h>=s.sl;ht=c.l<=tp;}
          if(hs&&ht){v='loss';break;} if(ht){v='win';break;} if(hs){v='loss';break;}}
        return v;}).filter(v=>v!=='unresolved');
      const wins=res.filter(v=>v==='win').length, losses=res.length-wins;
      const totalR=wins*m-losses;
      rows.push({rr:rr[0]+':'+rr[1], f:label, n:res.length, wins, losses,
        wr:res.length?wins/res.length:0, totalR, exp:res.length?totalR/res.length:0});
    });
  });
  // Need a credible sample before crowning a winner, else a lone 1/0 wins.
  rows=rows.filter(r=>r.n>0);
  const ranked=[...rows].filter(r=>r.n>=5).sort((a,b)=>b.exp-a.exp);
  const best=ranked[0];
  const shown=(best?ranked:rows.sort((a,b)=>b.exp-a.exp)).slice(0,12);
  let h=`<table><tr><th>RR</th><th>Filter</th><th>Trades</th><th>W/L</th><th>Win%</th><th>Total R</th><th>Exp/trade</th></tr>`;
  shown.forEach((r,i)=>{ const c=r.totalR>=0?'pos':'neg'; const isBest=best&&r===best;
    h+=`<tr class="${isBest?'best':''}"><td>${r.rr}${isBest?' ★':''}</td><td>${r.f}</td>
      <td>${r.n}</td><td>${r.wins}/${r.losses}</td><td>${pct(r.wr)}</td>
      <td class="${c}">${r.totalR.toFixed(2)}R</td><td class="${c}">${r.exp.toFixed(3)}</td></tr>`; });
  h+='</table>';
  const head = best
    ? `<div class="mut" style="margin-bottom:8px">Best in this window (≥ 5 trades): <b style="color:var(--accent)">${best.rr}</b> &times; <b style="color:var(--accent)">${best.f}</b> &rarr; ${best.exp.toFixed(3)}R/trade over ${best.n} trades.</div>`
    : `<div class="mut" style="margin-bottom:8px">No combo reaches 5 resolved trades in this window &mdash; widen the period.</div>`;
  document.getElementById('optimizer').innerHTML=head+h;
}

// ---- strategy description + best-setup recommendation (cached per strategy) ----
function simStrat(candles, setups, m){
  let wins=0, losses=0;
  setups.forEach(s=>{ const tp=s.dir==='long'?s.entry+Math.abs(s.entry-s.sl)*m:s.entry-Math.abs(s.entry-s.sl)*m;
    for(let i=s.resolve_index;i<candles.length;i++){const c=candles[i];
      let hs,ht; if(s.dir==='long'){hs=c.l<=s.sl;ht=c.h>=tp;}else{hs=c.h>=s.sl;ht=c.l<=tp;}
      if(hs&&ht){losses++;return;} if(ht){wins++;return;} if(hs){losses++;return;}}
  });
  const res=wins+losses, totalR=wins*m-losses;
  return {n:res, wins, losses, totalR, wr:res?wins/res:0, exp:res?totalR/res:0};
}
const _bestCache={};
function bestSetup(){
  const cacheKey = S.strat + '_' + JSON.stringify(S.filters);
  if(_bestCache[cacheKey]!==undefined) return _bestCache[cacheKey];
  let best=null;
  DATA.timeframes.forEach(tf=>{ const d=DATA.data[tf], setups=d.strategies[S.strat]||[];
    RRS.forEach(rr=>{
      const filtered = setups.filter(s => passCombo(s, S.filters));
      const st=simStrat(d.candles, filtered, rr[1]/rr[0]);
      if(st.n>=10 && st.totalR>0 && (!best || st.exp>best.exp)) best={tf, rr:rr[0]+':'+rr[1], ...st};
    });
  });
  _bestCache[cacheKey]=best; return best;
}
function renderStratInfo(){
  const desc=DATA.descriptions[S.strat]||'';
  const b=bestSetup();
  const line2 = b
    ? `<b style="color:var(--accent)">Best setup for this strategy:</b> ${b.tf} at ${b.rr} &mdash; `
      +`${pct(b.wr)} win, ${b.exp.toFixed(3)}R/trade over ${b.n} resolved trades `
      +`<span class="faint">(highest expectancy across all timeframes &times; RR, hindsight on the full sample).</span>`
    : `<span class="faint">No timeframe &times; RR combo clears 10 resolved profitable trades for this strategy on the embedded data.</span>`;
  document.getElementById('stratinfo').innerHTML = `<div style="margin-bottom:6px">${desc}</div>${line2}`;
}

// ---- setups table ----
function flagBadge(label, val, title){
  // val: true -> kept, false -> skipped, null/undefined -> no opinion (warm-up)
  if(val===null||val===undefined)
    return `<span class="badge b-skip" style="opacity:.4" title="${title||'no data'}">${label}?</span>`;
  return `<span class="badge ${val?'b-keep':'b-loss'}" title="${title||''}">${label}</span>`;
}
function renderSetups(){
  const candles=tfd().candles;
  let h=`<table><tr><th>#</th><th>Dir</th><th>Trigger @ time</th><th>Context</th>
    <th>Entry</th><th>SL</th><th>TP</th><th>Verdict</th><th>Profit</th><th>R</th><th>Filters</th></tr>`;
  VIEW.forEach((s,i)=>{
    const tci=s.trigger_index;
    const flags = flagBadge('trend', s.kept, s.reason) + ' '
                + flagBadge('MA', s.ma_ok) + ' '
                + flagBadge('RSI', s.rsi_ok);
    const pnlEntry = pnlHistory[i];
    const profitStr = pnlEntry ? (pnlEntry.pnl >= 0 ? '+$' : '-$') + Math.abs(pnlEntry.pnl).toFixed(2) : '-';
    const profitClass = pnlEntry ? (pnlEntry.pnl >= 0 ? 'pos' : 'neg') : '';
    h+=`<tr class="clk" data-i="${i}" title="click for the trade-detail slide"><td>${i+1}</td>
      <td><span class="badge b-${s.dir}">${s.dir}</span></td>
      <td>${fmt(s.trigger_level)} <span class="faint">@ ${candles[tci].t}</span></td>
      <td class="mut">${s.zone?s.zone.kind+' ['+fmt(s.zone.bottom)+'–'+fmt(s.zone.top)+']':s.note}</td>
      <td>${fmt(s.entry)}</td><td>${fmt(s.sl)}</td><td>${fmt(s.tp)}</td>
      <td><span class="badge b-${s.v}">${s.v}</span></td>
      <td class="${profitClass}">${profitStr}</td>
      <td class="${s.r>=0?'pos':'neg'}">${s.r.toFixed(2)}R</td>
      <td>${flags}</td></tr>`;
  });
  const host=document.getElementById('setups');
  host.innerHTML=h+'</table>';
  host.querySelectorAll('tr.clk').forEach(tr=>{ tr.onclick=()=>openDetail(VIEW[+tr.dataset.i]); });
  document.getElementById('setupcount').textContent=`(${VIEW.length} in window, filters: ${filterLabel()} · click a row for detail)`;
}

function renderAll(){
  const st=statsOf(VIEW);
  renderCards(st); renderVerdict(st);
  document.getElementById('byhour').innerHTML=breakdown(VIEW,s=>s.hour+':00','Hour');
  document.getElementById('bydir').innerHTML=breakdown(VIEW,s=>s.dir,'Direction');
  renderStratInfo();
  renderOptimizer(); renderSetups();
  const bad=DATA.bad[S.tf]||[];
  const bp=document.getElementById('badpanel');
  if(bad.length){bp.style.display='block';
    document.getElementById('bad').innerHTML='<table><tr><th>Line</th><th>Reason</th></tr>'+
      bad.map(b=>`<tr><td>${b.line}</td><td>${b.reason}</td></tr>`).join('')+'</table>';}
  else bp.style.display='none';
  resize();
}

// ---- chart ----
function css(v){return getComputedStyle(document.documentElement).getPropertyValue(v).trim();}
let geom=null;
// The period selector [from,to] sets the data/stats window; the chart shows a
// movable ~24h viewport *inside* that window (pan = drag, zoom = wheel).
function periodBounds(){
  const cs=tfd().candles; let a=0,b=cs.length-1;
  while(a<cs.length && cs[a].d<S.from) a++;
  while(b>0 && cs[b].d>S.to) b--;
  return [a,Math.max(a,b)];
}
function barsPerDay(){
  const d=tfd(); if(d._bpd) return d._bpd;
  const m={}; d.candles.forEach(c=>{ m[c.d]=(m[c.d]||0)+1; });
  const vals=Object.values(m).filter(v=>v>1);
  d._bpd=Math.max(20, vals.length?Math.max(...vals):60); return d._bpd;
}
function initViewport(force){
  const [pa,pb]=periodBounds(); const periodLen=pb-pa+1;
  if(force||S.vSpan==null) S.vSpan=Math.min(barsPerDay(), periodLen);
  S.vSpan=Math.max(10, Math.min(S.vSpan, periodLen));
  if(force||S.vStart==null) S.vStart=pb-S.vSpan+1;   // default: most recent 24h
  S.vStart=Math.max(pa, Math.min(S.vStart, pb-S.vSpan+1));
}
function visibleRange(){
  initViewport(false); const [,pb]=periodBounds();
  const a=S.vStart, b=Math.min(a+S.vSpan-1, pb);
  return [a,Math.max(a,b)];
}
function panBy(dCandles){ const [pa,pb]=periodBounds();
  S.vStart=Math.max(pa, Math.min(S.vStart+dCandles, pb-S.vSpan+1)); draw(); }
function zoomBy(factor, anchorFrac){ const [pa,pb]=periodBounds(); const periodLen=pb-pa+1;
  const old=S.vSpan; let span=Math.round(old*factor);
  span=Math.max(10, Math.min(periodLen, span));
  const anchor=S.vStart + (anchorFrac==null?0.5:anchorFrac)*old;
  S.vStart=Math.round(anchor - (anchorFrac==null?0.5:anchorFrac)*span);
  S.vSpan=span; S.vStart=Math.max(pa, Math.min(S.vStart, pb-span+1)); draw();
  updateViewHint(); }
function updateViewHint(){ const [pa,pb]=periodBounds(); const cs=tfd().candles;
  const a=S.vStart, b=Math.min(a+S.vSpan-1, pb); const el=document.getElementById('viewhint');
  if(el&&cs[a]&&cs[b]) el.textContent=`viewing ${cs[a].t} → ${cs[b].t}  (${b-a+1} bars · drag to pan, scroll to zoom)`; }
function buildGeom(){
  const cs=tfd().candles, [a,b]=visibleRange(); const view=cs.slice(a,b+1);
  const W=cv.clientWidth, H=520;
  let lo=Infinity,hi=-Infinity; view.forEach(c=>{lo=Math.min(lo,c.l);hi=Math.max(hi,c.h);});
  if(!isFinite(lo)){lo=0;hi=1;}
  const pad=(hi-lo)*0.06||1; lo-=pad; hi+=pad;
  const px=W-PAD.l-PAD.r, ph=H-PAD.t-PAD.b, n=view.length;
  const x=i=>PAD.l + (n<=1?px/2:((i-a)/(n-1))*px);
  const y=p=>PAD.t + (1-(p-lo)/(hi-lo))*ph;
  const cw=Math.max(1.5, px/Math.max(1,n)*0.7);
  geom={a,b,view,W,H,lo,hi,x,y,cw,px,ph,xr:[PAD.l,W-PAD.r]};
}
function resize(){ cv.width=cv.clientWidth*devicePixelRatio; cv.height=520*devicePixelRatio;
  ctx.setTransform(devicePixelRatio,0,0,devicePixelRatio,0,0); draw(); }
window.addEventListener('resize', resize);

function vis(i){ return i>=geom.a && i<=geom.b; }
function draw(){
  if(!tfd()) return; buildGeom();
  const {a,b,view,W,H,x,y,cw,lo,hi}=geom; const cs=tfd().candles;
  ctx.clearRect(0,0,W,H);
  ctx.strokeStyle=css('--line'); ctx.fillStyle=css('--mut'); ctx.font='10px '+css('--mono');
  for(let g=0;g<=5;g++){const p=lo+(hi-lo)*g/5,yy=y(p);
    ctx.globalAlpha=.35;ctx.beginPath();ctx.moveTo(PAD.l,yy);ctx.lineTo(W-PAD.r,yy);ctx.stroke();
    ctx.globalAlpha=1;ctx.fillText(p.toFixed(1),6,yy+3);}
  // Draw date separators and time labels
  let lastDate = null;
  const step=Math.max(1,Math.floor(view.length/8));
  ctx.globalAlpha=0.5;
  for(let i=0;i<view.length;i++){
    const c=view[i];
    if(c.d!==lastDate){
      // Draw vertical separator for new date
      ctx.strokeStyle=css('--line2');ctx.setLineDash([2,2]);
      ctx.beginPath();ctx.moveTo(x(c.i),PAD.t);ctx.lineTo(x(c.i),H-PAD.b);ctx.stroke();
      ctx.setLineDash([]);
      // Write date at separator
      ctx.globalAlpha=0.7;ctx.fillText(c.d, x(c.i)-35, PAD.t-2);
      lastDate=c.d;
    }
  }
  ctx.globalAlpha=1;
  // Draw time labels for intraday (skip date)
  for(let i=0;i<view.length;i+=step){
    const c=view[i];
    const time=c.t.slice(11,16);  // HH:MM only
    ctx.fillText(time, x(c.i)-22, H-7);
  }

  if(S.layers.sr) drawSR();
  if(S.layers.fvg) drawFVG();
  if(S.layers.ifvg) drawIFVG();
  if(S.layers.ob) drawOB();
  if(S.layers.breaker) drawBreaker();
  if(S.layers.breakout) drawBreakout();
  if(S.layers.ma) drawMA();
  if(S.layers.swings) drawSwings();

  // candles
  view.forEach(c=>{
    const up=c.c>=c.o, col=up?css('--up'):css('--down');
    ctx.strokeStyle=col; ctx.fillStyle=up?'rgba(63,185,80,.25)':col; ctx.lineWidth=1;
    const cx=x(c.i);
    ctx.beginPath();ctx.moveTo(cx,y(c.h));ctx.lineTo(cx,y(c.l));ctx.stroke();
    const top=y(Math.max(c.o,c.c)),bot=y(Math.min(c.o,c.c));
    ctx.beginPath();ctx.rect(cx-cw/2,top,cw,Math.max(1,bot-top));
    up?ctx.stroke():ctx.fill(); up&&ctx.stroke();
  });

  if(S.layers.structure) drawStructure();
  if(S.layers.sweeps) drawSweeps();
  if(S.layers.setups) drawTrades();

  if(hover>=a && hover<=b){ctx.strokeStyle=css('--line2');ctx.globalAlpha=.6;
    ctx.beginPath();ctx.moveTo(x(hover),PAD.t);ctx.lineTo(x(hover),H-PAD.b);ctx.stroke();ctx.globalAlpha=1;}
  updateViewHint();
}
function clipX(i){ return Math.max(geom.xr[0], Math.min(geom.xr[1], geom.x(i))); }
// Right edge of a level marking: a short span past its anchor, not the chart edge.
function spanEnd(anchor){ return clipX(Math.min(geom.b, anchor + LEVEL_SPAN)); }
function drawSwings(){ const m=tfd().markings; const {x,y,a,b}=geom;
  m.swings.forEach(s=>{ if(s.i>b || s.i+LEVEL_SPAN<a) return;
    ctx.strokeStyle=s.kind==='high'?'rgba(240,82,74,.45)':'rgba(63,185,80,.45)';
    ctx.setLineDash([3,3]);ctx.beginPath();ctx.moveTo(clipX(s.i),y(s.price));ctx.lineTo(spanEnd(s.i),y(s.price));ctx.stroke();ctx.setLineDash([]);});
}
function drawSR(){ const m=tfd().markings,{y,a,b}=geom;
  m.sr.forEach(z=>{ const anchor=(z.i!=null?z.i:a); if(anchor>b || anchor+LEVEL_SPAN<a) return;
    const x0=clipX(anchor), x1=spanEnd(anchor), w=Math.max(2,x1-x0), h=Math.max(1,y(z.lo)-y(z.hi));
    ctx.fillStyle='rgba(139,151,167,.10)';ctx.fillRect(x0,y(z.hi),w,h);
    ctx.strokeStyle='rgba(139,151,167,.35)';ctx.strokeRect(x0,y(z.hi),w,h);});
}
function zoneRect(start,top,bottom,fill,stroke,label){ const {x,y}=geom;
  if(start>geom.b || start+LEVEL_SPAN<geom.a) return; const x0=clipX(start), x1=spanEnd(start);
  ctx.fillStyle=fill;ctx.strokeStyle=stroke;
  ctx.fillRect(x0,y(top),x1-x0,Math.max(1,y(bottom)-y(top)));
  ctx.strokeRect(x0,y(top),x1-x0,Math.max(1,y(bottom)-y(top)));
  if(label){ctx.fillStyle=stroke;ctx.fillText(label,x0+2,y(top)-2);}
}
function drawFVG(){ tfd().markings.fvgs.forEach(z=>{ if(z.end<geom.a||z.start>geom.b)return;
  const long=z.dir==='long';
  zoneRect(z.start,z.top,z.bottom, long?'rgba(56,139,253,.09)':'rgba(227,160,8,.09)',
    long?'rgba(56,139,253,.4)':'rgba(227,160,8,.4)','FVG'); }); }
function drawIFVG(){ tfd().markings.ifvgs.forEach(z=>{ if(z.violated<geom.a||z.start>geom.b)return;
  zoneRect(z.start,z.top,z.bottom,'rgba(227,160,8,.07)','rgba(227,160,8,.5)','IFVG'); }); }
function drawOB(){ // OB zones come from liquidity setups
  const setups=tfd().strategies.liquidity_imbalance||[];
  setups.forEach(s=>{ if(!s.zone||s.zone.kind!=='OB')return; const z=s.zone; if(z.start>geom.b)return;
    zoneRect(z.start,z.top,z.bottom,'rgba(188,140,255,.09)','rgba(188,140,255,.5)','OB'); }); }
function drawBreaker(){ tfd().markings.breakers.forEach(z=>{ if(z.i>geom.b)return;
  zoneRect(z.i,z.top,z.bottom,'rgba(126,224,201,.08)','rgba(126,224,201,.5)','BRK'); }); }
function drawMA(){ const ma=tfd().ma,{x,y,a,b}=geom; if(!ma) return;
  ctx.strokeStyle='#d2a8ff';ctx.lineWidth=1.4;ctx.beginPath();let started=false;
  for(let i=a;i<=b;i++){ const v=ma[i]; if(v==null){started=false;continue;}
    const xx=x(i),yy=y(v); if(!started){ctx.moveTo(xx,yy);started=true;}else ctx.lineTo(xx,yy);}
  ctx.stroke();ctx.lineWidth=1;
  ctx.fillStyle='#d2a8ff';ctx.font='10px '+css('--mono');
  for(let i=b;i>=a;i--){ if(ma[i]!=null){ctx.fillText('MA'+tfd().ma_period,x(i)-26,y(ma[i])-4);break;} }
}
function drawBreakout(){ const m=tfd().markings,{x,y}=geom;
  m.pdhl.forEach(d=>{ if(d.to_index<geom.a||d.from_index>geom.b)return;
    const x0=clipX(d.from_index),x1=clipX(d.to_index);
    [['pdh',d.pdh,'rgba(88,166,255,.5)'],['pdl',d.pdl,'rgba(227,160,8,.5)']].forEach(([k,p,col])=>{
      ctx.strokeStyle=col;ctx.setLineDash([6,3]);ctx.beginPath();ctx.moveTo(x0,y(p));ctx.lineTo(x1,y(p));ctx.stroke();ctx.setLineDash([]);
      ctx.fillStyle=col;ctx.fillText(k.toUpperCase(),x0+2,y(p)-2);});
  });
}
function drawStructure(){ const {x,y}=geom;
  tfd().markings.structure.forEach(e=>{ if(e.i<geom.a||e.i>geom.b)return;
    const up=e.dir==='up'; ctx.fillStyle=e.kind==='CHoCH'?css('--gold'):(up?css('--up'):css('--down'));
    ctx.font='9px '+css('--mono');
    ctx.fillText(e.kind, x(e.i)-9, y(e.level)+(up?-4:11)); ctx.font='10px '+css('--mono');
    ctx.globalAlpha=.5;ctx.strokeStyle=ctx.fillStyle;ctx.beginPath();
    ctx.moveTo(clipX(e.i),y(e.level));ctx.lineTo(clipX(e.i)+14,y(e.level));ctx.stroke();ctx.globalAlpha=1;});
}
function drawSweeps(){ const {x,y}=geom;
  tfd().markings.sweeps.forEach(s=>{ if(s.i<geom.a||s.i>geom.b)return;
    ctx.fillStyle=s.side==='sell'?css('--down'):css('--up');
    const yy=y(s.wick),xx=x(s.i),up=s.side==='buy';
    ctx.beginPath();
    if(up){ctx.moveTo(xx,yy+9);ctx.lineTo(xx-5,yy+1);ctx.lineTo(xx+5,yy+1);}
    else{ctx.moveTo(xx,yy-9);ctx.lineTo(xx-5,yy-1);ctx.lineTo(xx+5,yy-1);}
    ctx.closePath();ctx.fill();});
}
function drawTrades(){ const {x,y}=geom;
  VIEW.forEach(s=>{
    const tp=s.tp!=null?s.tp:tpOf(s);
    const x0=clipX(s.entry_index), x1=s.ei!=null?clipX(s.ei):geom.xr[1];
    ctx.globalAlpha=s.kept?1:0.45;
    const line=(p,col,dash)=>{ctx.strokeStyle=col;ctx.lineWidth=1.2;ctx.setLineDash(dash||[]);
      ctx.beginPath();ctx.moveTo(x0,y(p));ctx.lineTo(x1,y(p));ctx.stroke();ctx.setLineDash([]);ctx.lineWidth=1;};
    line(s.entry, s.dir==='long'?css('--long'):css('--short'), []);
    line(s.sl, css('--loss'), [3,3]);
    line(tp, css('--win'), [3,3]);
    if(s.ei!=null){ctx.fillStyle=s.v==='win'?css('--win'):css('--loss');
      ctx.beginPath();ctx.arc(x1,y(s.ep),3.5,0,7);ctx.fill();}
    ctx.globalAlpha=1;
  });
}

let drag=null;
cv.style.cursor='grab';
cv.addEventListener('mousedown',e=>{ drag={x:e.clientX, start:S.vStart, moved:false}; cv.style.cursor='grabbing'; });
window.addEventListener('mouseup',()=>{ if(drag) cv.style.cursor='grab'; drag=null; });
cv.addEventListener('mousemove',e=>{
  if(!geom)return; const r=cv.getBoundingClientRect();
  if(drag){ const per=geom.px/Math.max(1,geom.view.length);
    const d=-Math.round((e.clientX-drag.x)/per); if(d!==0) drag.moved=true;
    const [pa,pb]=periodBounds();
    S.vStart=Math.max(pa, Math.min(drag.start+d, pb-S.vSpan+1));
    tip.style.display='none'; draw(); updateViewHint(); return; }
  const mx=e.clientX-r.left; const {view}=geom; let best=-1,bd=1e9;
  view.forEach(c=>{const dd=Math.abs(geom.x(c.i)-mx);if(dd<bd){bd=dd;best=c.i;}});
  hover=best; draw();
  const c=tfd().candles[best];
  tip.style.display='block';tip.style.left=(e.clientX+14)+'px';tip.style.top=(e.clientY+14)+'px';
  tip.textContent=`${c.t}\nO ${fmt(c.o)}  H ${fmt(c.h)}\nL ${fmt(c.l)}  C ${fmt(c.c)}`;
});
cv.addEventListener('mouseleave',()=>{tip.style.display='none';hover=-1;draw();});
cv.addEventListener('wheel',e=>{ if(!geom)return; e.preventDefault();
  const r=cv.getBoundingClientRect(), mx=e.clientX-r.left;
  const frac=Math.max(0,Math.min(1,(mx-PAD.l)/Math.max(1,geom.px)));
  zoomBy(e.deltaY>0?1.2:1/1.2, frac);
}, {passive:false});

// ---- trade-detail slide (opens on a Setups-row click) ----
const dcv=document.getElementById('dcanvas'), dctx=dcv.getContext('2d');
let _detail=null;
function drawDetail(s){
  const cs=tfd().candles, tp=s.tp!=null?s.tp:tpOf(s);
  // Window: pad around the trigger/entry/exit so there's context + resolution.
  const marks=[s.trigger_index,s.entry_index,s.resolve_index]; if(s.ei!=null)marks.push(s.ei);
  let lo=Math.min(...marks), hi=Math.max(...marks);
  const pad=Math.max(3,Math.round((hi-lo)*0.4));
  let a=Math.max(0,lo-pad), b=Math.min(cs.length-1,hi+pad);
  if(b-a<16){const grow=Math.ceil((16-(b-a))/2); a=Math.max(0,a-grow); b=Math.min(cs.length-1,b+grow);}
  const view=cs.slice(a,b+1), n=view.length;
  const W=dcv.clientWidth||980, H=360, P={l:56,r:62,t:14,b:22};
  dcv.width=W*devicePixelRatio; dcv.height=H*devicePixelRatio;
  dctx.setTransform(devicePixelRatio,0,0,devicePixelRatio,0,0);
  let pl=Infinity,ph=-Infinity; view.forEach(c=>{pl=Math.min(pl,c.l);ph=Math.max(ph,c.h);});
  [s.entry,s.sl,tp,s.trigger_level].forEach(v=>{if(v!=null){pl=Math.min(pl,v);ph=Math.max(ph,v);}});
  if(s.zone){pl=Math.min(pl,s.zone.bottom);ph=Math.max(ph,s.zone.top);}
  const pe=(ph-pl)*0.08||1; pl-=pe; ph+=pe;
  const pw=W-P.l-P.r, pht=H-P.t-P.b;
  const x=i=>P.l+(n<=1?pw/2:((i-a)/(n-1))*pw);
  const y=p=>P.t+(1-(p-pl)/(ph-pl))*pht;
  const cw=Math.max(2,pw/Math.max(1,n)*0.62);
  dctx.clearRect(0,0,W,H); dctx.font='10px '+css('--mono');
  for(let g=0;g<=4;g++){const p=pl+(ph-pl)*g/4,yy=y(p);
    dctx.strokeStyle=css('--line');dctx.globalAlpha=.4;dctx.beginPath();dctx.moveTo(P.l,yy);dctx.lineTo(W-P.r,yy);dctx.stroke();
    dctx.globalAlpha=1;dctx.fillStyle=css('--mut');dctx.fillText(p.toFixed(1),5,yy+3);}
  const step=Math.max(1,Math.floor(n/7));
  for(let i=0;i<n;i+=step){const c=view[i];dctx.fillStyle=css('--mut');dctx.fillText(c.t.slice(5,16),x(c.i)-22,H-6);}
  // zone (OB/FVG) rect: from its start to the entry candle
  if(s.zone){const z=s.zone; const x0=x(Math.max(a,z.start)), x1=x(Math.min(b,Math.max(z.end,s.entry_index)));
    const fill=z.kind==='OB'?'rgba(188,140,255,.13)':'rgba(56,139,253,.13)';
    const strk=z.kind==='OB'?'rgba(188,140,255,.65)':'rgba(56,139,253,.65)';
    dctx.fillStyle=fill;dctx.strokeStyle=strk;
    dctx.fillRect(x0,y(z.top),Math.max(3,x1-x0),Math.max(2,y(z.bottom)-y(z.top)));
    dctx.strokeRect(x0,y(z.top),Math.max(3,x1-x0),Math.max(2,y(z.bottom)-y(z.top)));
    dctx.fillStyle=strk;dctx.fillText(z.kind+' '+fmt(z.bottom)+'–'+fmt(z.top),x0+3,y(z.top)-4);}
  const hline=(p,col,dash,label,fromX)=>{dctx.strokeStyle=col;dctx.setLineDash(dash||[]);dctx.lineWidth=1.4;
    const startX = fromX !== undefined ? fromX : P.l;
    dctx.beginPath();dctx.moveTo(startX,y(p));dctx.lineTo(W-P.r,y(p));dctx.stroke();dctx.setLineDash([]);dctx.lineWidth=1;
    dctx.fillStyle=col;dctx.fillText(label,W-P.r+3,y(p)+3);};
  hline(s.trigger_level, css('--gold'),[5,3],'LIQ '+fmt(s.trigger_level));
  // candles
  view.forEach(c=>{const up=c.c>=c.o,col=up?css('--up'):css('--down');
    dctx.strokeStyle=col;dctx.fillStyle=up?'rgba(63,185,80,.28)':col;
    const cx=x(c.i);dctx.beginPath();dctx.moveTo(cx,y(c.h));dctx.lineTo(cx,y(c.l));dctx.stroke();
    const t=y(Math.max(c.o,c.c)),bo=y(Math.min(c.o,c.c));
    dctx.beginPath();dctx.rect(cx-cw/2,t,cw,Math.max(1,bo-t));up?dctx.stroke():dctx.fill();up&&dctx.stroke();});
  // trigger candle highlight
  const tcx=x(s.trigger_index);
  dctx.strokeStyle=css('--gold');dctx.globalAlpha=.85;dctx.lineWidth=1.5;
  dctx.strokeRect(tcx-cw/2-2,P.t,cw+4,pht);dctx.globalAlpha=1;dctx.lineWidth=1;
  // entry point X coordinate for line drawing
  const entryX = x(s.entry_index);
  // entry / sl / tp (draw from entry point to the right)
  hline(s.entry, s.dir==='long'?css('--long'):css('--short'),[],'ENTRY '+fmt(s.entry), entryX);
  hline(s.sl, css('--loss'),[4,3],'SL '+fmt(s.sl), entryX);
  hline(tp, css('--win'),[4,3],'TP '+fmt(tp), entryX);
  // Mark entry point prominently
  const exi=x(s.entry_index), eyi=y(s.entry);
  dctx.fillStyle=s.dir==='long'?css('--long'):css('--short');
  dctx.strokeStyle=s.dir==='long'?css('--long'):css('--short');
  dctx.globalAlpha=1;
  // Outer ring
  dctx.lineWidth=2;dctx.beginPath();dctx.arc(exi,eyi,6,0,Math.PI*2);dctx.stroke();
  // Inner dot
  dctx.beginPath();dctx.arc(exi,eyi,3,0,Math.PI*2);dctx.fill();
  dctx.globalAlpha=1;
  if(s.ei!=null){dctx.fillStyle=s.v==='win'?css('--win'):css('--loss');
    dctx.strokeStyle=s.v==='win'?css('--win'):css('--loss');
    const exi2=x(s.ei), eyi2=y(s.ep);
    dctx.lineWidth=1.5;dctx.beginPath();dctx.arc(exi2,eyi2,5,0,Math.PI*2);dctx.stroke();
    dctx.beginPath();dctx.arc(exi2,eyi2,3,0,Math.PI*2);dctx.fill();
  }
}
const DLEG=[['#e0b341','LIQ level'],['#bc8cff','Order block'],['#388bfd','FVG'],
  [css('--long'),'Entry'],[css('--loss'),'SL'],[css('--win'),'TP']];
function openDetail(s){
  if(!s) return; _detail=s;
  const cs=tfd().candles, tp=s.tp!=null?s.tp:tpOf(s);
  const risk=Math.abs(s.entry-s.sl), m=rrMult(), lbl=DATA.labels[S.strat];
  const long=s.dir==='long';
  document.getElementById('dtitle').innerHTML=`${long?'Long':'Short'} &middot; ${lbl}`;
  document.getElementById('dsub').textContent=`${S.tf} · entry ${cs[s.entry_index].t} · ${S.rr[0]}:${S.rr[1]} RR · ${s.v.toUpperCase()}`;
  document.getElementById('dlegend').innerHTML=DLEG.map(([c,t])=>`<span><span class="sw" style="background:${c}"></span>${t}</span>`).join('');
  // narrative
  const trigT=cs[s.trigger_index].t, entT=cs[s.entry_index].t;
  const steps=[];
  steps.push(['Key level', `Level marked at <b>${fmt(s.trigger_level)}</b> on the ${trigT} candle &mdash; ${s.note||lbl}.`]);
  if(s.zone) steps.push(['The zone', `Price left ${s.zone.kind==='OB'?'an order block':'a fair-value gap'} at <b>${fmt(s.zone.bottom)}–${fmt(s.zone.top)}</b>; the rule waits for a return to it.`]);
  steps.push(['Entry & stop', `${long?'Long':'Short'} at <b>${fmt(s.entry)}</b> (${entT}), stop <b>${fmt(s.sl)}</b> &mdash; ${fmt(risk)} of risk.`]);
  const out = s.v==='win'?`hit target for <b class="pos">+${m.toFixed(2)}R</b>`
    : s.v==='loss'?`stopped out for <b class="neg">-1.00R</b>`
    : 'never resolved within the data';
  steps.push(['Outcome', `Target <b>${fmt(tp)}</b> (${m.toFixed(2)}&times; risk). ${s.ei!=null?'Resolved '+cs[s.ei].t+' &mdash; ':''}${out}.`]);
  const earlyExit = risk * 0.5;
  const earlyExitPrice = long ? s.entry + earlyExit : s.entry - earlyExit;
  steps.push(['Early exit (optional)', `To cut losses early before hitting SL: <b>${fmt(earlyExitPrice)}</b> (half risk) or <b>${fmt(s.entry)}</b> (breakeven). Hold for target if trend is favourable.`]);
  // Add losing trade analysis
  if(s.v==='loss'){
    const bev20 = risk * 0.20;
    const bev30 = risk * 0.30;
    const bev40 = risk * 0.40;
    const bev20Price = long ? s.entry + bev20 : s.entry - bev20;
    const bev30Price = long ? s.entry + bev30 : s.entry - bev30;
    const bev40Price = long ? s.entry + bev40 : s.entry - bev40;
    steps.push(['Losing trade analysis', `This trade lost. To improve: consider setting breakeven stops at <b>${fmt(bev20Price)}</b> (20% profit), <b>${fmt(bev30Price)}</b> (30%), or <b>${fmt(bev40Price)}</b> (40%) to convert potential losses into winners if price returns to entry.`]);
  }
  document.getElementById('dsteps').innerHTML=steps.map((t,i)=>
    `<div class="step"><div class="n">${i+1}. ${t[0]}</div><div class="b">${t[1]}</div></div>`).join('');
  // ticket
  const riskPct=100/(1+m), rewPct=100-riskPct;
  const reward=risk*m;
  const filt=[['trend',s.kept],['MA',s.ma_ok],['RSI',s.rsi_ok]]
    .map(([k,v])=>`${k} ${v===false?'✗':v===true?'✓':'–'}`).join('  ');
  document.getElementById('dticket').innerHTML=
    `<div><div class="tk">Direction</div><div class="tv"><span class="badge b-${s.dir}">${s.dir}</span></div></div>
     <div><div class="tk">Verdict</div><div class="tv"><span class="badge b-${s.v}">${s.v}</span></div></div>
     <div><div class="tk">Entry</div><div class="tv gold">${fmt(s.entry)}</div></div>
     <div><div class="tk">Stop loss</div><div class="tv neg">${fmt(s.sl)}</div></div>
     <div><div class="tk">Take profit</div><div class="tv pos">${fmt(tp)}</div></div>
     <div><div class="tk">Result</div><div class="tv ${s.r>=0?'pos':'neg'}">${s.r.toFixed(2)}R</div></div>
     <div><div class="tk">Risk</div><div class="tv">${fmt(risk)}</div></div>
     <div><div class="tk">Reward (${m.toFixed(2)}R)</div><div class="tv pos">${fmt(reward)}</div></div>
     <div style="grid-column:1/3;border-bottom:0">
       <div class="tk">Risk : Reward at ${S.rr[0]}:${S.rr[1]} &mdash; break-even ${pct(1/(1+m))}</div>
       <div class="rrbar"><div class="risk" style="width:${riskPct.toFixed(1)}%"></div><div class="rew" style="width:${rewPct.toFixed(1)}%"></div></div>
       <div class="faint" style="margin-top:6px">filters &mdash; ${filt}</div>
     </div>`;
  document.getElementById('dnote').innerHTML='';
  document.getElementById('modal').classList.add('on');
  drawDetail(s);                       // sync: reading clientWidth forces layout
  requestAnimationFrame(()=>drawDetail(s));  // redraw once fonts/layout settle
}
function closeDetail(){ document.getElementById('modal').classList.remove('on'); _detail=null; }
document.getElementById('dclose').onclick=closeDetail;
document.getElementById('modal').onclick=e=>{ if(e.target.id==='modal') closeDetail(); };
window.addEventListener('keydown',e=>{ if(e.key==='Escape') closeDetail(); });
window.addEventListener('resize',()=>{ if(_detail&&document.getElementById('modal').classList.contains('on')) drawDetail(_detail); });

// ---- boot ----
fillPeriods();
recompute();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    raise SystemExit(main())
