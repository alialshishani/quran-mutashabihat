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


class PhraseNotFound(LookupError):
    """No official phrase carries this id."""


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
            "first_page": r["first_page"],
            "last_page": r["last_page"],
        }
        for r in con.execute(
            "SELECT surah, name_ar, ayah_count, revelation_place, first_page, last_page "
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


def _has_official(con: sqlite3.Connection) -> bool:
    """Whether `pipeline.official` and `pipeline.pegs` have run on this corpus."""
    present = {
        r[0]
        for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('official_phrases', 'official_positions', 'pegs')"
        )
    }
    if len(present) < 3:
        return False
    return bool(con.execute("SELECT COUNT(*) FROM pegs LIMIT 1").fetchone()[0])


def _peg(row: sqlite3.Row) -> dict | None:
    if row is None or row["kind"] is None:
        return None
    return {
        "kind": row["kind"],
        "cue_ar": row["cue_ar"],
        "cue_window": row["cue_window"],
        "continuation_ar": row["continuation_ar"],
        "continuation_unique": bool(row["continuation_unique"]),
        "strength": row["strength"],
        "text_ar": row["text_ar"],
        "evidence": json.loads(row["evidence"]) if row["evidence"] else None,
    }


def official_matches(
    con: sqlite3.Connection,
    surah: int,
    ayah: int,
    words: _Words,
    surah_names: dict[int, str],
    juz_of: dict[str, int],
) -> list[dict]:
    """Official mutashābih phrases touching this āyah, each position with its peg.

    The peg is the point of this section: for the position sitting in the āyah
    asked about, it is the cue that tells it from its siblings; for each sibling,
    it is what tells that one apart in turn.
    """
    bounds = con.execute(
        "SELECT first_word_id, last_word_id FROM ayahs WHERE surah = ? AND ayah = ?",
        (surah, ayah),
    ).fetchone()
    hits = con.execute(
        "SELECT DISTINCT phrase_id FROM official_positions "
        "WHERE start_word_id <= ? AND end_word_id >= ?",
        (bounds["last_word_id"], bounds["first_word_id"]),
    ).fetchall()

    out = []
    for hit in hits:
        phrase = con.execute(
            "SELECT * FROM official_phrases WHERE phrase_id = ?", (hit["phrase_id"],)
        ).fetchone()
        positions = []
        for row in con.execute(
            "SELECT o.*, p.kind, p.cue_ar, p.cue_window, p.continuation_ar, "
            "       p.continuation_unique, p.strength, p.text_ar, p.evidence "
            "FROM official_positions o LEFT JOIN pegs p ON p.pos_id = o.pos_id "
            "WHERE o.phrase_id = ? ORDER BY o.start_word_id",
            (hit["phrase_id"],),
        ):
            position = _position(
                con,
                words,
                {
                    "start_word_id": row["start_word_id"],
                    "end_word_id": row["end_word_id"],
                    "verse_key": row["verse_key"],
                    "page": row["page"],
                    "line": None,
                },
                surah_names,
                juz_of,
            )
            position |= {
                "pos_id": row["pos_id"],
                "in_official": bool(row["in_official"]),
                "in_exact": bool(row["in_exact"]),
                "group_id": row["group_id"],
                "link": row["link"],
                "is_query": row["start_word_id"] <= bounds["last_word_id"]
                and row["end_word_id"] >= bounds["first_word_id"],
                "peg": _peg(row),
            }
            positions.append(position)

        here = [p for p in positions if p["is_query"]]
        out.append(
            {
                "phrase_id": phrase["phrase_id"],
                "source": phrase["source"],
                "text_ar": phrase["text_ar"],
                "span_len": phrase["span_len"],
                "set_count": phrase["set_count"],
                "official_count": phrase["official_count"],
                "exact_count": phrase["exact_count"],
                "surah_count": phrase["surah_count"],
                "here": here,
                "elsewhere": [p for p in positions if not p["is_query"]],
                "positions": positions,
            }
        )

    # Strongest peg for the position in this āyah first; a wider confusion set
    # is the more urgent one to hold apart.
    out.sort(
        key=lambda p: (
            -max((h["peg"]["strength"] if h["peg"] else 0) for h in p["here"])
            if p["here"]
            else 0,
            -p["set_count"],
            p["phrase_id"],
        )
    )
    return out


# -- forks --------------------------------------------------------------------

