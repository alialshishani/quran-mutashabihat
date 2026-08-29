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
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
CODES = ROOT / "data" / "raw" / "qcf-v1-codes"

# The glyph codes of a page are one contiguous run through the font's private
# encoding. Across all 604 pages the run breaks in exactly one place, and it is
# Unicode's own: U+FBB2–U+FBD2 is unassigned inside Arabic Presentation Forms-A,
# and the encoding steps over it. So the next code after any code is knowable
# without the font, which is what lets a missing token be filled in.
def succ(code: str) -> str:
    return "".join(
        chr(0xFBD3 if ord(c) == 0xFBB1 else ord(c) + 1) for c in code
    )


def succ_n(code: str, times: int) -> str:
    for _ in range(times):
        code = succ(code)
    return code


# The code file stops one word short of the page here: 13:37's last word,
# `وَاقٍۢ`, has no token of its own, so every glyph after it on page 254 is bound
# to the token before its own and the page's last glyph is never drawn. That
# sets six of the page's fifteen lines between 5% under the measure and 16%
# over. The run is contiguous, so the repair is exact rather than a guess: the
# word takes the code after its neighbour's, and the rest of the page steps up
# by one. With it, every line of 254 sets within 0.5% of the measure but the
# last, which lands at 2.5%.
SHORT_BY_ONE = {"13:37"}


# A token can straddle a line break: the word ends one line and the sign that
# trails it opens the next. The code file carries one line per token and cannot
# say so, and the muṣḥaf does it in one place — 38:24 on page 454, where the
# word is `وَأَنَابَ` and the sign is the sajdah ۩ that opens line 12. Left whole
# on line 11 it sets that line 4.8% over the measure and line 12 5.3% under;
# split, both land within 0.3% of the page, which is the band every other line
# on 454 sits in. Keyed by the token's own verse key and position in the code
# file, so it names the one place rather than describing a rule.
SIGN_OPENS_NEXT_LINE = {("38:24", 32)}

