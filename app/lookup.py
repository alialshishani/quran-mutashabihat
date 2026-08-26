"""Āyah-scoped lookup over the pass-A groups.

Given a sūrah and an āyah, return every repeated span that touches that āyah
together with the other positions of that span — the āyāt a memoriser is liable
to confuse it with — and any ḍābiṭ that verified for the group.

Nothing here computes new analysis. It reads what `pipeline.pass_a` and
`pipeline.apply_rules` already wrote, so the constraints those passes hold to
(Qur'anic text copied byte-for-byte, every count computed rather than asserted)
hold here too.
"""
from __future__ import annotations

import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"

DEFAULT_SCOPE = "full"
DEFAULT_LIMIT = 25


class AyahNotFound(LookupError):
    """The requested sūrah:āyah is not in the muṣḥaf."""


def connect(db: Path | str = DB) -> sqlite3.Connection:
    """Read-only connection. The service never writes to the corpus."""
    db = Path(db)
    if not db.exists():
        raise FileNotFoundError(f"missing {db}; run: python -m pipeline.ingest --rebuild")
    con = sqlite3.connect(
        f"file:{db.as_posix()}?mode=ro", uri=True, check_same_thread=False
    )
    con.row_factory = sqlite3.Row
    return con


# -- reference data -----------------------------------------------------------


def surahs(con: sqlite3.Connection) -> list[dict]:
    return [
        {
            "surah": r["surah"],
            "name_ar": r["name_ar"],
            "ayah_count": r["ayah_count"],
            "revelation_place": r["revelation_place"],
        }
        for r in con.execute(
            "SELECT surah, name_ar, ayah_count, revelation_place "
            "FROM surahs ORDER BY surah"
        )
    ]


def scopes(con: sqlite3.Connection) -> list[dict]:
    return [
        {"scope": r["scope"], "groups": r["n"]}
        for r in con.execute(
            "SELECT scope, COUNT(*) AS n FROM groups GROUP BY scope ORDER BY n DESC"
        )
    ]


# -- internals ----------------------------------------------------------------


class _Words:
    """Per-request word cache. One query per contiguous range asked for."""

    def __init__(self, con: sqlite3.Connection) -> None:
        self._con = con
        self._rows: dict[int, sqlite3.Row] = {}

    def load_range(self, first: int, last: int) -> None:
        if all(w in self._rows for w in range(first, last + 1)):
            return
        for row in self._con.execute(
            "SELECT word_id, surah, ayah, word_pos, text_uthmani "
            "FROM words WHERE word_id BETWEEN ? AND ?",
            (first, last),
        ):
            self._rows[row["word_id"]] = row

    def get(self, word_id: int) -> sqlite3.Row | None:
        if word_id not in self._rows:
            self.load_range(word_id, word_id)
        return self._rows.get(word_id)

    def text(self, first: int, last: int) -> list[str]:
        self.load_range(first, last)
        return [self._rows[w]["text_uthmani"] for w in range(first, last + 1)]

    def neighbour(self, word_id: int, surah: int) -> str | None:
        """The token at `word_id`, but only if it lies inside the same sūrah.

        A token on the far side of a sūrah seam is not part of the phrase — the
        same rule `pipeline.apply_rules` applies when it builds its slots.
        """
        row = self.get(word_id)
        if row is None or row["surah"] != surah:
            return None
        return row["text_uthmani"]


def _ayah_row(con: sqlite3.Connection, surah: int, ayah: int) -> sqlite3.Row:
    row = con.execute(
        "SELECT verse_key, surah, ayah, first_word_id, last_word_id, "
        "       page_start, page_end, juz, hizb, rub "
        "FROM ayahs WHERE surah = ? AND ayah = ?",
        (surah, ayah),
    ).fetchone()
    if row is None:
        raise AyahNotFound(f"{surah}:{ayah} is not an ayah in the mushaf")
    return row