SHAPES = ("all_but_one", "two_way", "many", "no_fork")
# Cheapest to hold first: one exception beats a two-way split, which beats a
# fork that costs a peg per position.
SHAPE_RANK = "CASE shape WHEN 'all_but_one' THEN 0 WHEN 'two_way' THEN 1 " \
             "WHEN 'many' THEN 2 ELSE 3 END"
SORTS = {
    "useful": f"{SHAPE_RANK}, position_count DESC, phrase_id",
    "positions": "position_count DESC, phrase_id",
    "branches": "branch_count DESC, position_count DESC, phrase_id",
    "surahs": "surah_count DESC, position_count DESC, phrase_id",
}


def has_forks(con: sqlite3.Connection) -> bool:
    present = {
        r[0]
        for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('forks', 'fork_branches', 'fork_members')"
        )
    }
    return len(present) == 3 and bool(
        con.execute("SELECT COUNT(*) FROM forks LIMIT 1").fetchone()[0]
    )


def _branches(con: sqlite3.Connection, phrase_id: int) -> list[dict]:
    out = []
    for branch in con.execute(
        "SELECT * FROM fork_branches WHERE phrase_id = ? ORDER BY ordinal", (phrase_id,)
    ):
        members = con.execute(
            "SELECT o.pos_id, o.verse_key, o.surah, o.ayah, o.page, o.juz, s.name_ar "
            "FROM fork_members m JOIN official_positions o ON o.pos_id = m.pos_id "
            "JOIN surahs s ON s.surah = o.surah "
            "WHERE m.branch_id = ? ORDER BY o.start_word_id",
            (branch["branch_id"],),
        ).fetchall()
        out.append(
            {
                "branch_id": branch["branch_id"],
                "ordinal": branch["ordinal"],
                "token_ar": branch["token_ar"],
                "ends_surah": bool(branch["ends_surah"]),
                "position_count": branch["position_count"],
                "is_largest": bool(branch["is_largest"]),
                "positions": [
                    {
                        "pos_id": m["pos_id"],
                        "verse_key": m["verse_key"],
                        "surah": m["surah"],
                        "ayah": m["ayah"],
                        "surah_name_ar": m["name_ar"],
                        "page": m["page"],
                        "juz": m["juz"],
                    }
                    for m in members
                ],
            }
        )
    return out


def fork_index(
    con: sqlite3.Connection,
    *,
    shape: str | None = None,
    min_positions: int = 2,
    surah: int | None = None,
    q: str | None = None,
    sort: str = "useful",
    limit: int = 25,
    offset: int = 0,
) -> dict:
    """The official mutashābihāt as forks, filtered and paged."""
    where = ["f.position_count >= ?"]
    args: list = [min_positions]
    if shape:
        if shape not in SHAPES:
            raise ValueError(f"unknown shape {shape!r}; expected one of {', '.join(SHAPES)}")
        where.append("f.shape = ?")
        args.append(shape)
    if surah:
        where.append(
            "EXISTS (SELECT 1 FROM official_positions o "
            "WHERE o.phrase_id = f.phrase_id AND o.surah = ?)"
        )
        args.append(surah)
    if q:
        where.append("(f.road_ar LIKE ? OR p.text_norm LIKE ?)")
        args += [f"%{q}%", f"%{q}%"]

    clause = " AND ".join(where)
    joined = (
        "FROM forks f JOIN official_phrases p ON p.phrase_id = f.phrase_id "
        f"WHERE {clause}"
    )
    total = con.execute(f"SELECT COUNT(*) {joined}", args).fetchone()[0]
    by_shape = dict(
        con.execute(f"SELECT f.shape, COUNT(*) {joined} GROUP BY f.shape", args)
    )

    order = SORTS.get(sort)
    if order is None:
        raise ValueError(f"unknown sort {sort!r}; expected one of {', '.join(SORTS)}")

    rows = con.execute(
        f"SELECT f.*, p.text_ar AS phrase_ar, p.span_len, p.official_count, "
        f"       p.exact_count {joined} ORDER BY {order} LIMIT ? OFFSET ?",
        args + [limit, offset],
    ).fetchall()

    phrases = []
    for row in rows:
        # The road is the phrase plus whatever the positions still say together;
        # keeping the tail separate lets the page show where the agreement ends.
        tail = row["road_ar"][len(row["phrase_ar"]):].strip()
        phrases.append(
            {
                "phrase_id": row["phrase_id"],
                "phrase_ar": row["phrase_ar"],
                "road_ar": row["road_ar"],
                "road_tail_ar": tail or None,
                "shared_after": row["shared_after"],
                "shape": row["shape"],
                "position_count": row["position_count"],
                "branch_count": row["branch_count"],
                "largest_branch": row["largest_branch"],
                "singleton_branches": row["singleton_branches"],
                "surah_count": row["surah_count"],
                "span_len": row["span_len"],
                "official_count": row["official_count"],
                "exact_count": row["exact_count"],
                "branches": _branches(con, row["phrase_id"]),
            }
        )

    return {
        "params": {
            "shape": shape,
            "min_positions": min_positions,
            "surah": surah,
            "q": q,
            "sort": sort,
            "limit": limit,
            "offset": offset,
        },
        "counts": {"total": total, "returned": len(phrases), "by_shape": by_shape},
        "phrases": phrases,
    }


