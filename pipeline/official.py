"""Ingest the official mutashābihāt lists and bind them to the corpus.

Two QUL resources say which phrases are confusable, curated rather than
detected: resource 73 is phrase-centric (a phrase and every āyah carrying it),
resource 74 is pair-centric (an āyah and the āyāt resembling it).

    python -m pipeline.official --rebuild

What this pass produces per phrase is its **confusion set** — the union of

  * the official position list, and
  * every exact repeat of the phrase's own token sequence in the muṣḥaf.

Neither source is the whole set. The official list omits real repeats (36
phrases here list fewer positions than the muṣḥaf actually contains), and exact
matching misses the near-variants that make a phrase confusable in the first
place. A peg verified against half the set is a peg that fails on the half it
never saw, so the union is what `pipeline.pegs` reasons over.

Official positions are also linked to the pass-A group covering them, so a
curated phrase and a detected one are the same object seen twice.
"""
from __future__ import annotations

import argparse
import bisect
import json
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
PARAMS = ROOT / "config" / "params.yaml"
EXTRACTED = ROOT / "data" / "raw" / "extracted"

PHRASES_JSON = EXTRACTED / "qul-73-mutashabihat__phrases.json"
SIMILAR_DB = EXTRACTED / "qul-74-similar-ayah.db"

# How far either side of the listed start to look for the phrase's own tokens.
# A window this small only ever finds the phrase where the list already pointed.
SNAP = 3

SCHEMA = """
CREATE TABLE IF NOT EXISTS official_phrases (
  phrase_id INTEGER PRIMARY KEY,
  source TEXT,
  source_verse_key TEXT,
  source_word_from INTEGER,
  source_word_to INTEGER,
  span_len INTEGER,
  text_ar TEXT,
  text_norm TEXT,
  official_count INTEGER,
  exact_count INTEGER,
  set_count INTEGER,
  surah_count INTEGER
);
CREATE TABLE IF NOT EXISTS official_positions (
  pos_id INTEGER PRIMARY KEY,
  phrase_id INTEGER NOT NULL,
  verse_key TEXT,
  surah INTEGER,
  ayah INTEGER,
  start_word_id INTEGER,
  end_word_id INTEGER,
  listed_end_word_id INTEGER,
  page INTEGER,
  juz INTEGER,
  in_official INTEGER,
  in_exact INTEGER,
  group_id INTEGER,
  link TEXT
);
CREATE TABLE IF NOT EXISTS similar_ayahs (
  verse_key TEXT,
  matched_verse_key TEXT,
  matched_words INTEGER,
  coverage INTEGER,
  score INTEGER,
  ranges TEXT
);
CREATE INDEX IF NOT EXISTS idx_off_pos_phrase ON official_positions(phrase_id);
CREATE INDEX IF NOT EXISTS idx_off_pos_word ON official_positions(start_word_id);
CREATE INDEX IF NOT EXISTS idx_similar_key ON similar_ayahs(verse_key);
"""


class Corpus:
    """The word stream, indexed the three ways this pass needs it."""

    def __init__(self, con: sqlite3.Connection) -> None:
        rows = con.execute(
            "SELECT word_id, surah, ayah, word_pos, text_uthmani, text_norm "
            "FROM words ORDER BY word_id"
        ).fetchall()
        self.norm = {r[0]: r[5] for r in rows}
        self.display = {r[0]: r[4] for r in rows}
        self.surah = {r[0]: r[1] for r in rows}
        self.key = {r[0]: f"{r[1]}:{r[2]}" for r in rows}
        self.at = {(r[1], r[2], r[3]): r[0] for r in rows}
        self.starting: dict[str, list[int]] = defaultdict(list)
        for r in rows:
            self.starting[r[5]].append(r[0])

    def word_id(self, verse_key: str, word_pos: int) -> int | None:
        surah, ayah = (int(x) for x in verse_key.split(":"))
        return self.at.get((surah, ayah, word_pos))

    def exact_repeats(self, tokens: list[str]) -> list[int]:
        """Every word_id at which this normalized token sequence starts.

        Scanning is confined to one sūrah: a sequence that only exists by
        running across a sūrah seam is an artefact of the global stream, the
        same call `pipeline.pass_a` makes when it flags cross_surah spans.
        """
        out = []
        for start in self.starting.get(tokens[0], ()):
            surah = self.surah[start]
            if all(
                self.norm.get(start + i) == tok and self.surah.get(start + i) == surah
                for i, tok in enumerate(tokens[1:], 1)
            ):
                out.append(start)
        return out


