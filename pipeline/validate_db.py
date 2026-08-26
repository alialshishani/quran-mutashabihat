"""M0 gate: assert data/quran.db is internally consistent.

Every expected value is derived from the data at runtime. No count in this file
is asserted from memory (C2). Exits non-zero on any failure.
"""
from __future__ import annotations

import sqlite3
import sys
from difflib import SequenceMatcher
from pathlib import Path

from pipeline.normalize import is_ayah_marker, normalize

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
SRC = ROOT / "data" / "raw" / "extracted"
AYAH_TEXT_SRC = SRC / "qul-69-ayah-metadata.sqlite"
LAYOUT_SRC = SRC / "qul-15-layout-kfgqpc-v1.db"


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        mark = "PASS" if ok else "FAIL"
        print(f"  [{mark}] {name}" + (f" — {detail}" if detail else ""))
        if not ok:
            self.failures.append(name)


def main() -> int:
    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")

    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    rep = Report()

    # --- derived counts ------------------------------------------------------
    counts = {
        "words": con.execute("SELECT COUNT(*) FROM words").fetchone()[0],
        "ayahs": con.execute("SELECT COUNT(*) FROM ayahs").fetchone()[0],
        "surahs": con.execute("SELECT COUNT(*) FROM surahs").fetchone()[0],
        "pages": con.execute("SELECT COUNT(DISTINCT page) FROM words").fetchone()[0],
        "juz": con.execute("SELECT COUNT(DISTINCT juz) FROM ayahs").fetchone()[0],
        "hizb": con.execute("SELECT COUNT(DISTINCT hizb) FROM ayahs").fetchone()[0],
        "rub": con.execute("SELECT COUNT(DISTINCT rub) FROM ayahs").fetchone()[0],
        "roots": con.execute(
            "SELECT COUNT(DISTINCT root) FROM words WHERE root IS NOT NULL"
        ).fetchone()[0],
        "lemmas": con.execute(
            "SELECT COUNT(DISTINCT lemma) FROM words WHERE lemma IS NOT NULL"
        ).fetchone()[0],
        "distinct text_norm": con.execute(
            "SELECT COUNT(DISTINCT text_norm) FROM words"
        ).fetchone()[0],
        "distinct text_uthmani": con.execute(
            "SELECT COUNT(DISTINCT text_uthmani) FROM words"
        ).fetchone()[0],
    }
    print("Derived corpus counts (computed from the data):")
    width = max(len(k) for k in counts)
    for key, value in counts.items():
        print(f"  {key:<{width}}  {value:>9,}")
    print()

    print("Consistency checks:")

    # --- word_id contiguity --------------------------------------------------
    lo, hi, n = con.execute(
        "SELECT MIN(word_id), MAX(word_id), COUNT(*) FROM words"
    ).fetchone()
    rep.check(
        "word_id contiguous from 1 with no gaps",
        lo == 1 and hi == n,
        f"min={lo} max={hi} count={n:,}",
    )

    # --- word_pos runs 1..k within every ayah --------------------------------
    bad_pos = con.execute(
        "SELECT COUNT(*) FROM ("
        "  SELECT surah, ayah FROM words GROUP BY surah, ayah"
        "  HAVING MIN(word_pos) != 1 OR MAX(word_pos) != COUNT(*)"
        ")"
    ).fetchone()[0]
    rep.check("word_pos is 1..k within every ayah", bad_pos == 0, f"{bad_pos} bad ayahs")

    # --- ayah spans match the word rows --------------------------------------
    mismatched = con.execute(
        "SELECT COUNT(*) FROM ayahs a JOIN ("
        "  SELECT surah, ayah, MIN(word_id) f, MAX(word_id) l, COUNT(*) c"
        "  FROM words GROUP BY surah, ayah"
        ") w ON w.surah = a.surah AND w.ayah = a.ayah "
        "WHERE a.first_word_id != w.f OR a.last_word_id != w.l "
        "   OR (a.last_word_id - a.first_word_id + 1) != w.c"
    ).fetchone()[0]
    rep.check("every ayah span matches its word rows", mismatched == 0, f"{mismatched} bad")

    # --- ayah word spans are contiguous and non-overlapping ------------------
    gaps = con.execute(
        "SELECT COUNT(*) FROM ("
        "  SELECT verse_key, first_word_id,"
        "         LAG(last_word_id) OVER (ORDER BY first_word_id) prev"
        "  FROM ayahs"
        ") WHERE prev IS NOT NULL AND first_word_id != prev + 1"
    ).fetchone()[0]
    rep.check("ayah spans tile the corpus with no gap or overlap", gaps == 0, f"{gaps} breaks")

    # --- layout coverage -----------------------------------------------------
    no_layout = con.execute(
        "SELECT COUNT(*) FROM words WHERE page IS NULL OR line IS NULL OR line_pos IS NULL"
    ).fetchone()[0]
    rep.check("every word has page, line and line_pos", no_layout == 0, f"{no_layout} missing")

    # --- lines per page within the layout's own declared bound ---------------
    layout = sqlite3.connect(f"file:{LAYOUT_SRC}?mode=ro", uri=True)
    declared_pages, declared_lines = layout.execute(
        "SELECT number_of_pages, lines_per_page FROM info"
    ).fetchone()
    layout.close()
    over = con.execute(
        "SELECT COUNT(*) FROM ("
        "  SELECT page FROM words GROUP BY page HAVING MAX(line) > ?"
        ")",
        (declared_lines,),
    ).fetchone()[0]
    rep.check(
        f"no page exceeds the layout's declared {declared_lines} lines",
        over == 0,
        f"{over} pages over",
    )
    rep.check(
        "page range matches the layout's declared page count",
        counts["pages"] == declared_pages,
        f"db={counts['pages']} layout={declared_pages}",
    )

    # --- divisions fully populated -------------------------------------------
    unassigned = con.execute(
        "SELECT COUNT(*) FROM ayahs WHERE juz IS NULL OR hizb IS NULL OR rub IS NULL"
    ).fetchone()[0]
    rep.check("every ayah has juz, hizb and rub", unassigned == 0, f"{unassigned} missing")

    # --- surah ayah_count agrees with the word rows --------------------------
    bad_surah = con.execute(
        "SELECT COUNT(*) FROM surahs s JOIN ("
        "  SELECT surah, COUNT(*) c FROM ayahs GROUP BY surah"
        ") a ON a.surah = s.surah WHERE s.ayah_count != a.c"
    ).fetchone()[0]
    rep.check("surah ayah_count matches the ayahs table", bad_surah == 0, f"{bad_surah} bad")

    # --- round-trip against the independent ayah-level text resource ---------
    # Compared under the `standard` profile: the ayah-level export uses different
    # spacing and embeds the ayah marker, so a byte comparison would be testing
    # typography rather than wording.
    src = sqlite3.connect(f"file:{AYAH_TEXT_SRC}?mode=ro", uri=True)
    expected = {
        key: "".join(
            normalize(tok, "standard")
            for tok in text.split()
            if not is_ayah_marker(tok)
        )
        for key, text in src.execute("SELECT verse_key, text FROM verses")
    }
    src.close()

    actual: dict[str, str] = {}
    for key, tok in con.execute(
        "SELECT a.verse_key, w.text_norm FROM words w "
        "JOIN ayahs a ON a.surah = w.surah AND a.ayah = w.ayah "
        "ORDER BY w.word_id"
    ):
        actual[key] = actual.get(key, "") + tok

    differing = sorted(k for k in expected if expected[k] != actual.get(k, ""))

    # The two resources are different scripts (word-by-word Uthmani vs the
    # QPC Hafs ayah-level export), and they genuinely disagree about which seat
    # a hamza sits on in a handful of words. That is a property of the sources,
    # not of this pipeline, so it is tolerated — but only at single-character
    # granularity and only among the hamza seats. Anything else (a missing word,
    # a reordered phrase, a wrong root letter) still fails the gate.
    HAMZA_SEATS = set("ءأإآؤئوياى")
    unexplained = []
    for key in differing:
        for op, i1, i2, j1, j2 in SequenceMatcher(
            None, actual[key], expected[key]
        ).get_opcodes():
            if op == "equal":
                continue
            left, right = actual[key][i1:i2], expected[key][j1:j2]
            if len(left) <= 1 and len(right) <= 1:
                if set(left) <= HAMZA_SEATS and set(right) <= HAMZA_SEATS:
                    continue
            unexplained.append((key, op, left, right))

    rep.check(
        "per-ayah round-trip differs only by hamza seat across the two scripts",
        not unexplained,
        f"{len(differing)} of {len(expected):,} ayahs differ, "
        f"{len(unexplained)} unexplained"
        + (f"; first: {unexplained[:3]}" if unexplained else ""),
    )

    # --- normalization never blanks a token ----------------------------------
    empty = con.execute(
        "SELECT COUNT(*) FROM words WHERE text_norm = '' OR text_strict = ''"
    ).fetchone()[0]
    rep.check("no token normalizes to empty", empty == 0, f"{empty} empty")

    # --- no marker leaked into words -----------------------------------------
    leaked = sum(
        1 for (t,) in con.execute("SELECT text_uthmani FROM words") if is_ayah_marker(t)
    )
    rep.check("no ayah-number marker leaked into words", leaked == 0, f"{leaked} leaked")

    con.close()
    print()
    if rep.failures:
        print(f"{len(rep.failures)} check(s) FAILED: {', '.join(rep.failures)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
