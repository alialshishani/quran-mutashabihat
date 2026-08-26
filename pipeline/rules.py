"""Ḍawābiṭ rules.

Each rule is a predicate that must verify against the database before it can
fire (brief section 7). A rule that cannot be proven true from the data is not
emitted (C4) — a missing ḍābiṭ costs the user nothing, a wrong one teaches a
mistake.

Rendered Arabic is assembled from a fixed template plus tokens copied
byte-for-byte out of the database. No Qur'anic text originates here (C1) and no
count is asserted rather than computed (C2).
"""
from __future__ import annotations

import json
import math
from collections import Counter
from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Occurrence:
    """One position of a group, with the token on each side of the span."""

    occ_id: int
    start_word_id: int
    end_word_id: int
    verse_key: str
    surah: int
    ayah: int
    page: int
    juz: int
    surah_name: str
    span_display: tuple[str, ...]
    left_display: str | None
    left_norm: str | None
    right_display: str | None
    right_norm: str | None


@dataclass(frozen=True)
class Group:
    group_id: int
    kind: str
    occurrences: tuple[Occurrence, ...]

    @property
    def count(self) -> int:
        return len(self.occurrences)


class Rule(Protocol):
    code: str
    prior: float

    def applies(self, group: Group) -> bool: ...
    def evidence(self, group: Group) -> dict: ...
    def render(self, evidence: dict) -> str: ...


# Arabic connective vocabulary used to build ḍābiṭ text. Fixed template words
# only — never Qur'anic text, never a claim about meaning or wisdom (C5).
_AFTER = "ما بعد"
_BEFORE = "ما قبل"
_IN_ALL = "في كل المواضع"
_POSITIONS = "وعددها {n}"
_EXCEPT_ONE = "إلا موضعًا واحدًا"
_EXCEPT_TWO = "إلا موضعين"
_EXCEPT_N = "إلا {n} مواضع"
_IN_SURAH = "في سورة {surahs}"
_IN_SURAHS = "في سور {surahs}"
_IN_TWO_SURAHS = "في سورتي {surahs}"


def _surah_phrase(names: list[str]) -> str:
    """سورة / سورتي / سور, matching Arabic number agreement."""
    joined = " و".join(names)
    if len(names) == 1:
        return _IN_SURAH.format(surahs=joined)
    if len(names) == 2:
        return _IN_TWO_SURAHS.format(surahs=joined)
    return _IN_SURAHS.format(surahs=joined)


def _except_clause(minority: list[dict]) -> str:
    """The 'except ...' half.

    Minority positions are grouped by the token they actually carry: two
    positions sharing one variant is one thing to remember, not two, and
    printing the token twice reads as a mistake.
    """
    by_token: dict[str, list[str]] = {}
    display: dict[str, str] = {}
    for entry in minority:
        key = entry["token_norm"]
        display.setdefault(key, entry["token"])
        by_token.setdefault(key, []).append(entry["surah_name"])

    if len(minority) == 1:
        count = _EXCEPT_ONE
    elif len(minority) == 2:
        count = _EXCEPT_TWO
    else:
        count = _EXCEPT_N.format(n=len(minority))

    parts = [
        f"{_surah_phrase(names)} فـ({display[key]})"
        for key, names in by_token.items()
    ]
    return f"{count} {'، و'.join(parts)}"


