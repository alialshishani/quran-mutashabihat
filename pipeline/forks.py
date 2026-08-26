"""Where a shared road splits.

    python -m pipeline.forks --rebuild

A phrase that repeats is not by itself worth studying. What costs a reciter is
the fork: a stretch of wording they have recited before, followed by a point
where it goes two ways, and nothing in the road itself says which. This pass
turns each official mutashābih phrase into that shape.

  road            the phrase, plus every word after it that all its positions
                  still share — you are still on one road while they agree
  fork            the first word where the positions stop agreeing
  branch          one way out of the fork, and the positions that take it
  signpost        the cue from `pipeline.pegs`: what told you which fork you
                  were at, before you had to choose

The shapes are counted, not assumed. Of the 809 phrases, 731 fork on the very
next word and the rest run on together for up to nine more; 457 fork exactly two
ways, and in 448 a single position leaves the road the others take — the shape
that carries the most for the least memorising.
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"

# How far past the phrase to keep looking for the split. Positions still in step
# after this many words are not a fork a reciter meets; they are two roads that
# stay together well past the point of confusion.
MAX_SHARED = 12

SCHEMA = """
CREATE TABLE IF NOT EXISTS forks (
  phrase_id INTEGER PRIMARY KEY,
  shared_after INTEGER,
  road_ar TEXT,
  branch_count INTEGER,
  position_count INTEGER,
  largest_branch INTEGER,
  singleton_branches INTEGER,
  surah_count INTEGER,
  shape TEXT
);
CREATE TABLE IF NOT EXISTS fork_branches (
  branch_id INTEGER PRIMARY KEY,
  phrase_id INTEGER NOT NULL,
  ordinal INTEGER,
  token_ar TEXT,
  token_norm TEXT,
  ends_surah INTEGER,
  position_count INTEGER,
  is_largest INTEGER
);
CREATE TABLE IF NOT EXISTS fork_members (
  branch_id INTEGER NOT NULL,
  pos_id INTEGER NOT NULL,
  PRIMARY KEY (branch_id, pos_id)
);
CREATE INDEX IF NOT EXISTS idx_branch_phrase ON fork_branches(phrase_id);
CREATE INDEX IF NOT EXISTS idx_member_pos ON fork_members(pos_id);
"""


def shape_of(branch_count: int, positions: int, largest: int, singletons: int) -> str:
    """Name the fork by what it costs to hold.

    `all_but_one` is the cheapest: learn the one exception and the rest is the
    default. A `two_way` split with a real minority on both sides costs more,
    and `many` costs a peg per position.
    """
    if branch_count < 2:
        return "no_fork"
    if positions - largest == 1 and singletons == 1:
        return "all_but_one"
    if branch_count == 2:
        return "two_way"
    return "many"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row

    if args.rebuild:
        for table in ("fork_members", "fork_branches", "forks"):
            con.execute(f"DROP TABLE IF EXISTS {table}")
    con.executescript(SCHEMA)
    if con.execute("SELECT COUNT(*) FROM forks").fetchone()[0]:
        sys.exit("forks already populated; pass --rebuild")
    if not con.execute("SELECT COUNT(*) FROM official_positions").fetchone()[0]:
        sys.exit("no official positions; run: python -m pipeline.official --rebuild")

    rows = con.execute(
        "SELECT word_id, surah, text_uthmani, text_norm FROM words"
    ).fetchall()
    surah_of = {r["word_id"]: r["surah"] for r in rows}
    display = {r["word_id"]: r["text_uthmani"] for r in rows}
    norm = {r["word_id"]: r["text_norm"] for r in rows}

    by_phrase = defaultdict(list)
    for row in con.execute(
        "SELECT pos_id, phrase_id, surah, start_word_id, end_word_id "
        "FROM official_positions ORDER BY phrase_id, start_word_id"
    ):
        by_phrase[row["phrase_id"]].append(row)

    phrase_text = dict(
        con.execute("SELECT phrase_id, text_ar FROM official_phrases")
    )

    def token_at(position: sqlite3.Row, offset: int) -> int | None:
        """The word `offset` past the phrase, or None at the sūrah's end."""
        word = position["end_word_id"] + offset
        if surah_of.get(word) != position["surah"]:
            return None
        return word

    fork_rows, branch_rows, member_rows = [], [], []
    branch_id = 0
    shapes = defaultdict(int)
    shared_hist = defaultdict(int)

    for phrase_id, positions in sorted(by_phrase.items()):
        if len(positions) < 2:
            continue

        # Walk forward while every position still says the same word. A position
        # that has run out of sūrah says None, which agrees with nothing.
        shared = 0
        while shared < MAX_SHARED:
            words = [token_at(p, shared + 1) for p in positions]
            keys = {norm[w] if w is not None else None for w in words}
            if len(keys) > 1:
                break
            if None in keys:
                break
            shared += 1

        grouped: dict[str | None, list[sqlite3.Row]] = defaultdict(list)
        for position in positions:
            word = token_at(position, shared + 1)
            grouped[norm[word] if word is not None else None].append(position)

        ordered = sorted(grouped.items(), key=lambda kv: (-len(kv[1]), kv[1][0]["pos_id"]))
        largest = len(ordered[0][1])
        singletons = sum(1 for _, members in ordered if len(members) == 1)
        shape = shape_of(len(ordered), len(positions), largest, singletons)

        road_tail = [
            token_at(positions[0], offset) for offset in range(1, shared + 1)
        ]
        road = " ".join(
            [phrase_text[phrase_id]] + [display[w] for w in road_tail if w is not None]
        )

        fork_rows.append(
            (
                phrase_id,
                shared,
                road,
                len(ordered),
                len(positions),
                largest,
                singletons,
                len({p["surah"] for p in positions}),
                shape,
            )
        )
        shapes[shape] += 1
        shared_hist[shared] += 1

        for ordinal, (key, members) in enumerate(ordered, 1):
            branch_id += 1
            word = token_at(members[0], shared + 1)
            branch_rows.append(
                (
                    branch_id,
                    phrase_id,
                    ordinal,
                    display[word] if word is not None else None,
                    key,
                    1 if word is None else 0,
                    len(members),
                    1 if len(members) == largest and ordinal == 1 else 0,
                )
            )
            member_rows.extend((branch_id, m["pos_id"]) for m in members)

    con.executemany("INSERT INTO forks VALUES (?,?,?,?,?,?,?,?,?)", fork_rows)
    con.executemany("INSERT INTO fork_branches VALUES (?,?,?,?,?,?,?,?)", branch_rows)
    con.executemany("INSERT INTO fork_members VALUES (?,?)", member_rows)
    con.commit()

    print(f"phrases: {len(fork_rows):,}   branches: {len(branch_rows):,}")
    for shape, n in sorted(shapes.items(), key=lambda kv: -kv[1]):
        print(f"  {shape:<12} {n:>4}  ({n / len(fork_rows):.1%})")
    print(
        "  words shared past the phrase before it forks: "
        + ", ".join(f"{k}: {v}" for k, v in sorted(shared_hist.items()))
    )
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