def _snap(corpus: Corpus, tokens: list[str], start: int) -> int:
    """Where the phrase's own tokens begin, near where the list marked them.

    The list says which words of an āyah carry the phrase, and for a handful of
    positions it says it a word off: 29:17 marks `دون` for the phrase
    `من دون الله`, so a window of the phrase's length reads `دون الله لا` --
    three words the āyah does contain, in an order it does not. Where the
    phrase's own tokens sit within a word or three of the mark, that is the
    place meant, and the mark is corrected to it.

    A position whose tokens match nowhere nearby is left exactly where the list
    put it. The list gathers near-variants on purpose -- most positions that do
    not match their phrase differ in wording, not in alignment -- and a variant
    is a fact about the corpus, not an error to be snapped away.
    """
    surah = corpus.surah[start]
    for offset in sorted(range(-SNAP, SNAP + 1), key=lambda o: (abs(o), o)):
        first = start + offset
        if all(
            corpus.norm.get(first + i) == tok and corpus.surah.get(first + i) == surah
            for i, tok in enumerate(tokens)
        ):
            return first
    return start


def _load_phrases() -> dict:
    if not PHRASES_JSON.exists():
        sys.exit(
            f"missing {PHRASES_JSON}\n"
            "download resource 73 per docs/DOWNLOAD.md, then: python -m scripts.extract"
        )
    with PHRASES_JSON.open(encoding="utf-8") as fh:
        return json.load(fh)


def _linker(con: sqlite3.Connection):
    """Classify an official span against the pass-A occurrences covering it."""
    occurrences = sorted(
        con.execute(
            "SELECT o.start_word_id, o.end_word_id, o.group_id "
            "FROM occurrences o JOIN groups g ON g.group_id = o.group_id "
            "WHERE g.scope = 'full'"
        ).fetchall()
    )
    starts = [o[0] for o in occurrences]
    widest = max((e - s for s, e, _ in occurrences), default=0)

    def link(first: int, last: int) -> tuple[int | None, str]:
        best: tuple[int, str] | None = None
        rank = {"exact": 0, "contained": 1, "contains": 2, "overlap": 3}
        index = bisect.bisect_left(starts, first - widest)
        for start, end, group_id in occurrences[index:]:
            if start > last:
                break
            if start == first and end == last:
                kind = "exact"
            elif start <= first and last <= end:
                kind = "contained"
            elif first <= start and end <= last:
                kind = "contains"
            elif start <= last and end >= first:
                kind = "overlap"
            else:
                continue
            if best is None or rank[kind] < rank[best[1]]:
                best = (group_id, kind)
            if kind == "exact":
                break
        return best if best else (None, "none")

    return link