def fork_detail(con: sqlite3.Connection, phrase_id: int) -> dict:
    """One fork in full: every position with its āyah and its signpost."""
    row = con.execute(
        "SELECT f.*, p.text_ar AS phrase_ar, p.span_len, p.official_count, "
        "       p.exact_count, p.source_verse_key FROM forks f "
        "JOIN official_phrases p ON p.phrase_id = f.phrase_id WHERE f.phrase_id = ?",
        (phrase_id,),
    ).fetchone()
    if row is None:
        raise PhraseNotFound(f"no official phrase {phrase_id}")

    words = _Words(con)
    surah_names = {
        r["surah"]: r["name_ar"] for r in con.execute("SELECT surah, name_ar FROM surahs")
    }
    juz_of = {
        r["verse_key"]: r["juz"] for r in con.execute("SELECT verse_key, juz FROM ayahs")
    }

    branches = _branches(con, phrase_id)
    for branch in branches:
        detailed = []
        for member in branch["positions"]:
            source = con.execute(
                "SELECT o.start_word_id, o.end_word_id, o.verse_key, o.page, "
                "       o.in_official, o.in_exact, o.group_id, o.link, "
                "       g.kind, g.cue_ar, g.cue_window, g.continuation_ar, "
                "       g.continuation_unique, g.strength, g.text_ar, g.evidence "
                "FROM official_positions o LEFT JOIN pegs g ON g.pos_id = o.pos_id "
                "WHERE o.pos_id = ?",
                (member["pos_id"],),
            ).fetchone()
            position = _position(
                con,
                words,
                {
                    "start_word_id": source["start_word_id"],
                    "end_word_id": source["end_word_id"],
                    "verse_key": source["verse_key"],
                    "page": source["page"],
                    "line": None,
                },
                surah_names,
                juz_of,
            )
            position |= {
                "pos_id": member["pos_id"],
                "in_official": bool(source["in_official"]),
                "in_exact": bool(source["in_exact"]),
                "group_id": source["group_id"],
                "link": source["link"],
                "peg": _peg(source),
            }
            detailed.append(position)
        branch["positions"] = detailed

    tail = row["road_ar"][len(row["phrase_ar"]):].strip()
    return {
        "phrase_id": row["phrase_id"],
        "phrase_ar": row["phrase_ar"],
        "road_ar": row["road_ar"],
        "road_tail_ar": tail or None,
        "shared_after": row["shared_after"],
        "shape": row["shape"],
        "position_count": row["position_count"],
        "branch_count": row["branch_count"],
        "largest_branch": row["largest_branch"],
        "singleton_branches": row["singleton_branches"],
        "surah_count": row["surah_count"],
        "span_len": row["span_len"],
        "official_count": row["official_count"],
        "exact_count": row["exact_count"],
        "source_verse_key": row["source_verse_key"],
        "branches": branches,
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


# -- the printed page ---------------------------------------------------------
#
# `pipeline.layout` carried the KFGQPC line table into the corpus, so a page can
# be reproduced line for line rather than reflowed: the same words on the same
# line, the same headings, and every āyah marker in the place it is printed.


class PageNotFound(LookupError):
    """The requested page is outside the muṣḥaf."""


class LayoutMissing(LookupError):
    """The `lines` table has not been built."""


# The basmalah is read out of the corpus at this key rather than written here:
# nothing in this repository composes Qur'anic text of its own (C1).
BASMALAH_KEY = "1:1"


def has_layout(con: sqlite3.Connection) -> bool:
    present = con.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'lines'"
    ).fetchone()
    return bool(present) and bool(
        con.execute("SELECT COUNT(*) FROM lines LIMIT 1").fetchone()[0]
    )