class MajorityRule:
    """R1 — قاعدة الأغلبية.

    A repeated span is a frame; the token immediately before or after it is the
    slot that varies. When one filler holds the great majority of the positions
    and a small minority holds another, that is the highest-yield peg there is.

    Both edges are tested independently and the stronger one wins. Counts come
    from the group's own occurrences, never from an asserted total (C2).
    """

    code = "MAJORITY"

    def __init__(self, params: dict) -> None:
        self.min_occurrences = params["min_occurrences"]
        self.max_minority_count = params["max_minority_count"]
        self.min_majority_share = params["min_majority_share"]
        self.prior = params["prior"]

    # -- internals ------------------------------------------------------------

    @staticmethod
    def _slots(group: Group, side: str) -> list[tuple[Occurrence, str]]:
        """Occurrences paired with their filler on `side`, dropping unfilled ones."""
        out = []
        for occ in group.occurrences:
            norm = occ.right_norm if side == "right" else occ.left_norm
            if norm:
                out.append((occ, norm))
        return out

    def _best_split(self, group: Group) -> dict | None:
        """The strongest majority/minority split across both edges, or None."""
        best = None
        for side in ("right", "left"):
            slots = self._slots(group, side)
            if len(slots) < self.min_occurrences:
                continue
            counts = Counter(norm for _, norm in slots)
            if len(counts) < 2:
                # No variation on this edge: nothing to tell apart.
                continue
            majority_norm, majority_count = counts.most_common(1)[0]
            minority_total = len(slots) - majority_count
            share = majority_count / len(slots)
            if share < self.min_majority_share:
                continue
            if minority_total > self.max_minority_count:
                continue
            candidate = {
                "side": side,
                "positions": len(slots),
                "majority_norm": majority_norm,
                "majority_count": majority_count,
                "minority_count": minority_total,
                "share": share,
            }
            if best is None or candidate["share"] > best["share"]:
                best = candidate
        return best

    # -- Rule protocol --------------------------------------------------------

    def applies(self, group: Group) -> bool:
        return self._best_split(group) is not None

    def evidence(self, group: Group) -> dict:
        split = self._best_split(group)
        if split is None:
            raise ValueError(f"R1 does not apply to group {group.group_id}")

        side = split["side"]
        slots = self._slots(group, side)
        display_of = {}
        majority_positions = []
        minority = []
        for occ, norm in slots:
            display = occ.right_display if side == "right" else occ.left_display
            display_of.setdefault(norm, display)
            if norm == split["majority_norm"]:
                majority_positions.append(occ.verse_key)
            else:
                minority.append(
                    {
                        "verse_key": occ.verse_key,
                        "surah_name": occ.surah_name,
                        "juz": occ.juz,
                        "page": occ.page,
                        "token": display,
                        "token_norm": norm,
                    }
                )

        return {
            "rule": self.code,
            "side": side,
            "span": list(group.occurrences[0].span_display),
            "positions": split["positions"],
            "majority": {
                "token": display_of[split["majority_norm"]],
                "count": split["majority_count"],
                "verse_keys": sorted(majority_positions),
            },
            "minority": sorted(minority, key=lambda m: m["verse_key"]),
            "share": round(split["share"], 4),
        }

    def strength(self, evidence: dict) -> float:
        """Prior scaled by how lopsided the split actually is."""
        share = evidence["share"]
        positions = evidence["positions"]
        # More positions and a more lopsided split both raise confidence.
        lopsidedness = (share - self.min_majority_share) / (1 - self.min_majority_share)
        breadth = min(1.0, math.log2(positions) / math.log2(10))
        return round(self.prior * (0.5 + 0.25 * lopsidedness + 0.25 * breadth), 4)

    def render(self, evidence: dict) -> str:
        """Name the frame the claim is scoped to.

        Without the frame the sentence reads as a claim about the whole Qur'an;
        it is only a claim about the positions of this one phrase, and saying so
        is the difference between a true peg and an overreaching one (C4).
        """
        frame = " ".join(evidence["span"])
        anchor = _AFTER if evidence["side"] == "right" else _BEFORE
        majority_token = evidence["majority"]["token"]
        positions = _POSITIONS.format(n=evidence["positions"])
        return (
            f"{anchor} ({frame}) هو ({majority_token}) {_IN_ALL} {positions}، "
            f"{_except_clause(evidence['minority'])}."
        )


def load_rules(params: dict) -> list[Rule]:
    """Rules active at this milestone, in the order they are attempted."""
    return [MajorityRule(params["rules"]["r1_majority"])]


def evidence_json(evidence: dict) -> str:
    """Stable serialisation so two runs produce byte-identical rows."""
    return json.dumps(evidence, ensure_ascii=False, sort_keys=True)
