"""Self-contained interactive HTML report (vanilla-JS canvas, no dependencies)."""
from __future__ import annotations

import json
from dataclasses import asdict
from typing import List

from .engine import RunResult, BatchResult
from .params import Params
from .report import Stats


def _candle_json(c):
    return {"i": c.index, "t": c.label, "o": c.open, "h": c.high,
            "l": c.low, "c": c.close, "v": c.volume}


def _zone_json(zone, direction=None):
    return {"kind": zone.kind, "top": zone.top, "bottom": zone.bottom,
            "start": zone.start_index, "end": zone.end_index, "dir": direction}


def _setup_json(s, candles):
    return {
        "direction": s.direction,
        "strategy": s.strategy,
        "note": s.note,
        "sweep_index": s.sweep.index if s.sweep else s.trigger_index,
        "swept_level": round(s.swept_price, 5),
        "swept_time": candles[s.trigger_index].label,
        "sweep_time": candles[s.trigger_index].label,
        "zone": _zone_json(s.zone, s.direction) if s.zone else None,
        "entry_index": s.entry_index,
        "entry": round(s.entry_price, 5),
        "sl": round(s.stop_loss, 5),
        "tp": round(s.take_profit, 5),
        "risk": round(s.risk, 5),
        "verdict": s.verdict,
        "exit_index": s.exit_index,
        "exit_price": round(s.exit_price, 5) if s.exit_price is not None else None,
        "r": round(s.r_multiple, 3),
        "kept": s.filter_kept,
        "reason": s.filter_reason,
        "entry_time": candles[s.entry_index].label,
        "exit_time": candles[s.exit_index].label if s.exit_index is not None else None,
    }


def _run_json(r: RunResult):
    return {
        "name": r.name,
        "candles": [_candle_json(c) for c in r.candles],
        "swings": [{"i": s.index, "price": round(s.price, 5), "kind": s.kind} for s in r.swings],
        "sweeps": [{"i": s.index, "level": round(s.level, 5), "side": s.side,
                    "direction": s.direction, "wick": round(s.wick, 5)} for s in r.sweeps],
        "zones": [_zone_json(z, d) for z, d in r.fvgs],
        "setups": [_setup_json(s, r.candles) for s in r.setups],
        "stats_on": r.stats_on.as_dict(),
        "stats_off": r.stats_off.as_dict(),
        "bad_rows": [{"line": b.line_no, "reason": b.reason} for b in r.bad_rows],
    }


def build_payload(runs: List[RunResult], params: Params,
                  agg_on: Stats = None, agg_off: Stats = None) -> dict:
    return {
        "params": asdict(params),
        "days": [_run_json(r) for r in runs],
        "agg_on": agg_on.as_dict() if agg_on else None,
        "agg_off": agg_off.as_dict() if agg_off else None,
    }


def build_html(payload: dict) -> str:
    data = json.dumps(payload)
    return _TEMPLATE.replace("/*__DATA__*/", data)


def write_report(path: str, runs: List[RunResult], params: Params,
                 agg_on: Stats = None, agg_off: Stats = None):
    payload = build_payload(runs, params, agg_on, agg_off)
    html = build_html(payload)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(html)
    return path


