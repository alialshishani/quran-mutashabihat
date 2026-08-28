"""Bind the KFGQPC glyph codes to the corpus.

`scripts.fetch_qcf` brings down two things per page: the font KFGQPC cut for
that page, and the code naming each glyph inside it. This pass binds the second
to the corpus, so a word in `words` knows the glyph that prints it.

    python -m pipeline.glyphs --rebuild

The binding is by position, not by text: a token at (sūrah, āyah, position) in
the code file is the word at the same place in `words`. That is exact, and it is
also checkable — the code files say which page and line every token prints on,
and so does the layout the corpus was built from. The two are independent
records of the same 1405H typesetting, so they have to agree, and this pass
stops if they do not rather than binding a code to the wrong word.

Āyah markers get their glyph too. They are tokens on the page with a place on a
line and no row in `words`, so they are keyed by the āyah they close.

Additive: it touches nothing the other passes wrote, and is dropped and rebuilt
on its own.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
CODES = ROOT / "data" / "raw" / "qcf-v1-codes"

SCHEMA = """
CREATE TABLE IF NOT EXISTS glyphs (
  page      INTEGER NOT NULL,
  line      INTEGER NOT NULL,
  ordinal   INTEGER NOT NULL,   -- render order along the line
  kind      TEXT NOT NULL,      -- word | end
  word_id   INTEGER,            -- NULL on an āyah marker
  verse_key TEXT NOT NULL,
  code_v1   TEXT NOT NULL,
  PRIMARY KEY (page, line, ordinal)
);
CREATE INDEX IF NOT EXISTS idx_glyphs_word ON glyphs(word_id);
"""


def load_page(path: Path) -> list[dict]:
    """Every token of one page, in the order it prints."""
    data = json.loads(path.read_text(encoding="utf-8"))
    tokens = []
    for verse in data["verses"]:
        for token in verse["words"]:
            tokens.append(
                {
                    "verse_key": verse["verse_key"],
                    "position": token["position"],
                    "kind": "end" if token["char_type_name"] != "word" else "word",
                    "line": token["line_number"],
                    "page": token["page_number"],
                    "code": token["code_v1"],
                }
            )
    return tokens


def build(
    con: sqlite3.Connection, files: list[Path]
) -> tuple[list[tuple], list[str], list[str]]:
    word_at = {
        (row["surah"], row["ayah"], row["word_pos"]): (row["word_id"], row["page"], row["line"])
        for row in con.execute("SELECT word_id, surah, ayah, word_pos, page, line FROM words")
    }
    marker_line = {
        row["verse_key"]: (row["page"], row["line"])
        for row in con.execute(
            "SELECT a.verse_key, l.page, l.line FROM ayahs a "
            "JOIN words w ON w.word_id = a.last_word_id "
            "JOIN lines l ON w.src_word_id + 1 BETWEEN l.src_first AND l.src_last"
        )
    }

    rows: list[tuple] = []
    complaints: list[str] = []
    notes: list[str] = []
    seen_words: set[int] = set()
    ordinals: dict[tuple[int, int], int] = defaultdict(int)

    for path in files:
        for token in load_page(path):
            key = token["verse_key"]
            surah, ayah = (int(part) for part in key.split(":"))
            # The glyph is cut to fill the line the font puts it on, so where the
            # font's record and the layout table disagree about which line a word
            # sits on, the font's is the one that renders correctly. The
            # disagreement is still worth saying out loud.
            page, line = token["page"], token["line"]

            if token["kind"] == "word":
                found = word_at.get((surah, ayah, token["position"]))
                if found is None:
                    complaints.append(
                        f"{key} word {token['position']}: no such word in the corpus"
                    )
                    continue
                word_id, was_page, was_line = found
                if was_page != page:
                    complaints.append(
                        f"{key} word {token['position']}: codes say page {page}, "
                        f"layout says page {was_page}"
                    )
                    continue
                if was_line != line:
                    notes.append(
                        f"{key} word {token['position']}: line {line} per the font, "
                        f"{was_line} per the layout"
                    )
                seen_words.add(word_id)
            else:
                word_id = None
                placed = marker_line.get(key)
                if placed is None:
                    complaints.append(f"{key}: marker has no line in the layout")
                    continue
                if placed[0] != page:
                    complaints.append(
                        f"{key} marker: codes say page {page}, layout says page {placed[0]}"
                    )
                    continue
                if placed[1] != line:
                    notes.append(
                        f"{key} marker: line {line} per the font, {placed[1]} per the layout"
                    )

            ordinals[(page, line)] += 1
            rows.append(
                (page, line, ordinals[(page, line)], token["kind"], word_id, key, token["code"])
            )

    # A word with no glyph of its own is one the font sets together with its
    # neighbour — a single token carrying two glyphs where the Uthmānī source
    # splits the pair. The merge never crosses an āyah, so nothing that is keyed
    # by āyah loses by it; only a word-level highlight covers the pair at once.
    pages = sorted({int(path.stem[1:]) for path in files})
    unbound = [
        (row["word_id"], f"{row['surah']}:{row['ayah']}")
        for row in con.execute(
            "SELECT word_id, surah, ayah FROM words WHERE page IN "
            f"({','.join('?' * len(pages))})",
            pages,
        )
        if row["word_id"] not in seen_words
    ]
    if unbound:
        where = sorted({key for _, key in unbound})
        notes.append(
            f"{len(unbound)} word(s) set as part of a neighbouring token, in "
            f"{len(where)} āyah(s): {', '.join(where[:6])}"
        )
    return rows, complaints, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rebuild", action="store_true", help="drop and recreate")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")
    files = sorted(CODES.glob("p*.json"), key=lambda p: int(p.stem[1:]))
    if not files:
        sys.exit(f"no code files in {CODES}; run: python -m scripts.fetch_qcf")

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    if not con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='lines'"
    ).fetchone():
        sys.exit("no lines table; run: python -m pipeline.layout --rebuild")

    if args.rebuild:
        con.execute("DROP TABLE IF EXISTS glyphs")
    con.executescript(SCHEMA)
    if con.execute("SELECT COUNT(*) FROM glyphs").fetchone()[0]:
        sys.exit("glyphs already populated; pass --rebuild")

    rows, complaints, notes = build(con, files)
    if complaints:
        for line in complaints[:10]:
            print(f"  {line}", file=sys.stderr)
        sys.exit(
            f"{len(complaints)} irreconcilable difference(s) between the glyph codes "
            "and the corpus; nothing written"
        )

    con.executemany("INSERT INTO glyphs VALUES (?,?,?,?,?,?,?)", rows)
    con.commit()
    for note in notes:
        print(f"  note: {note}")

    pages = con.execute("SELECT COUNT(DISTINCT page) FROM glyphs").fetchone()[0]
    words = con.execute("SELECT COUNT(*) FROM glyphs WHERE kind='word'").fetchone()[0]
    ends = con.execute("SELECT COUNT(*) FROM glyphs WHERE kind='end'").fetchone()[0]
    print(f"glyphs: {len(rows):,} across {pages:,} pages ({words:,} words, {ends:,} markers)")
    if pages < 604:
        print(f"  {604 - pages} page(s) not yet fetched; run: python -m scripts.fetch_qcf")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