def has_glyphs(con: sqlite3.Connection) -> bool:
    """Whether `pipeline.glyphs` has bound the KFGQPC page fonts to this corpus."""
    present = con.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'glyphs'"
    ).fetchone()
    return bool(present) and bool(
        con.execute("SELECT COUNT(*) FROM glyphs LIMIT 1").fetchone()[0]
    )


def page_count(con: sqlite3.Connection) -> int:
    if not has_layout(con):
        return 0
    return con.execute("SELECT MAX(page) FROM lines").fetchone()[0] or 0


def page_of(con: sqlite3.Connection, surah: int, ayah: int) -> int:
    """The page an āyah starts on."""
    return _ayah_row(con, surah, ayah)["page_start"]


def _page_marks(
    con: sqlite3.Connection, keys: list[str], scope: str
) -> dict[str, dict[str, int]]:
    """Per āyah on the page: how much there is to confuse it with.

    Counted from the rows, per request, for the āyāt of this page only — the
    page marks where a memoriser should stop, and the count is the reason.
    """
    marks = {key: {"official": 0, "phrases": 0} for key in keys}
    if not keys:
        return marks
    holes = ",".join("?" * len(keys))

    if _has_official(con):
        for key, count in con.execute(
            "SELECT a.verse_key, COUNT(DISTINCT o.phrase_id) "
            "FROM ayahs a JOIN official_positions o "
            "  ON o.start_word_id <= a.last_word_id AND o.end_word_id >= a.first_word_id "
            f"WHERE a.verse_key IN ({holes}) GROUP BY a.verse_key",
            keys,
        ):
            marks[key]["official"] = count

    for key, count in con.execute(
        "SELECT a.verse_key, COUNT(DISTINCT o.group_id) "
        "FROM ayahs a JOIN occurrences o "
        "  ON o.start_word_id <= a.last_word_id AND o.end_word_id >= a.first_word_id "
        "JOIN groups g ON g.group_id = o.group_id AND g.scope = ? "
        f"WHERE a.verse_key IN ({holes}) GROUP BY a.verse_key",
        [scope, *keys],
    ):
        marks[key]["phrases"] = count
    return marks


def _basmalah(con: sqlite3.Connection) -> list[dict]:
    return [
        {"word_id": r["word_id"], "text": r["text_uthmani"]}
        for r in con.execute(
            "SELECT w.word_id, w.text_uthmani FROM words w, ayahs a "
            "WHERE a.verse_key = ? AND w.word_id BETWEEN a.first_word_id AND a.last_word_id "
            "ORDER BY w.word_id",
            (BASMALAH_KEY,),
        )
    ]


def measure_lines(con: sqlite3.Connection, limit: int = 8) -> dict:
    """The densest lines in the muṣḥaf, for the page to set its type by.

    A muṣḥaf is set at one size and holds it for 604 pages; density differences
    between pages show up as elongation, not as bigger letters. To hold one size
    the page has to know the widest line in the book, and `width_chars` only
    ranks candidates — the real width depends on the face doing the rendering —
    so the top few are handed over and measured where they will be drawn.
    """
    if not has_layout(con):
        raise LayoutMissing("no page layout; run: python -m pipeline.layout --rebuild")
    rows = con.execute(
        "SELECT page, line, first_word_id, last_word_id, width_chars FROM lines "
        "WHERE line_type = 'ayah' AND first_word_id IS NOT NULL "
        "ORDER BY width_chars DESC LIMIT ?",
        (limit,),
    ).fetchall()
    return {
        "lines": [
            {
                "page": row["page"],
                "line": row["line"],
                "width_chars": row["width_chars"],
                "text": " ".join(
                    w[0]
                    for w in con.execute(
                        "SELECT text_uthmani FROM words WHERE word_id BETWEEN ? AND ? "
                        "ORDER BY word_id",
                        (row["first_word_id"], row["last_word_id"]),
                    )
                ),
            }
            for row in rows
        ]
    }