_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Gold Sweep / Imbalance Backtest</title>
<style>
 :root{--bg:#0e1116;--panel:#161b22;--line:#30363d;--fg:#c9d1d9;--mut:#8b949e;
   --up:#3fb950;--down:#f85149;--long:#58a6ff;--short:#d29922;--win:#3fb950;--loss:#f85149;}
 *{box-sizing:border-box}
 body{margin:0;background:var(--bg);color:var(--fg);font:13px/1.4 ui-monospace,Menlo,Consolas,monospace}
 header{padding:12px 16px;border-bottom:1px solid var(--line);display:flex;gap:16px;align-items:baseline;flex-wrap:wrap}
 h1{font-size:15px;margin:0}
 .mut{color:var(--mut)}
 .wrap{padding:12px 16px;max-width:1300px;margin:0 auto}
 .controls{display:flex;gap:14px;flex-wrap:wrap;align-items:center;margin:10px 0;padding:10px;background:var(--panel);border:1px solid var(--line);border-radius:8px}
 label.tog{display:inline-flex;gap:5px;align-items:center;cursor:pointer;user-select:none}
 select{background:#0d1117;color:var(--fg);border:1px solid var(--line);border-radius:6px;padding:4px 8px}
 canvas{background:var(--panel);border:1px solid var(--line);border-radius:8px;width:100%;display:block}
 .grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:14px}
 table{border-collapse:collapse;width:100%;font-size:12px}
 th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
 th:first-child,td:first-child{text-align:left}
 th{color:var(--mut);font-weight:600}
 .panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px}
 .panel h2{font-size:13px;margin:0 0 8px}
 .pos{color:var(--win)}.neg{color:var(--loss)}
 .badge{padding:1px 6px;border-radius:4px;font-size:11px}
 .b-long{background:rgba(88,166,255,.18);color:var(--long)}
 .b-short{background:rgba(210,153,34,.2);color:var(--short)}
 .b-win{background:rgba(63,185,80,.18);color:var(--win)}
 .b-loss{background:rgba(248,81,73,.18);color:var(--loss)}
 .b-unresolved{background:rgba(139,148,158,.18);color:var(--mut)}
 .b-skip{background:rgba(139,148,158,.18);color:var(--mut)}
 .b-keep{background:rgba(63,185,80,.14);color:var(--win)}
 #tip{position:fixed;pointer-events:none;background:#0d1117;border:1px solid var(--line);
   border-radius:6px;padding:6px 8px;font-size:12px;display:none;z-index:9;white-space:pre}
 .note{background:#1c2128;border-left:3px solid var(--short);padding:8px 12px;border-radius:4px;margin:10px 0;color:var(--mut)}
 .swatch{display:inline-block;width:10px;height:10px;border-radius:2px;vertical-align:middle;margin-right:3px}
</style>
</head>
<body>
<header>
 <h1>Gold Liquidity-Sweep + Imbalance Backtest</h1>
 <span class="mut" id="paramline"></span>
</header>
<div class="wrap">
 <div class="note"><b>Honesty note:</b> this is hindsight on past candles &mdash; "what the rules would have flagged", not a prediction or live signal. Prices/levels are computed exactly from OHLC. Same-candle stop+target resolves as a LOSS (pessimistic). A trend filter that shines on a trending day can cost on a range day &mdash; compare ON vs OFF and across days.</div>

 <div class="controls">
  <span>Day: <select id="daysel"></select></span>
  <label class="tog"><input type="checkbox" id="L_levels" checked><span class="swatch" style="background:#6e7681"></span>Liquidity</label>
  <label class="tog"><input type="checkbox" id="L_sweeps" checked><span class="swatch" style="background:#bc8cff"></span>Sweeps</label>
  <label class="tog"><input type="checkbox" id="L_zones" checked><span class="swatch" style="background:#388bfd"></span>FVG/OB</label>
  <label class="tog"><input type="checkbox" id="L_setups" checked><span class="swatch" style="background:#58a6ff"></span>Setups (E/SL/TP)</label>
  <label class="tog"><input type="checkbox" id="L_skipped"><span class="swatch" style="background:#8b949e"></span>Show filter-skipped</label>
 </div>

 <canvas id="chart" height="560"></canvas>

 <div class="grid">
  <div class="panel"><h2>Stats &mdash; Filter OFF (all setups)</h2><div id="stats_off"></div></div>
  <div class="panel"><h2>Stats &mdash; Filter ON (trend-aligned)</h2><div id="stats_on"></div></div>
 </div>

 <div class="panel" style="margin-top:14px" id="batchpanel">
  <h2>Batch &mdash; per-day breakdown</h2>
  <div id="batch"></div>
 </div>

 <div class="panel" style="margin-top:14px">
  <h2>Setups (this day)</h2>
  <div id="setups"></div>
 </div>
 <div class="panel" style="margin-top:14px;display:none" id="badpanel">
  <h2>Bad rows</h2><div id="bad"></div>
 </div>
</div>
<div id="tip"></div>
<script>
const DATA = /*__DATA__*/;
const cv = document.getElementById('chart'), ctx = cv.getContext('2d');
const tip = document.getElementById('tip');
let cur = 0, hover = -1;
const PAD = {l:64,r:16,t:14,b:26};

function css(v){return getComputedStyle(document.documentElement).getPropertyValue(v).trim();}
function fmt(x){return x==null?'-':(+x).toFixed(2);}
function pct(x){return (x*100).toFixed(1)+'%';}

document.getElementById('paramline').textContent =
  'params: ' + Object.entries(DATA.params).filter(([k,v])=>v!=null)
    .map(([k,v])=>k+'='+v).join('  ');

const sel = document.getElementById('daysel');
DATA.days.forEach((d,i)=>{const o=document.createElement('option');o.value=i;o.textContent=d.name;sel.appendChild(o);});
sel.onchange = ()=>{cur=+sel.value; renderAll();};
['L_levels','L_sweeps','L_zones','L_setups','L_skipped'].forEach(id=>
  document.getElementById(id).onchange = draw);

function resize(){ cv.width = cv.clientWidth * devicePixelRatio; cv.height = 560*devicePixelRatio;
  ctx.setTransform(devicePixelRatio,0,0,devicePixelRatio,0,0); draw(); }
window.addEventListener('resize', resize);

let geom = null;
function buildGeom(){
  const d = DATA.days[cur], cs = d.candles;
  const W = cv.clientWidth, H = 560;
  let lo=Infinity, hi=-Infinity;
  cs.forEach(c=>{lo=Math.min(lo,c.l);hi=Math.max(hi,c.h);});
  // include setup TP/SL so lines stay on screen
  d.setups.forEach(s=>{ if(showSetup(s)){lo=Math.min(lo,s.sl,s.tp);hi=Math.max(hi,s.sl,s.tp);} });
  const padp=(hi-lo)*0.06||1; lo-=padp; hi+=padp;
  const px=W-PAD.l-PAD.r, ph=H-PAD.t-PAD.b;
  const x=i=>PAD.l + (cs.length<=1?px/2:(i/(cs.length-1))*px);
  const y=p=>PAD.t + (1-(p-lo)/(hi-lo))*ph;
  const cw=Math.max(2, px/cs.length*0.7);
  geom={d,cs,W,H,lo,hi,x,y,cw,px,ph};
}
function showSetup(s){ return s.kept || document.getElementById('L_skipped').checked; }

function draw(){
  if(!geom) buildGeom(); else buildGeom();
  const {d,cs,W,H,x,y,cw,lo,hi}=geom;
  ctx.clearRect(0,0,W,H);
  // axes / gridlines
  ctx.strokeStyle=css('--line'); ctx.fillStyle=css('--mut'); ctx.font='11px monospace';
  ctx.lineWidth=1;
  for(let g=0;g<=5;g++){const p=lo+(hi-lo)*g/5,yy=y(p);
    ctx.globalAlpha=.4;ctx.beginPath();ctx.moveTo(PAD.l,yy);ctx.lineTo(W-PAD.r,yy);ctx.stroke();
    ctx.globalAlpha=1;ctx.fillText(p.toFixed(2),6,yy+3);}
  // x labels (~8)
  const step=Math.max(1,Math.floor(cs.length/8));
  for(let i=0;i<cs.length;i+=step){ctx.fillText(cs[i].t.slice(11)||('#'+i), x(i)-14, H-8);}

  if(document.getElementById('L_zones').checked) drawZones();
  if(document.getElementById('L_levels').checked) drawLevels();

  // candles
  cs.forEach((c,i)=>{
    const up=c.c>=c.o, col=up?css('--up'):css('--down');
    ctx.strokeStyle=col; ctx.fillStyle=up?css('--bg'):col; ctx.lineWidth=1;
    const cx=x(i);
    ctx.beginPath();ctx.moveTo(cx,y(c.h));ctx.lineTo(cx,y(c.l));ctx.stroke();
    const top=y(Math.max(c.o,c.c)), bot=y(Math.min(c.o,c.c));
    ctx.beginPath();ctx.rect(cx-cw/2, top, cw, Math.max(1,bot-top));
    if(up){ctx.stroke();}else{ctx.fill();ctx.stroke();}
  });

  if(document.getElementById('L_sweeps').checked) drawSweeps();
  if(document.getElementById('L_setups').checked) drawSetups();

  if(hover>=0 && hover<cs.length){ctx.strokeStyle=css('--mut');ctx.globalAlpha=.5;
    ctx.beginPath();ctx.moveTo(x(hover),PAD.t);ctx.lineTo(x(hover),H-PAD.b);ctx.stroke();ctx.globalAlpha=1;}
}

function drawZones(){
  const {d,x,y,cw}=geom;
  d.zones.forEach(z=>{
    ctx.fillStyle = z.dir==='long' ? 'rgba(88,166,255,.10)' : 'rgba(210,153,34,.10)';
    ctx.strokeStyle = z.dir==='long' ? 'rgba(88,166,255,.5)' : 'rgba(210,153,34,.5)';
    const x0=x(z.start)-cw/2, x1=geom.W-PAD.r;
    ctx.fillRect(x0, y(z.top), x1-x0, y(z.bottom)-y(z.top));
    ctx.strokeRect(x0, y(z.top), x1-x0, y(z.bottom)-y(z.top));
    ctx.fillStyle=css('--mut');ctx.fillText('FVG', x0+2, y(z.top)-2);
  });
  // OB zones from setups
  d.setups.filter(s=>s.zone && s.zone.kind==='OB' && showSetup(s)).forEach(s=>{
    const z=s.zone; ctx.fillStyle='rgba(188,140,255,.10)'; ctx.strokeStyle='rgba(188,140,255,.6)';
    const x0=x(z.start)-cw/2, x1=x(s.entry_index)+cw;
    ctx.fillRect(x0,y(z.top),x1-x0,y(z.bottom)-y(z.top));
    ctx.strokeRect(x0,y(z.top),x1-x0,y(z.bottom)-y(z.top));
    ctx.fillStyle=css('--mut');ctx.fillText('OB',x0+2,y(z.bottom)+11);
  });
}
function drawLevels(){
  const {d,x,y}=geom;
  d.swings.forEach(s=>{
    ctx.strokeStyle = s.kind==='high' ? 'rgba(248,81,73,.35)' : 'rgba(63,185,80,.35)';
    ctx.setLineDash([4,3]);ctx.beginPath();ctx.moveTo(x(s.i),y(s.price));ctx.lineTo(geom.W-PAD.r,y(s.price));ctx.stroke();ctx.setLineDash([]);
  });
}
function drawSweeps(){
  const {d,x,y}=geom;
  d.sweeps.forEach(s=>{
    ctx.fillStyle = s.side==='sell' ? css('--down') : css('--up');
    const yy=y(s.wick), xx=x(s.i), up=s.side==='buy';
    ctx.beginPath();
    if(up){ctx.moveTo(xx,yy+9);ctx.lineTo(xx-5,yy+1);ctx.lineTo(xx+5,yy+1);}
    else{ctx.moveTo(xx,yy-9);ctx.lineTo(xx-5,yy-1);ctx.lineTo(xx+5,yy-1);}
    ctx.closePath();ctx.fill();
  });
}
function drawSetups(){
  const {d,x,y,cw}=geom;
  d.setups.forEach(s=>{
    if(!showSetup(s)) return;
    const a = s.kept?1:0.4;
    const x0=x(s.entry_index), x1 = s.exit_index!=null?x(s.exit_index):geom.W-PAD.r;
    ctx.globalAlpha=a;
    const line=(p,col,dash)=>{ctx.strokeStyle=col;ctx.setLineDash(dash||[]);
      ctx.beginPath();ctx.moveTo(x0,y(p));ctx.lineTo(x1,y(p));ctx.stroke();ctx.setLineDash([]);};
    line(s.entry, s.direction==='long'?css('--long'):css('--short'), []);
    line(s.sl, css('--loss'), [3,3]);
    line(s.tp, css('--win'), [3,3]);
    // exit marker
    if(s.exit_index!=null){
      ctx.fillStyle = s.verdict==='win'?css('--win'):css('--loss');
      const ey=y(s.exit_price); ctx.beginPath();ctx.arc(x1,ey,4,0,7);ctx.fill();
    }
    ctx.globalAlpha=1;
  });
}

cv.addEventListener('mousemove', e=>{
  if(!geom)return; const r=cv.getBoundingClientRect();
  const mx=e.clientX-r.left; const {cs}=geom;
  let best=-1,bd=1e9; cs.forEach((c,i)=>{const dd=Math.abs(geom.x(i)-mx);if(dd<bd){bd=dd;best=i;}});
  hover=best; draw();
  const c=cs[best];
  tip.style.display='block'; tip.style.left=(e.clientX+12)+'px'; tip.style.top=(e.clientY+12)+'px';
  tip.textContent = `${c.t}\nO ${fmt(c.o)}  H ${fmt(c.h)}\nL ${fmt(c.l)}  C ${fmt(c.c)}\nVol ${c.v}`;
});
cv.addEventListener('mouseleave', ()=>{tip.style.display='none';hover=-1;draw();});

function statRows(s){
  const rcls = s.total_r>=0?'pos':'neg';
  return `<table>
   <tr><th>Setups (entries)</th><td>${s.n_setups}</td></tr>
   <tr><th>Wins / Losses</th><td>${s.wins} / ${s.losses}</td></tr>
   <tr><th>Unresolved (excl.)</th><td>${s.unresolved}</td></tr>
   <tr><th>Win rate</th><td>${pct(s.win_rate)}</td></tr>
   <tr><th>Total R</th><td class="${rcls}">${s.total_r.toFixed(2)}R</td></tr>
   <tr><th>Expectancy</th><td class="${rcls}">${s.expectancy.toFixed(2)}R</td></tr>
  </table>`;
}

function detailCounts(d){
  return `<table><tr><th>Liquidity levels</th><td>${d.swings.length}</td></tr>
    <tr><th>Sweeps</th><td>${d.sweeps.length}</td></tr>
    <tr><th>FVGs</th><td>${d.zones.length}</td></tr></table>`;
}

function renderSetups(d){
  let h=`<table><tr><th>#</th><th>Dir</th><th>Swept level @ time</th><th>Imbalance</th>
    <th>Entry</th><th>SL</th><th>TP</th><th>Risk</th><th>Verdict</th><th>Resolved @</th><th>R</th><th>Filter</th></tr>`;
  d.setups.forEach((s,i)=>{
    h+=`<tr>
      <td>${i+1}</td>
      <td><span class="badge b-${s.direction}">${s.direction}</span></td>
      <td>${fmt(s.swept_level)} @ ${s.sweep_time}</td>
      <td>${s.zone?(s.zone.kind+' ['+fmt(s.zone.bottom)+'–'+fmt(s.zone.top)+']'):s.note}</td>
      <td>${fmt(s.entry)}</td><td>${fmt(s.sl)}</td><td>${fmt(s.tp)}</td>
      <td>${fmt(s.risk)}</td>
      <td><span class="badge b-${s.verdict}">${s.verdict}</span></td>
      <td>${s.exit_time||'-'}</td>
      <td class="${s.r>=0?'pos':'neg'}">${s.r.toFixed(2)}R</td>
      <td><span class="badge ${s.kept?'b-keep':'b-skip'}" title="${s.reason}">${s.kept?'keep':'skip'}</span></td>
    </tr>`;
  });
  return h+'</table>';
}

function renderBatch(){
  let h=`<table><tr><th>Day</th><th>Setups</th>
     <th>OFF W/L</th><th>OFF win%</th><th>OFF R</th>
     <th>ON W/L</th><th>ON win%</th><th>ON R</th></tr>`;
  DATA.days.forEach(d=>{
    const o=d.stats_off,n=d.stats_on;
    h+=`<tr><td>${d.name}</td><td>${o.n_setups}</td>
      <td>${o.wins}/${o.losses}</td><td>${pct(o.win_rate)}</td><td class="${o.total_r>=0?'pos':'neg'}">${o.total_r.toFixed(2)}R</td>
      <td>${n.wins}/${n.losses}</td><td>${pct(n.win_rate)}</td><td class="${n.total_r>=0?'pos':'neg'}">${n.total_r.toFixed(2)}R</td></tr>`;
  });
  if(DATA.agg_off){const o=DATA.agg_off,n=DATA.agg_on;
    h+=`<tr style="font-weight:700;border-top:2px solid var(--line)"><td>ALL</td><td>${o.n_setups}</td>
      <td>${o.wins}/${o.losses}</td><td>${pct(o.win_rate)}</td><td class="${o.total_r>=0?'pos':'neg'}">${o.total_r.toFixed(2)}R</td>
      <td>${n.wins}/${n.losses}</td><td>${pct(n.win_rate)}</td><td class="${n.total_r>=0?'pos':'neg'}">${n.total_r.toFixed(2)}R</td></tr>`;}
  return h+'</table>';
}

function renderAll(){
  const d=DATA.days[cur];
  document.getElementById('stats_off').innerHTML = detailCounts(d)+statRows(d.stats_off);
  document.getElementById('stats_on').innerHTML = statRows(d.stats_on);
  document.getElementById('setups').innerHTML = renderSetups(d);
  document.getElementById('batch').innerHTML = renderBatch();
  const bp=document.getElementById('badpanel');
  if(d.bad_rows.length){bp.style.display='block';
    document.getElementById('bad').innerHTML='<table><tr><th>Line</th><th>Reason</th></tr>'+
      d.bad_rows.map(b=>`<tr><td>${b.line}</td><td>${b.reason}</td></tr>`).join('')+'</table>';}
  else bp.style.display='none';
  resize();
}
document.getElementById('batchpanel').style.display = DATA.days.length>1?'block':'none';
renderAll();
</script>
</body>
</html>
"""
