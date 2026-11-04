"""Forgiving parser for MT5 candle exports.

MT5 "Save As" lines look like::

    2026.05.27  01:00,4536.97000,4538.67000,4501.25000,4504.80000,2815,0

i.e. ``date<two spaces>time, open, high, low, close, volume, spread``.

The parser tolerates:
  * comma, tab, or whitespace field separation
  * a header row (skipped)
  * trailing/missing volume & spread columns
  * a completely missing timestamp (candles are then numbered)
and validates ``high >= low`` (and that high/low bracket open/close), reporting
the offending source line number for any bad row.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import List, Optional

from .models import Candle

_TS_RE = re.compile(r"^\d{4}[.\-/]\d{2}[.\-/]\d{2}")
_DATE_ONLY_RE = re.compile(r"^\d{4}[.\-/]\d{2}[.\-/]\d{2}$")
_TIME_ONLY_RE = re.compile(r"^\d{2}:\d{2}(?::\d{2})?$")
_HEADER_RE = re.compile(r"(?i)\b(open|high|low|close|date|time)\b")
# date and time joined by 1+ spaces, optional 'T' separator too.
_DATETIME_RE = re.compile(
    r"(\d{4})[.\-/](\d{2})[.\-/](\d{2})[ T]+(\d{2}):(\d{2})(?::(\d{2}))?"
)


@dataclass
class ParseResult:
    candles: List[Candle]
    bad_rows: List["BadRow"] = field(default_factory=list)
    source: Optional[str] = None

    @property
    def ok(self) -> bool:
        return len(self.candles) > 0


@dataclass
class BadRow:
    line_no: int
    raw: str
    reason: str


def _to_float(tok: str) -> Optional[float]:
    tok = tok.strip()
    if not tok:
        return None
    try:
        return float(tok)
    except ValueError:
        return None


def _split_fields(line: str) -> List[str]:
    """Split a line into fields, keeping the 'date<space>time' chunk intact.

    Strategy: if the line contains commas (or tabs) use those as the primary
    delimiter, since the date/time gap is spaces. Otherwise fall back to
    whitespace splitting and re-join the first two tokens as the timestamp.
    """
    if "," in line:
        parts = [p.strip() for p in line.split(",")]
    elif "\t" in line:
        parts = [p.strip() for p in line.split("\t")]
    else:
        # whitespace-only: date, time, then 5-6 numbers
        toks = line.split()
        if len(toks) >= 2 and _TS_RE.match(toks[0]) and ":" in toks[1]:
            parts = [f"{toks[0]} {toks[1]}"] + toks[2:]
        else:
            parts = toks
    return parts


def _parse_timestamp(token: str) -> Optional[datetime]:
    m = _DATETIME_RE.search(token)
    if not m:
        return None
    y, mo, d, h, mi, s = m.groups()
    return datetime(int(y), int(mo), int(d), int(h), int(mi), int(s or 0))


def parse_lines(lines, source: Optional[str] = None) -> ParseResult:
    candles: List[Candle] = []
    bad: List[BadRow] = []
    idx = 0

    for line_no, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line:
            continue
        # Skip a header row if it has no leading timestamp and mentions OHLC words.
        if not _TS_RE.match(line) and _HEADER_RE.search(line):
            continue

        parts = _split_fields(line)
        if not parts:
            continue

        # Re-join a split "date" + "time" pair (common with tab/space exports).
        if len(parts) >= 2 and _DATE_ONLY_RE.match(parts[0]) and _TIME_ONLY_RE.match(parts[1]):
            parts = [f"{parts[0]} {parts[1]}"] + parts[2:]

        ts: Optional[datetime] = None
        nums = parts
        # Does the first field carry a timestamp?
        if parts and _DATETIME_RE.search(parts[0]):
            ts = _parse_timestamp(parts[0])
            nums = parts[1:]

        floats = [_to_float(p) for p in nums]
        floats = [f for f in floats if f is not None]

        if len(floats) < 4:
            bad.append(BadRow(line_no, line, f"expected >=4 numeric OHLC values, got {len(floats)}"))
            continue

        o, h, l, c = floats[0], floats[1], floats[2], floats[3]
        vol = floats[4] if len(floats) > 4 else 0.0
        spr = floats[5] if len(floats) > 5 else 0.0

        if h < l:
            bad.append(BadRow(line_no, line, f"high ({h}) < low ({l})"))
            continue
        if not (l <= o <= h and l <= c <= h):
            bad.append(BadRow(line_no, line, f"open/close outside [low, high]: o={o} c={c} h={h} l={l}"))
            continue

        candles.append(Candle(index=idx, open=o, high=h, low=l, close=c,
                              volume=vol, spread=spr, timestamp=ts))
        idx += 1

    return ParseResult(candles=candles, bad_rows=bad, source=source)


def _read_text(path: str) -> str:
    """Read a file, auto-detecting the BOM (MT5 often exports UTF-16-LE)."""
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw[:2] == b"\xff\xfe":
        return raw.decode("utf-16-le")
    if raw[:2] == b"\xfe\xff":
        return raw.decode("utf-16-be")
    if raw[:3] == b"\xef\xbb\xbf":
        return raw.decode("utf-8-sig")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


def parse_file(path: str) -> ParseResult:
    return parse_lines(_read_text(path).splitlines(), source=path)