def _ayah_words(con: sqlite3.Connection, verse_key: str, words: _Words) -> list[sqlite3.Row]:
    bounds = con.execute(
        "SELECT first_word_id, last_word_id FROM ayahs WHERE verse_key = ?",
        (verse_key,),
    ).fetchone()
    words.load_range(bounds["first_word_id"], bounds["last_word_id"])
    return [
        words.get(w)
        for w in range(bounds["first_word_id"], bounds["last_word_id"] + 1)
    ]


def _position(
    con: sqlite3.Connection,
    words: _Words,
    occ: sqlite3.Row,
    surah_names: dict[int, str],
    juz_of: dict[str, int],
) -> dict:
    """One position of a group: the āyah(s) it sits in, with the span marked."""
    start, end = occ["start_word_id"], occ["end_word_id"]
    words.load_range(start, end)
    surah = int(occ["verse_key"].split(":")[0])

    covered: list[str] = []
    for w in range(start, end + 1):
        row = words.get(w)
        key = f"{row['surah']}:{row['ayah']}"
        if key not in covered:
            covered.append(key)

    ayat = []
    for key in covered:
        s, a = (int(x) for x in key.split(":"))
        ayat.append(
            {
                "verse_key": key,
                "surah": s,
                "surah_name_ar": surah_names[s],
                "ayah": a,
                "juz": juz_of.get(key),
                "words": [
                    {
                        "word_id": row["word_id"],
                        "word_pos": row["word_pos"],
                        "text": row["text_uthmani"],
                        "in_span": start <= row["word_id"] <= end,
                    }
                    for row in _ayah_words(con, key, words)
                ],
            }
        )

    return {
        "verse_key": occ["verse_key"],
        "surah": surah,
        "surah_name_ar": surah_names[surah],
        "ayah": int(occ["verse_key"].split(":")[1]),
        "page": occ["page"],
        "line": occ["line"],
        "juz": juz_of.get(occ["verse_key"]),
        "start_word_id": start,
        "end_word_id": end,
        "span_text": " ".join(words.text(start, end)),
        # In recitation order: `before` precedes the span, `after` follows it.
        "before": words.neighbour(start - 1, surah),
        "after": words.neighbour(end + 1, surah),
        "crosses_ayah": len(covered) > 1,
        "ayat": ayat,
    }


def _subsumed(match: dict, others: list[dict]) -> bool:
    """True when `match` adds nothing another match on this āyah does not.

    Only fires when a longer span covers this one *and* lands in exactly the
    same set of positions. A shorter span almost always has more positions than
    the longer one containing it, so this drops duplicates, never evidence.
    """
    here = (match["here"]["start_word_id"], match["here"]["end_word_id"])
    keys = {p["verse_key"] for p in match["positions"]}
    for other in others:
        if other["group_id"] == match["group_id"]:
            continue
        o_here = (other["here"]["start_word_id"], other["here"]["end_word_id"])
        if o_here == here:
            continue
        if o_here[0] <= here[0] and here[1] <= o_here[1]:
            if keys <= {p["verse_key"] for p in other["positions"]}:
                return True
    return False


# -- the query ----------------------------------------------------------------