def _ingest_similar(con: sqlite3.Connection) -> int:
    if not SIMILAR_DB.exists():
        return 0
    src = sqlite3.connect(f"file:{SIMILAR_DB.as_posix()}?mode=ro", uri=True)
    rows = src.execute(
        "SELECT verse_key, matched_ayah_key, matched_words_count, coverage, score, "
        "       match_words_range FROM similar_ayahs"
    ).fetchall()
    src.close()
    con.executemany("INSERT INTO similar_ayahs VALUES (?,?,?,?,?,?)", rows)
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")
    with PARAMS.open(encoding="utf-8") as fh:
        params = yaml.safe_load(fh)["pegs"]["confusion_set"]

    phrases = _load_phrases()
    con = sqlite3.connect(DB)

    if args.rebuild:
        # Drop rather than DELETE: --rebuild has to be able to carry a schema
        # change, not just replace rows under an older column list.
        for table in ("official_positions", "official_phrases", "similar_ayahs"):
            con.execute(f"DROP TABLE IF EXISTS {table}")
    con.executescript(SCHEMA)
    if con.execute("SELECT COUNT(*) FROM official_phrases").fetchone()[0]:
        sys.exit("official tables already populated; pass --rebuild")

    corpus = Corpus(con)
    link = _linker(con)
    ayah_meta = {
        r[0]: (r[1], r[2])
        for r in con.execute("SELECT verse_key, page_start, juz FROM ayahs")
    }

    phrase_rows, position_rows = [], []
    pos_id = 0
    unmapped_sources = unmapped_positions = clipped = snapped = 0
    enriched = 0  # phrases the muṣḥaf carries in more places than the list says

    for raw_id, phrase in sorted(phrases.items(), key=lambda kv: int(kv[0])):
        phrase_id = int(raw_id)
        source = phrase["source"]
        first = corpus.word_id(source["key"], source["from"])
        last = corpus.word_id(source["key"], source["to"])
        if first is None or last is None:
            unmapped_sources += 1
            continue
        tokens = [corpus.norm[w] for w in range(first, last + 1)]

        official: dict[int, int] = {}  # start_word_id -> end_word_id
        for verse_key, ranges in phrase["ayah"].items():
            for word_from, word_to in {tuple(r) for r in ranges}:
                start = corpus.word_id(verse_key, word_from)
                end = corpus.word_id(verse_key, word_to)
                if start is None or end is None:
                    unmapped_positions += 1
                    continue
                aligned = _snap(corpus, tokens, start)
                if aligned != start:
                    snapped += 1
                # `end` stays as the list gave it: the column records the extent
                # the list marked, and the window below is measured from the
                # start regardless.
                official[aligned] = end

        exact = set()
        if params["include_exact_repeats"]:
            exact = set(corpus.exact_repeats(tokens))
        if exact - set(official):
            enriched += 1

        members: set[int] = set()
        for start in sorted(set(official) | exact):
            # Every member of a confusion set is measured over the same window:
            # the phrase's own length, from the phrase's own start. The official
            # list marks a different extent at different positions (four words at
            # the source, six at one occurrence), and a continuation read from
            # one offset here and another there is not a comparison — it is two
            # unrelated facts presented as a distinction.
            end = start + len(tokens) - 1
            if corpus.surah.get(end) != corpus.surah[start]:
                clipped += 1
                continue
            pos_id += 1
            members.add(start)
            verse_key = corpus.key[start]
            page, juz = ayah_meta.get(verse_key, (None, None))
            group_id, kind = link(start, end)
            position_rows.append(
                (
                    pos_id,
                    phrase_id,
                    verse_key,
                    int(verse_key.split(":")[0]),
                    int(verse_key.split(":")[1]),
                    start,
                    end,
                    official.get(start),
                    page,
                    juz,
                    1 if start in official else 0,
                    1 if start in exact else 0,
                    group_id,
                    kind,
                )
            )

        # Counts describe the rows that were written, not the rows that were
        # considered: a position dropped above is not a position of the phrase.
        phrase_rows.append(
            (
                phrase_id,
                "qul-73",
                source["key"],
                source["from"],
                source["to"],
                len(tokens),
                " ".join(corpus.display[w] for w in range(first, last + 1)),
                " ".join(tokens),
                len(members & set(official)),
                len(members & exact),
                len(members),
                len({corpus.surah[w] for w in members}),
            )
        )

    con.executemany(
        "INSERT INTO official_phrases VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", phrase_rows
    )
    con.executemany(
        "INSERT INTO official_positions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", position_rows
    )
    similar = _ingest_similar(con)
    con.commit()

    print(f"phrases: {len(phrase_rows):,}   positions: {len(position_rows):,}")
    if unmapped_sources or unmapped_positions or clipped:
        print(
            f"  skipped: {unmapped_sources} source span(s), "
            f"{unmapped_positions} position(s) that do not map onto the corpus, "
            f"{clipped} position(s) whose window would run past the sūrah"
        )
    if snapped:
        print(f"  realigned: {snapped} position(s) the list marked a word or so off")
    official_total = sum(p[8] for p in phrase_rows)
    added = len(position_rows) - official_total
    print(f"  official positions: {official_total:,}")
    print(f"  exact repeats folded in: +{added:,} across {enriched:,} phrase(s)")
    links = dict(
        con.execute(
            "SELECT link, COUNT(*) FROM official_positions GROUP BY link ORDER BY 2 DESC"
        )
    )
    print(f"  linked to a pass-A group: {links}")
    print(f"  similar-āyah pairs (resource 74): {similar:,}")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