def mushaf_page(con: sqlite3.Connection, page: int, *, scope: str = DEFAULT_SCOPE) -> dict:
    """One printed page: its lines, the tokens on each, and what repeats there.

    Tokens are walked over the *source* id range of the line, so an āyah marker
    lands where the muṣḥaf prints it — including the lines of this layout that
    open with the marker closing the āyah of the line before.
    """
    if not has_layout(con):
        raise LayoutMissing("no page layout; run: python -m pipeline.layout --rebuild")
    total = page_count(con)
    if not 1 <= page <= total:
        raise PageNotFound(f"page {page} is outside the mushaf (1-{total})")

    rows = con.execute(
        "SELECT line, line_type, is_centered, surah, src_first, src_last "
        "FROM lines WHERE page = ? ORDER BY line",
        (page,),
    ).fetchall()

    words = {
        r["src_word_id"]: r
        for r in con.execute(
            "SELECT word_id, src_word_id, surah, ayah, word_pos, text_uthmani "
            "FROM words WHERE page = ? ORDER BY word_id",
            (page,),
        )
    }
    ids = [r["word_id"] for r in words.values()]
    first_word, last_word = (min(ids), max(ids)) if ids else (0, -1)
    spans = [r["src_first"] for r in rows if r["src_first"] is not None]
    src_lo = min(spans, default=1)
    src_hi = max((r["src_last"] for r in rows if r["src_last"] is not None), default=0)

    # A marker carries no row in `words`; its source id is one past the last word
    # of the āyah it closes, which is enough to place it.
    markers = {
        r["src"]: (r["surah"], r["ayah"])
        for r in con.execute(
            "SELECT a.surah, a.ayah, w.src_word_id + 1 AS src FROM ayahs a "
            "JOIN words w ON w.word_id = a.last_word_id "
            "WHERE w.src_word_id + 1 BETWEEN ? AND ?",
            (src_lo, src_hi),
        )
    }

    # Which words on this page are inside an official mutashābih phrase, so the
    # page can underline the shared wording itself and not merely the āyah.
    phrases_at: dict[int, list[int]] = {}
    if ids and _has_official(con):
        for hit in con.execute(
            "SELECT phrase_id, start_word_id, end_word_id FROM official_positions "
            "WHERE start_word_id <= ? AND end_word_id >= ?",
            (last_word, first_word),
        ):
            lo = max(hit["start_word_id"], first_word)
            hi = min(hit["end_word_id"], last_word)
            for word_id in range(lo, hi + 1):
                phrases_at.setdefault(word_id, []).append(hit["phrase_id"])

    # KFGQPC cuts a font per page, with each glyph already shaped and elongated
    # to fill the line it belongs to. Where those glyphs are bound, they are what
    # the line is made of, and the font's own record of which line a token sits
    # on is what orders them — see pipeline.glyphs.
    glyph_lines: dict[int, list[dict]] = {}
    if has_glyphs(con):
        for row in con.execute(
            "SELECT g.line, g.kind, g.word_id, g.verse_key, g.code_v1, "
            "       w.surah, w.ayah, w.word_pos, w.text_uthmani "
            "FROM glyphs g LEFT JOIN words w ON w.word_id = g.word_id "
            "WHERE g.page = ? ORDER BY g.line, g.ordinal",
            (page,),
        ):
            key = row["verse_key"]
            surah, ayah = (int(part) for part in key.split(":"))
            if row["kind"] == "word":
                token = {
                    "kind": "word",
                    "word_id": row["word_id"],
                    "verse_key": key,
                    "surah": surah,
                    "ayah": ayah,
                    "word_pos": row["word_pos"],
                    "text": row["text_uthmani"],
                    "code": row["code_v1"],
                    "phrase_ids": [],
                }
            else:
                token = {
                    "kind": "marker",
                    "verse_key": key,
                    "surah": surah,
                    "ayah": ayah,
                    "code": row["code_v1"],
                }
            glyph_lines.setdefault(row["line"], []).append(token)

    surah_rows = {r["surah"]: r for r in con.execute("SELECT * FROM surahs ORDER BY surah")}

    keys: list[str] = []
    lines: list[dict] = []
    for row in rows:
        line = {
            "line": row["line"],
            "type": row["line_type"],
            "centered": bool(row["is_centered"]),
        }
        if row["line_type"] == "surah_name":
            surah = surah_rows[row["surah"]]
            line |= {
                "surah": surah["surah"],
                "name_ar": surah["name_ar"],
                "ayah_count": surah["ayah_count"],
                "revelation_place": surah["revelation_place"],
            }
        elif row["line_type"] == "basmallah":
            line["words"] = _basmalah(con)
        elif row["line"] in glyph_lines:
            tokens = glyph_lines[row["line"]]
            for token in tokens:
                if token["kind"] != "word":
                    continue
                if token["verse_key"] not in keys:
                    keys.append(token["verse_key"])
                token["phrase_ids"] = phrases_at.get(token["word_id"], [])
            line["tokens"] = tokens
        else:
            tokens = []
            for src in range(row["src_first"], row["src_last"] + 1):
                word = words.get(src)
                if word is not None:
                    key = f"{word['surah']}:{word['ayah']}"
                    if key not in keys:
                        keys.append(key)
                    tokens.append(
                        {
                            "kind": "word",
                            "word_id": word["word_id"],
                            "verse_key": key,
                            "surah": word["surah"],
                            "ayah": word["ayah"],
                            "word_pos": word["word_pos"],
                            "text": word["text_uthmani"],
                            "phrase_ids": phrases_at.get(word["word_id"], []),
                        }
                    )
                elif src in markers:
                    surah, ayah = markers[src]
                    tokens.append(
                        {
                            "kind": "marker",
                            "verse_key": f"{surah}:{ayah}",
                            "surah": surah,
                            "ayah": ayah,
                        }
                    )
            line["tokens"] = tokens
        lines.append(line)

    # The muṣḥaf prints a marker in the margin where a juz', a ḥizb or a rub'
    # opens. A division opens at whichever of its āyāt comes first in the text.
    meta: dict[str, sqlite3.Row] = {}
    if keys:
        meta = {
            r["verse_key"]: r
            for r in con.execute(
                "SELECT verse_key, juz, hizb, rub, "
                "  first_word_id = (SELECT MIN(x.first_word_id) FROM ayahs x "
                "                   WHERE x.juz = a.juz) AS starts_juz, "
                "  first_word_id = (SELECT MIN(x.first_word_id) FROM ayahs x "
                "                   WHERE x.hizb = a.hizb) AS starts_hizb, "
                "  first_word_id = (SELECT MIN(x.first_word_id) FROM ayahs x "
                "                   WHERE x.rub = a.rub) AS starts_rub "
                f"FROM ayahs a WHERE verse_key IN ({','.join('?' * len(keys))})",
                keys,
            )
        }
    marks = _page_marks(con, keys, scope)

    ayat = []
    for key in keys:
        surah, ayah = (int(part) for part in key.split(":"))
        ayat.append(
            {
                "verse_key": key,
                "surah": surah,
                "ayah": ayah,
                "surah_name_ar": surah_rows[surah]["name_ar"],
                "juz": meta[key]["juz"],
                "hizb": meta[key]["hizb"],
                "rub": meta[key]["rub"],
                "starts_juz": bool(meta[key]["starts_juz"]),
                "starts_hizb": bool(meta[key]["starts_hizb"]),
                "starts_rub": bool(meta[key]["starts_rub"]),
                "official": marks[key]["official"],
                "phrases": marks[key]["phrases"],
            }
        )

    on_page = sorted(
        {a["surah"] for a in ayat}
        | {line["surah"] for line in lines if line["type"] == "surah_name"}
    )
    return {
        "page": page,
        "pages": total,
        "prev": page - 1 if page > 1 else None,
        "next": page + 1 if page < total else None,
        "lines_printed": len(lines),
        # When set, the page is drawn in the muṣḥaf's own glyphs and this is the
        # font that holds them. Heading and basmalah lines are not in it.
        "glyph_font": f"/fonts/qcf-v1/p{page}.woff2" if glyph_lines else None,
        "juz": ayat[0]["juz"] if ayat else None,
        "hizb": ayat[0]["hizb"] if ayat else None,
        "surahs": [
            {
                "surah": s,
                "name_ar": surah_rows[s]["name_ar"],
                "ayah_count": surah_rows[s]["ayah_count"],
                "revelation_place": surah_rows[s]["revelation_place"],
            }
            for s in on_page
        ],
        "counts": {
            "ayat": len(ayat),
            "with_official": sum(1 for a in ayat if a["official"]),
            "with_phrases": sum(1 for a in ayat if a["phrases"]),
        },
        "ayat": ayat,
        "lines": lines,
    }


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
    official: bool = True,
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

    has_official = official and _has_official(con)
    official_phrases = (
        official_matches(con, surah, ayah, words, surah_names, juz_of)
        if has_official
        else []
    )

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
            "official": has_official,
        },
        "counts": {
            "matches": total,
            "returned": len(matches),
            "with_dabit": with_dabit,
            "other_positions": other_positions,
            "distinct_ayat": distinct_ayat,
            "official_phrases": len(official_phrases),
            "official_positions": sum(len(p["elsewhere"]) for p in official_phrases),
        },
        "official": official_phrases,
        "matches": matches,
    }