def lookup(
    con: sqlite3.Connection,
    surah: int,
    ayah: int,
    *,
    scope: str = DEFAULT_SCOPE,
    min_len: int = 0,
    min_occurrences: int = 2,
    limit: int | None = DEFAULT_LIMIT,
    collapse: bool = True,
) -> dict:
    """Every repeated span touching `surah:ayah`, strongest peg first."""
    row = _ayah_row(con, surah, ayah)
    words = _Words(con)
    surah_names = {
        r["surah"]: r["name_ar"] for r in con.execute("SELECT surah, name_ar FROM surahs")
    }
    juz_of = {
        r["verse_key"]: r["juz"] for r in con.execute("SELECT verse_key, juz FROM ayahs")
    }

    first, last = row["first_word_id"], row["last_word_id"]
    hits = con.execute(
        "SELECT o.group_id, o.start_word_id, o.end_word_id, "
        "       g.occurrence_count, g.span_len_min, g.span_len_max, g.kind, "
        "       g.cross_surah, g.needs_review "
        "FROM occurrences o JOIN groups g ON g.group_id = o.group_id "
        "WHERE g.scope = ? AND o.start_word_id <= ? AND o.end_word_id >= ? "
        "ORDER BY o.start_word_id",
        (scope, last, first),
    ).fetchall()

    matches: list[dict] = []
    for hit in hits:
        if hit["span_len_max"] < min_len or hit["occurrence_count"] < min_occurrences:
            continue
        gid = hit["group_id"]

        positions = [
            _position(con, words, occ, surah_names, juz_of)
            for occ in con.execute(
                "SELECT occ_id, start_word_id, end_word_id, verse_key, page, line "
                "FROM occurrences WHERE group_id = ? ORDER BY start_word_id",
                (gid,),
            )
        ]
        here_start, here_end = hit["start_word_id"], hit["end_word_id"]
        for pos in positions:
            pos["is_query"] = (
                pos["start_word_id"] == here_start and pos["end_word_id"] == here_end
            )
        here = next(p for p in positions if p["is_query"])

        dawabit = [
            {
                "rule_code": d["rule_code"],
                "strength": d["strength"],
                "text_ar": d["text_ar"],
                "verified": bool(d["verified"]),
                "generated_by": d["generated_by"],
                "evidence": json.loads(d["payload"]) if d["payload"] else None,
            }
            for d in con.execute(
                "SELECT rule_code, strength, text_ar, verified, generated_by, payload "
                "FROM dawabit WHERE group_id = ? ORDER BY strength DESC",
                (gid,),
            )
        ]

        matches.append(
            {
                "group_id": gid,
                "kind": hit["kind"],
                "span_len": here_end - here_start + 1,
                "occurrence_count": hit["occurrence_count"],
                "cross_surah": bool(hit["cross_surah"]),
                "needs_review": bool(hit["needs_review"]),
                "span_text": " ".join(words.text(here_start, here_end)),
                "span_tokens": words.text(here_start, here_end),
                "here": here,
                "elsewhere": [p for p in positions if not p["is_query"]],
                "positions": positions,
                "dawabit": dawabit,
            }
        )

    if collapse:
        matches = [m for m in matches if not _subsumed(m, matches)]

    # A verified peg is the product; span length and breadth order the rest.
    matches.sort(
        key=lambda m: (
            0 if m["dawabit"] else 1,
            -max((d["strength"] or 0) for d in m["dawabit"]) if m["dawabit"] else 0,
            -m["span_len"],
            -m["occurrence_count"],
            m["group_id"],
        )
    )
    # Summary counts describe the āyah, so they are taken before the display
    # limit is applied; `returned` is the only number about the page size.
    total = len(matches)
    with_dabit = sum(1 for m in matches if m["dawabit"])
    other_positions = sum(len(m["elsewhere"]) for m in matches)
    distinct_ayat = len({p["verse_key"] for m in matches for p in m["elsewhere"]})
    if limit is not None:
        matches = matches[:limit]

    ayah_words = _ayah_words(con, row["verse_key"], words)
    covered = {
        w
        for m in matches
        for w in range(m["here"]["start_word_id"], m["here"]["end_word_id"] + 1)
    }

    return {
        "query": {
            "verse_key": row["verse_key"],
            "surah": row["surah"],
            "ayah": row["ayah"],
            "surah_name_ar": surah_names[row["surah"]],
            "page": row["page_start"],
            "juz": row["juz"],
            "hizb": row["hizb"],
            "rub": row["rub"],
            "text": " ".join(w["text_uthmani"] for w in ayah_words),
            "words": [
                {
                    "word_id": w["word_id"],
                    "word_pos": w["word_pos"],
                    "text": w["text_uthmani"],
                    "repeated": w["word_id"] in covered,
                }
                for w in ayah_words
            ],
        },
        "params": {
            "scope": scope,
            "min_len": min_len,
            "min_occurrences": min_occurrences,
            "limit": limit,
            "collapse": collapse,
        },
        "counts": {
            "matches": total,
            "returned": len(matches),
            "with_dabit": with_dabit,
            "other_positions": other_positions,
            "distinct_ayat": distinct_ayat,
        },
        "matches": matches,
    }
