"""M0: build data/quran.db from the vendored QUL resources.

Pure function from data/raw/extracted/ to data/quran.db. Idempotent: --rebuild
drops and recreates every table, and two runs on the same inputs produce
byte-identical output (brief section 11).

Nothing in this file contains Qur'anic text. Every token is copied from the
source database (C1), and every count is computed at runtime (C2).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

from pipeline.normalize import is_ayah_marker, normalize

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data" / "raw" / "extracted"
DB = ROOT / "data" / "quran.db"

# The layout that drives page/line/line_pos. Recorded in `meta` so the choice is
# never implicit.
LAYOUT_FILE = "qul-15-layout-kfgqpc-v1.db"

SOURCES = {
    "uthmani": "qul-56-uthmani-wbw.db",
    "imlaei": "qul-54-imlaei-wbw.db",
    "layout": LAYOUT_FILE,
    "chapters": "qul-70-surah-names.sqlite",
    "verses": "qul-69-ayah-metadata.sqlite",
    "juz": "qul-68-juz.sqlite",
    "hizb": "qul-67-hizb.sqlite",
    "rub": "qul-63-rub.sqlite",
    "root": "qul-76-word-root.db",
    "lemma": "qul-75-word-lemma.db",
    "stem": "qul-77-word-stem.db",
}

SCHEMA = """
CREATE TABLE words (
  word_id      INTEGER PRIMARY KEY,
  src_word_id  INTEGER NOT NULL,
  surah        INTEGER NOT NULL,
  ayah         INTEGER NOT NULL,
  word_pos     INTEGER NOT NULL,
  text_uthmani TEXT NOT NULL,
  text_imlaei  TEXT,
  text_norm    TEXT NOT NULL,
  text_strict  TEXT NOT NULL,
  root         TEXT,
  lemma        TEXT,
  stem         TEXT,
  pos          TEXT,
  features     TEXT,
  page         INTEGER,
  line         INTEGER,
  line_pos     INTEGER
);
CREATE TABLE ayahs (
  verse_key TEXT PRIMARY KEY,
  surah INTEGER, ayah INTEGER,
  first_word_id INTEGER, last_word_id INTEGER,
  page_start INTEGER, page_end INTEGER,
  juz INTEGER, hizb INTEGER, rub INTEGER
);
CREATE TABLE surahs (
  surah INTEGER PRIMARY KEY, name_ar TEXT, name_norm TEXT,
  ayah_count INTEGER, revelation_place TEXT, revelation_order INTEGER,
  first_page INTEGER, last_page INTEGER
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
CREATE INDEX idx_words_ayah ON words(surah, ayah, word_pos);
CREATE INDEX idx_words_norm ON words(text_norm);
CREATE INDEX idx_words_page ON words(page, line, line_pos);
"""

WORD_COLUMNS = 17


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def open_src(name: str) -> sqlite3.Connection:
    path = SRC / SOURCES[name]
    if not path.exists():
        sys.exit(f"missing source: {path}\nrun: python -m scripts.extract")
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def parse_mapping(raw: str) -> list[tuple[int, int, int]]:
    """Turn a verse_mapping blob into (surah, first_ayah, last_ayah) triples."""
    spans = []
    for surah, span in json.loads(raw).items():
        lo, _, hi = span.partition("-")
        spans.append((int(surah), int(lo), int(hi or lo)))
    return spans


def division_map(conn: sqlite3.Connection, table: str, col: str) -> dict[str, int]:
    """verse_key -> juz/hizb/rub number, expanded from the mapping blobs."""
    out: dict[str, int] = {}
    for number, raw in conn.execute(f"SELECT {col}, verse_mapping FROM {table}"):
        for surah, lo, hi in parse_mapping(raw):
            for ayah in range(lo, hi + 1):
                out[f"{surah}:{ayah}"] = number
    return out


def load_layout() -> dict[int, tuple[int, int, int]]:
    """src_word_id -> (page, line, line_pos).

    line_pos counts every token printed on the line, ayah markers included, so
    the value matches the printed page even though markers get no words row.
    """
    layout = open_src("layout")
    pos: dict[int, tuple[int, int, int]] = {}
    for page, line, first, last in layout.execute(
        "SELECT page_number, line_number, first_word_id, last_word_id "
        "FROM pages WHERE line_type='ayah' AND first_word_id != '' "
        "ORDER BY page_number, line_number"
    ):
        for offset, wid in enumerate(range(int(first), int(last) + 1), start=1):
            pos[wid] = (page, line, offset)
    layout.close()
    return pos


def load_morphology() -> dict[str, dict[str, str]]:
    """word_location -> {root, lemma, stem}, joined to their text tables."""
    morph: dict[str, dict[str, str]] = {}
    for kind, link_table, text_table, text_col in (
        ("root", "root_words", "roots", "arabic_trilateral"),
        ("lemma", "lemma_words", "lemmas", "text"),
        ("stem", "stem_words", "stems", "text"),
    ):
        conn = open_src(kind)
        for loc, text in conn.execute(
            f"SELECT w.word_location, j.{text_col} FROM {link_table} w "
            f"JOIN {text_table} j ON j.id = w.{kind}_id"
        ):
            morph.setdefault(loc, {})[kind] = text
        conn.close()
    return morph


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true", help="drop and recreate")
    args = parser.parse_args()

    if DB.exists():
        if not args.rebuild:
            sys.exit(f"{DB} exists; pass --rebuild to recreate")
        DB.unlink()

    log: list[str] = []
    DB.parent.mkdir(parents=True, exist_ok=True)
    out = sqlite3.connect(DB)
    out.executescript(SCHEMA)

    uthmani = open_src("uthmani")
    imlaei = open_src("imlaei")
    imlaei_by_loc = dict(imlaei.execute("SELECT location, text FROM words"))
    pos_of = load_layout()
    morph = load_morphology()

    rows = []
    word_id = 0
    markers = 0
    for src_id, loc, surah, ayah, word_pos, text in uthmani.execute(
        "SELECT id, location, surah, ayah, word, text FROM words ORDER BY id"
    ):
        if is_ayah_marker(text):
            markers += 1
            continue
        word_id += 1
        page, line, line_pos = pos_of.get(src_id, (None, None, None))
        entry = morph.get(loc, {})
        rows.append(
            (
                word_id,
                src_id,
                surah,
                ayah,
                word_pos,
                text,
                imlaei_by_loc.get(loc),
                normalize(text, "standard"),
                normalize(text, "strict"),
                entry.get("root"),
                entry.get("lemma"),
                entry.get("stem"),
                None,  # pos: pending QAC reconciliation
                None,  # features: pending QAC reconciliation
                page,
                line,
                line_pos,
            )
        )

    placeholders = ",".join("?" * WORD_COLUMNS)
    out.executemany(f"INSERT INTO words VALUES ({placeholders})", rows)
    log.append(f"words: {len(rows):,} (skipped {markers:,} ayah-number markers)")

    valid_locs = {f"{r[2]}:{r[3]}:{r[4]}" for r in rows}
    orphans = sorted(set(morph) - valid_locs)
    if orphans:
        log.append(f"morphology locations with no matching word: {len(orphans)} {orphans}")

    chapters = open_src("chapters")
    surah_rows = []
    for sid, name_ar, place, order, count in chapters.execute(
        "SELECT id, name_arabic, revelation_place, revelation_order, verses_count "
        "FROM chapters ORDER BY id"
    ):
        first_page, last_page = out.execute(
            "SELECT MIN(page), MAX(page) FROM words WHERE surah=?", (sid,)
        ).fetchone()
        surah_rows.append(
            (
                sid,
                name_ar,
                normalize(name_ar, "standard"),
                count,
                place,
                order,
                first_page,
                last_page,
            )
        )
    out.executemany("INSERT INTO surahs VALUES (?,?,?,?,?,?,?,?)", surah_rows)
    log.append(f"surahs: {len(surah_rows):,}")

    juz = division_map(open_src("juz"), "juz", "juz_number")
    hizb = division_map(open_src("hizb"), "hizbs", "hizb_number")
    rub = division_map(open_src("rub"), "rub", "rub_number")

    ayah_rows = []
    for surah, ayah, first, last, page_start, page_end in out.execute(
        "SELECT surah, ayah, MIN(word_id), MAX(word_id), MIN(page), MAX(page) "
        "FROM words GROUP BY surah, ayah ORDER BY surah, ayah"
    ):
        key = f"{surah}:{ayah}"
        ayah_rows.append(
            (
                key,
                surah,
                ayah,
                first,
                last,
                page_start,
                page_end,
                juz.get(key),
                hizb.get(key),
                rub.get(key),
            )
        )
    out.executemany("INSERT INTO ayahs VALUES (?,?,?,?,?,?,?,?,?,?)", ayah_rows)
    log.append(f"ayahs: {len(ayah_rows):,}")

    meta = {"layout": LAYOUT_FILE, "norm_profile_for_text_norm": "standard"}
    for name, filename in SOURCES.items():
        meta[f"src.{name}"] = f"{filename} sha256={sha256(SRC / filename)}"
    out.executemany("INSERT INTO meta VALUES (?,?)", sorted(meta.items()))

    out.commit()
    out.execute("VACUUM")
    out.close()

    for line in log:
        print(line)
    print(f"wrote {DB.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
