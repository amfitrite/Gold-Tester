"""Stats aggregation for setups (filter ON vs OFF, per-day, batch)."""
from __future__ import annotations

from dataclasses import dataclass, asdict
from typing import List

from .models import Setup


@dataclass
class Stats:
    n_setups: int = 0          # setups that triggered an entry
    wins: int = 0
    losses: int = 0
    unresolved: int = 0
    win_rate: float = 0.0      # over resolved trades only
    total_r: float = 0.0
    expectancy: float = 0.0    # R per resolved trade

    def as_dict(self):
        return asdict(self)


def compute_stats(setups: List[Setup]) -> Stats:
    wins = sum(1 for s in setups if s.verdict == "win")
    losses = sum(1 for s in setups if s.verdict == "loss")
    unresolved = sum(1 for s in setups if s.verdict == "unresolved")
    resolved = wins + losses
    total_r = sum(s.r_multiple for s in setups if s.verdict in ("win", "loss"))
    win_rate = wins / resolved if resolved else 0.0
    expectancy = total_r / resolved if resolved else 0.0
    return Stats(n_setups=len(setups), wins=wins, losses=losses, unresolved=unresolved,
                 win_rate=win_rate, total_r=total_r, expectancy=expectancy)


def stats_filtered(setups: List[Setup], kept_only: bool) -> Stats:
    pool = [s for s in setups if s.filter_kept] if kept_only else setups
    return compute_stats(pool)
