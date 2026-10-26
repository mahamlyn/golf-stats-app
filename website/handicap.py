"""Handicap Index calculation following the World Handicap System (WHS) as used by Golf Australia.

Not modelled: the Playing Conditions Calculation (treated as 0). A 9-hole round played
before a Handicap Index exists is paired with the next 9-hole round, in date order.
"""
import math
from dataclasses import dataclass, field
from datetime import date
from decimal import ROUND_HALF_UP, Decimal

MAX_INDEX = 54.0
WINDOW = 20
MIN_SCORES = 3
# Scores available -> (how many of the lowest differentials to average, adjustment).
TABLE = {
    3: (1, -2.0), 4: (1, -1.0), 5: (1, 0.0), 6: (2, -1.0), 7: (2, 0.0), 8: (2, 0.0),
    9: (3, 0.0), 10: (3, 0.0), 11: (3, 0.0), 12: (4, 0.0), 13: (4, 0.0), 14: (4, 0.0),
    15: (5, 0.0), 16: (5, 0.0), 17: (6, 0.0), 18: (6, 0.0), 19: (7, 0.0), 20: (8, 0.0),
}


@dataclass
class Hole:
    par: int
    stroke_index: int
    strokes: int


@dataclass
class Round:
    round_id: int
    played_on: date
    course_name: str
    num_holes: int
    rating: float | None
    slope: int | None
    holes: list = field(default_factory=list)


@dataclass
class Differential:
    round_ids: list
    played_on: date
    course_name: str
    holes: int
    adjusted_gross: int
    value: float
    adjustment: float = 0.0

    @property
    def effective(self):
        return self.value - self.adjustment


def round1(value):
    return float(Decimal(str(value)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


def course_handicap(index, rating, slope, par, num_holes):
    base = index if num_holes == 18 else index / 2
    return math.floor(base * slope / 113 + (rating - par) + 0.5)


def strokes_received(handicap, rank, num_holes):
    """Strokes a player gets on the hole with the given difficulty rank (1 = hardest)."""
    if handicap >= 0:
        return handicap // num_holes + (1 if rank <= handicap % num_holes else 0)
    given_back = -handicap
    return -(given_back // num_holes + (1 if rank > num_holes - given_back % num_holes else 0))


def adjusted_gross(holes, handicap):
    """Cap each hole at net double bogey, or par + 5 when there is no handicap yet."""
    order = sorted(range(len(holes)), key=lambda i: holes[i].stroke_index)
    rank = {hole: position + 1 for position, hole in enumerate(order)}
    total = 0
    for i, hole in enumerate(holes):
        if handicap is None:
            cap = hole.par + 5
        else:
            cap = hole.par + 2 + strokes_received(handicap, rank[i], len(holes))
        total += min(hole.strokes, cap)
    return total


def index_from(values):
    if len(values) < MIN_SCORES:
        return None
    count, adjustment = TABLE[min(len(values), WINDOW)]
    best = sorted(values)[:count]
    return min(round1(sum(best) / count + adjustment), MAX_INDEX)


def calculate(rounds):
    """Replay rounds in date order and return the current Handicap Index with its workings."""
    diffs, pending, history, skipped = [], [], [], []
    index = None

    for r in sorted(rounds, key=lambda r: (r.played_on, r.round_id)):
        if r.rating is None or r.slope is None:
            skipped.append({"RoundId": r.round_id, "CourseName": r.course_name,
                            "Reason": "Course has no rating and slope"})
            continue

        par = sum(h.par for h in r.holes)
        playing = None if index is None else course_handicap(index, r.rating, r.slope, par, r.num_holes)
        gross = adjusted_gross(r.holes, playing)
        differential = round1(113 / r.slope * (gross - r.rating))

        if r.num_holes == 18:
            new = Differential([r.round_id], r.played_on, r.course_name, 18, gross, differential)
        elif index is None:
            pending.append(Differential([r.round_id], r.played_on, r.course_name, 9, gross, differential))
            if len(pending) < 2:
                continue
            first, second = pending
            pending = []
            new = Differential(first.round_ids + second.round_ids, second.played_on,
                               f"{first.course_name} + {second.course_name}", 18,
                               first.adjusted_gross + second.adjusted_gross,
                               round1(first.value + second.value))
        else:
            expected = 0.52 * index + 1.2
            new = Differential([r.round_id], r.played_on, r.course_name, 9, gross,
                               round1(differential + expected))

        if index is not None:
            gap = index - new.value
            reduction = 2.0 if gap >= 10 else 1.0 if gap >= 7 else 0.0
            if reduction:
                for earlier in diffs[-(WINDOW - 1):]:
                    earlier.adjustment += reduction
                new.adjustment = reduction
        diffs.append(new)

        raw = index_from([d.effective for d in diffs[-WINDOW:]])
        if raw is None:
            continue
        low = min((i for day, i in history if (new.played_on - day).days <= 365), default=None)
        if low is not None and raw > low + 3:
            raw = round1(min(low + 3 + (raw - low - 3) / 2, low + 5))
        index = min(raw, MAX_INDEX)
        history.append((new.played_on, index))

    window = diffs[-WINDOW:]
    used = set()
    counted = 0
    adjustment = 0.0
    if len(window) >= MIN_SCORES:
        counted, adjustment = TABLE[min(len(window), WINDOW)]
        ranked = sorted(range(len(window)), key=lambda i: (window[i].effective, i))
        used = set(ranked[:counted])

    latest = diffs[-1].played_on if diffs else None
    low_index = min((i for day, i in history if latest and (latest - day).days <= 365), default=None)

    return {
        "index": index,
        "needed": max(0, MIN_SCORES - len(diffs)),
        "counted": counted,
        "adjustment": adjustment,
        "lowIndex": low_index,
        "pendingNineHole": len(pending),
        "skipped": skipped,
        "scores": [{
            "RoundIds": d.round_ids, "PlayedOn": d.played_on.isoformat(), "CourseName": d.course_name,
            "Holes": d.holes, "AdjustedGross": d.adjusted_gross,
            "Differential": round1(d.effective), "Adjustment": d.adjustment, "Used": i in used,
        } for i, d in enumerate(window)],
    }
