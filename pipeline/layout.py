"""Carry the muṣḥaf page layout into the corpus as a `lines` table.

`pipeline.ingest` already stamps every word with the page, line and position it
prints at. That is enough to find a word on a page; it is not enough to *set* a
page, because a printed page also carries lines that hold no word — the sūrah
heading and the basmalah — and because an āyah marker is a token with a place on
a line and no row in `words`.

    python -m pipeline.layout --rebuild

The pass is additive: it reads the same KFGQPC layout database the corpus was
ingested from (whichever one `meta.layout` names) and writes one row per printed
line. It never touches `words`, so it can be re-run without rebuilding anything.

Āyah markers keep their place through the source id range. A marker's id in the
source script is one past the last word of the āyah it closes, so a marker sits
on the line whose source range contains that id — which is how a marker ends up
at the head of a line 566 times in this layout, one line after the āyah it ends.

Nothing here contains Qur'anic text: the pass copies word id ranges, not tokens.
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
SRC = ROOT / "data" / "raw" / "extracted"

SCHEMA = """
CREATE TABLE IF NOT EXISTS lines (
  page        INTEGER NOT NULL,
  line        INTEGER NOT NULL,
  line_type   TEXT NOT NULL,     -- surah_name | basmallah | ayah
  is_centered INTEGER NOT NULL,  -- centred rather than justified to both margins
  surah       INTEGER,           -- the sūrah a heading line announces
  first_word_id INTEGER,         -- corpus word ids, NULL on a line with no word
  last_word_id  INTEGER,
  src_first   INTEGER,           -- source script ids, markers included
  src_last    INTEGER,
  PRIMARY KEY (page, line)
);
"""


def layout_path(con: sqlite3.Connection) -> Path:
    """The layout database the corpus was ingested from, per `meta`."""
    row = con.execute("SELECT value FROM meta WHERE key = 'layout'").fetchone()
    if row is None:
        sys.exit("meta has no 'layout' key; run: python -m pipeline.ingest --rebuild")
    path = SRC / row[0]
    if not path.exists():
        sys.exit(f"missing layout source: {path}\nrun: python -m scripts.extract")
    return path


def build(con: sqlite3.Connection) -> tuple[list[tuple], list[str]]:
    """One row per printed line, plus whatever disagreed with `words`."""
    word_of_src = dict(con.execute("SELECT src_word_id, word_id FROM words"))
    stamped = {
        (row[0], row[1]): (row[2], row[3])
        for row in con.execute(
            "SELECT page, line, MIN(word_id), MAX(word_id) FROM words "
            "WHERE page IS NOT NULL GROUP BY page, line"
        )
    }

    src = sqlite3.connect(f"file:{layout_path(con)}?mode=ro", uri=True)
    rows: list[tuple] = []
    complaints: list[str] = []
    for page, line, kind, centered, first, last, surah in src.execute(
        "SELECT page_number, line_number, line_type, is_centered, "
        "       first_word_id, last_word_id, surah_number FROM pages "
        "ORDER BY page_number, line_number"
    ):
        src_first = int(first) if str(first) != "" else None
        src_last = int(last) if str(last) != "" else None
        word_ids = (
            [word_of_src[w] for w in range(src_first, src_last + 1) if w in word_of_src]
            if src_first is not None
            else []
        )
        rows.append(
            (
                page,
                line,
                kind,
                int(centered),
                int(surah) if str(surah) != "" else None,
                min(word_ids) if word_ids else None,
                max(word_ids) if word_ids else None,
                src_first,
                src_last,
            )
        )
        # The line is only usable if it agrees with the page/line already stamped
        # on the words themselves — the two come from the same source, and a
        # disagreement means the corpus was ingested from a different layout.
        if word_ids and stamped.get((page, line)) != (min(word_ids), max(word_ids)):
            complaints.append(
                f"page {page} line {line}: layout says "
                f"{min(word_ids)}–{max(word_ids)}, words say {stamped.get((page, line))}"
            )
    src.close()
    return rows, complaints


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rebuild", action="store_true", help="drop and recreate")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")

    con = sqlite3.connect(DB)
    if args.rebuild:
        con.execute("DROP TABLE IF EXISTS lines")
    con.executescript(SCHEMA)
    if con.execute("SELECT COUNT(*) FROM lines").fetchone()[0]:
        sys.exit("lines already populated; pass --rebuild")

    rows, complaints = build(con)
    if complaints:
        for complaint in complaints[:10]:
            print(f"  {complaint}", file=sys.stderr)
        sys.exit(
            f"{len(complaints)} line(s) disagree with the page/line stamped on words; "
            "the corpus and the layout are out of step"
        )

    con.executemany("INSERT INTO lines VALUES (?,?,?,?,?,?,?,?,?)", rows)
    con.commit()

    pages = con.execute("SELECT COUNT(DISTINCT page) FROM lines").fetchone()[0]
    kinds = dict(
        con.execute("SELECT line_type, COUNT(*) FROM lines GROUP BY line_type ORDER BY 2 DESC")
    )
    placed = con.execute(
        "SELECT COUNT(*) FROM words w WHERE EXISTS ("
        "  SELECT 1 FROM lines l WHERE l.page = w.page AND l.line = w.line)"
    ).fetchone()[0]
    total = con.execute("SELECT COUNT(*) FROM words").fetchone()[0]
    print(f"lines: {len(rows):,} across {pages:,} pages   {kinds}")
    print(f"words placed on a line: {placed:,} of {total:,}")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
