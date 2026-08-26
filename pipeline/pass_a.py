"""Pass A: every maximal repeated span in the normalized token stream.

Exhaustive, not heuristic — the corpus is small enough that exact methods are
cheap (brief section 5). Idempotent: --rebuild drops and recreates the analysis
tables for the chosen scope.

    python -m pipeline.pass_a --scope juz30 --rebuild
    python -m pipeline.pass_a --scope full  --rebuild
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

import yaml

from pipeline.suffix import maximal_repeats

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
PARAMS = ROOT / "config" / "params.yaml"

ANALYSIS_SCHEMA = """
CREATE TABLE IF NOT EXISTS occurrences (
  occ_id INTEGER PRIMARY KEY,
  group_id INTEGER NOT NULL,
  start_word_id INTEGER NOT NULL,
  end_word_id INTEGER NOT NULL,
  verse_key TEXT,
  page INTEGER,
  line INTEGER
);
CREATE TABLE IF NOT EXISTS groups (
  group_id INTEGER PRIMARY KEY,
  occurrence_count INTEGER,
  span_len_min INTEGER,
  span_len_max INTEGER,
  kind TEXT,
  diff_type TEXT,
  confusability REAL,
  formulaic INTEGER,
  needs_review INTEGER,
  cross_surah INTEGER,
  scope TEXT
);
CREATE TABLE IF NOT EXISTS dawabit (
  dabit_id INTEGER PRIMARY KEY,
  group_id INTEGER NOT NULL,
  rule_code TEXT,
  strength REAL,
  payload TEXT,
  text_ar TEXT,
  generated_by TEXT,
  verified INTEGER
);
CREATE INDEX IF NOT EXISTS idx_occ_group ON occurrences(group_id);
CREATE INDEX IF NOT EXISTS idx_occ_start ON occurrences(start_word_id);
CREATE INDEX IF NOT EXISTS idx_dabit_group ON dawabit(group_id);
"""

def parse_scope(scope: str) -> int | None:
    """'juz7' -> 7, 'full' -> None. Anything else is an error, not a guess."""
    if scope == "full":
        return None
    if scope.startswith("juz"):
        suffix = scope[3:]
        if suffix.isdigit() and 1 <= int(suffix) <= 30:
            return int(suffix)
    raise ValueError(f"unknown scope {scope!r}; expected 'full' or 'juz1'..'juz30'")


def load_params() -> dict:
    with PARAMS.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def load_stream(con: sqlite3.Connection, scope: str) -> list[tuple]:
    """Return the scoped word rows in muṣḥaf order."""
    juz = parse_scope(scope)
    if juz is None:
        return con.execute(
            "SELECT word_id, text_norm, surah, ayah, page, line "
            "FROM words ORDER BY word_id"
        ).fetchall()
    return con.execute(
        "SELECT w.word_id, w.text_norm, w.surah, w.ayah, w.page, w.line "
        "FROM words w JOIN ayahs a ON a.surah = w.surah AND a.ayah = w.ayah "
        "WHERE a.juz = ? ORDER BY w.word_id",
        (juz,),
    ).fetchall()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", default="juz30")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")

    try:
        parse_scope(args.scope)
    except ValueError as exc:
        sys.exit(str(exc))

    params = load_params()["detection"]["pass_a"]
    min_span = params["min_span_tokens"]
    min_occ = params["min_occurrences"]

    con = sqlite3.connect(DB)
    con.executescript(ANALYSIS_SCHEMA)

    if args.rebuild:
        # Scope-local rebuild: leave any other scope's rows alone.
        con.execute(
            "DELETE FROM dawabit WHERE group_id IN "
            "(SELECT group_id FROM groups WHERE scope = ?)",
            (args.scope,),
        )
        con.execute(
            "DELETE FROM occurrences WHERE group_id IN "
            "(SELECT group_id FROM groups WHERE scope = ?)",
            (args.scope,),
        )
        con.execute("DELETE FROM groups WHERE scope = ?", (args.scope,))
    elif con.execute(
        "SELECT COUNT(*) FROM groups WHERE scope = ?", (args.scope,)
    ).fetchone()[0]:
        sys.exit(f"scope {args.scope!r} already populated; pass --rebuild")

    rows = load_stream(con, args.scope)
    print(f"scope={args.scope} tokens_in={len(rows):,}")

    # Intern the normalized forms so the suffix machinery works on integers.
    vocab: dict[str, int] = {}
    stream = []
    for _, norm, *_ in rows:
        stream.append(vocab.setdefault(norm, len(vocab)))
    print(f"distinct normalized forms: {len(vocab):,}")

    repeats = maximal_repeats(stream, min_span, min_occ)
    print(f"maximal repeated spans (len>={min_span}, count>={min_occ}): {len(repeats):,}")

    base_group = con.execute("SELECT COALESCE(MAX(group_id), 0) FROM groups").fetchone()[0]
    base_occ = con.execute("SELECT COALESCE(MAX(occ_id), 0) FROM occurrences").fetchone()[0]

    group_rows = []
    occ_rows = []
    gid = base_group
    oid = base_occ
    cross_surah_groups = 0

    for rep in repeats:
        gid += 1
        # cross_surah asks whether any single span runs across a surah seam —
        # that span is an artefact of the global token stream, not a phrase.
        # Occurrences sitting in different surahs is the normal case and is not
        # what this flag is for.
        cross = 0
        for start in rep.starts:
            oid += 1
            first = rows[start]
            last = rows[start + rep.length - 1]
            if first[2] != last[2]:
                cross = 1
            occ_rows.append(
                (
                    oid,
                    gid,
                    first[0],  # start_word_id
                    last[0],  # end_word_id
                    f"{first[2]}:{first[3]}",
                    first[4],  # page
                    first[5],  # line
                )
            )
        cross_surah_groups += cross
        group_rows.append(
            (
                gid,
                rep.count,
                rep.length,
                rep.length,
                "exact",
                None,  # diff_type: pass A records no diff, section 6 fills it
                None,  # confusability: pass D
                None,  # formulaic: pass D
                None,  # needs_review: set once rules have run
                cross,
                args.scope,
            )
        )

    con.executemany(
        "INSERT INTO groups VALUES (?,?,?,?,?,?,?,?,?,?,?)", group_rows
    )
    con.executemany("INSERT INTO occurrences VALUES (?,?,?,?,?,?,?)", occ_rows)
    con.commit()

    print(f"groups out: {len(group_rows):,}  occurrences out: {len(occ_rows):,}")
    print(f"  groups spanning more than one surah: {cross_surah_groups:,}")
    if group_rows:
        lengths = [g[2] for g in group_rows]
        counts = [g[1] for g in group_rows]
        print(f"  span length: min={min(lengths)} max={max(lengths)}")
        print(f"  occurrences per group: min={min(counts)} max={max(counts)}")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