SCHEMA = """
CREATE TABLE IF NOT EXISTS glyphs (
  page      INTEGER NOT NULL,
  line      INTEGER NOT NULL,
  ordinal   INTEGER NOT NULL,   -- render order along the line
  kind      TEXT NOT NULL,      -- word | end | sign
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

    # Where the corpus splits a pair the code file joined, the code file has one
    # word token fewer than the āyah has words, and every position after the
    # join is offset by one. Three āyāt are like this — 2:181, 8:6 and 13:37 —
    # and the cause is the same in all three: `بَعْدَ مَا`, written as one token
    # by the source the codes come from and as two by the Uthmānī one. Binding
    # by the token's own position would hand every later word of those āyāt its
    # neighbour's glyph and leave the last word of the āyah with none.
    #
    # The join is found by the pair itself rather than by "the first token in
    # the āyah that carries two glyphs": two glyphs is the ordinary way to write
    # a word that trails a waqf sign, and 13:37 has one of those four words
    # before its join.
    corpus_len: dict[tuple[int, int], int] = {
        (row["surah"], row["ayah"]): row["n"]
        for row in con.execute(
            "SELECT surah, ayah, COUNT(*) AS n FROM words GROUP BY surah, ayah"
        )
    }
    source_len: Counter[str] = Counter()
    for path in files:
        for token in load_page(path):
            if token["kind"] == "word":
                source_len[token["verse_key"]] += 1

    normalised: dict[tuple[int, int], list[str]] = defaultdict(list)
    for row in con.execute(
        "SELECT surah, ayah, text_norm FROM words ORDER BY surah, ayah, word_pos"
    ):
        normalised[(row["surah"], row["ayah"])].append(row["text_norm"])

    # verse_key -> the corpus position of `بعد`, whose token covers `ما` too.
    join_at: dict[str, int] = {}
    for key, count in source_len.items():
        surah, ayah = (int(part) for part in key.split(":"))
        if key in SHORT_BY_ONE or corpus_len.get((surah, ayah), 0) != count + 1:
            continue
        words = normalised[(surah, ayah)]
        for index in range(len(words) - 1):
            if words[index] == "بعد" and words[index + 1] == "ما":
                join_at[key] = index + 1
                break
        else:
            complaints.append(
                f"{key}: the corpus has {corpus_len[(surah, ayah)]} words to the "
                f"code file's {count}, and the extra one is not `بعد ما`"
            )

    for path in files:
        offset = 0
        shift = 0
        current = None
        for token in load_page(path):
            key = token["verse_key"]
            surah, ayah = (int(part) for part in key.split(":"))
            if key != current:
                current, offset = key, 0
            page = token["page"]

            if token["kind"] == "word":
                # A token can carry more than one glyph. Ordinarily that is one
                # word the font sets in two slots — a word and the waqf sign
                # after it — and the codes stay together on the one row. At the
                # join they are the two words, and one goes to each; where the
                # join has only a single glyph the second word has none of its
                # own and is set as part of its neighbour, which is what the
                # muṣḥaf does with it.
                at_join = join_at.get(key) == token["position"] + offset
                # A code is one glyph per character. Where a token carries two,
                # the code file writes them together or with a space between —
                # both forms occur, and the space is a separator in the record,
                # not a glyph on the line.
                codes = [succ_n(c, shift) for c in token["code"].replace(" ", "")]
                whole = "".join(codes)
                parts = codes if at_join and len(codes) > 1 else [whole]
                wraps = (key, token["position"]) in SIGN_OPENS_NEXT_LINE
                if wraps:
                    if len(codes) != 2:
                        complaints.append(
                            f"{key} word {token['position']}: recorded as a word "
                            f"and a sign across a line break, but it has "
                            f"{len(codes)} glyph(s), not 2"
                        )
                        continue
                    parts = codes[:1]

                bound_line: int | None = None
                for index, code in enumerate(parts):
                    position = token["position"] + offset + index
                    found = word_at.get((surah, ayah, position))
                    if found is None:
                        complaints.append(
                            f"{key} word {position}: no such word in the corpus"
                        )
                        continue
                    word_id, was_page, was_line = found
                    if was_page != page:
                        complaints.append(
                            f"{key} word {position}: codes say page {page}, "
                            f"layout says page {was_page}"
                        )
                        continue
                    # The line comes from the layout, not from the code file.
                    # The two disagree about a handful of words at a line
                    # boundary, and where they do the layout is the one the
                    # print bears out: on pages 177 and 443 the code file's
                    # placement puts a glyph on the line above the one it is cut
                    # for, which sets that line ~9% over the measure and — since
                    # a page takes its type size from its widest line — every
                    # other line on the page short of it.
                    if was_line != token["line"]:
                        notes.append(
                            f"{key} word {position}: line {token['line']} per the "
                            f"code file, {was_line} per the layout; the layout is used"
                        )
                    seen_words.add(word_id)
                    bound_line = was_line
                    ordinals[(page, was_line)] += 1
                    rows.append(
                        (
                            page,
                            was_line,
                            ordinals[(page, was_line)],
                            "word",
                            word_id,
                            key,
                            code,
                        )
                    )
                # The word the code file left out, and the step that pays for
                # it: from here to the end of the page every code moves up one.
                if key in SHORT_BY_ONE and token["position"] == source_len[key]:
                    position = token["position"] + 1
                    found = word_at.get((surah, ayah, position))
                    if found is None:
                        complaints.append(
                            f"{key}: recorded as one word short of the code file, "
                            f"but the corpus has no word {position}"
                        )
                        continue
                    word_id, _, was_line = found
                    seen_words.add(word_id)
                    ordinals[(page, was_line)] += 1
                    rows.append(
                        (
                            page,
                            was_line,
                            ordinals[(page, was_line)],
                            "word",
                            word_id,
                            key,
                            succ(whole[-1]),
                        )
                    )
                    shift += 1

                if wraps and bound_line is not None:
                    # The sign the word trails, on the line it opens. It is not
                    # a word and not an āyah marker, so it is neither: it draws,
                    # and it is not a tap target.
                    line = bound_line + 1
                    ordinals[(page, line)] += 1
                    rows.append(
                        (page, line, ordinals[(page, line)], "sign", None, key, codes[1])
                    )

                # The join eats two corpus positions whether it had one glyph
                # to give them or two.
                if at_join:
                    offset += 1
            else:
                placed = marker_line.get(key)
                if placed is None:
                    complaints.append(f"{key}: marker has no line in the layout")
                    continue
                if placed[0] != page:
                    complaints.append(
                        f"{key} marker: codes say page {page}, layout says page {placed[0]}"
                    )
                    continue
                line = token["line"]
                if placed[1] != line:
                    notes.append(
                        f"{key} marker: line {line} per the font, {placed[1]} per the layout"
                    )
                ordinals[(page, line)] += 1
                rows.append(
                    (
                        page,
                        line,
                        ordinals[(page, line)],
                        "end",
                        None,
                        key,
                        succ_n(token["code"].replace(" ", ""), shift),
                    )
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

    # The notes name āyāt and quote the muṣḥaf, and a Windows console is cp1252
    # by default; printing them there ended the run with a UnicodeEncodeError
    # after the write had already been committed.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")

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
