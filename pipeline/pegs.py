"""Bind every position of an official mutashābih phrase to a peg that identifies it.

    python -m pipeline.pegs --rebuild

A ḍābiṭ of the R1 kind describes a whole group at once ("all the positions take
X except one"). That is the cheapest peg when the distribution allows it, but
most confusable phrases have no majority to lean on: the twenty places carrying
one phrase each need their own handle.

The handle has to be something the reciter already holds at the moment of the
decision. Arriving at a shared phrase, what they have is the words just recited
and the knowledge of which sūrah they are in — not the continuation, which is
the very thing they are trying to choose. So a *unique following word* is not a
peg; it is the answer the peg has to select. The ladder below keys on the cue
and reports the continuation as the payload:

  1. CUE_BEFORE       the shortest run of preceding words carried by this
                      position and by no other in the confusion set
  2. SOLE_IN_SURAH    the phrase occurs once in this sūrah, so the sūrah names it
  3. ORDINAL_IN_SURAH the nth of m inside one sūrah, anchored to its page

Every rung is verified against the confusion set `pipeline.official` built —
official siblings plus exact repeats — before it is emitted. A cue that is
unique among half the positions and shared with the half that was never checked
is precisely the peg that teaches a mistake, so nothing is emitted on a set this
pass has not seen whole (C4).

Arabic is assembled from a fixed template plus tokens copied byte-for-byte out
of the database. No Qur'anic text originates here (C1); no count is asserted
rather than counted (C2); nothing claims why a wording differs (C5).
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
PARAMS = ROOT / "config" / "params.yaml"

SCHEMA = """
CREATE TABLE IF NOT EXISTS pegs (
  peg_id INTEGER PRIMARY KEY,
  phrase_id INTEGER NOT NULL,
  pos_id INTEGER NOT NULL,
  kind TEXT,
  cue_window INTEGER,
  cue_ar TEXT,
  continuation_ar TEXT,
  continuation_window INTEGER,
  continuation_unique INTEGER,
  strength REAL,
  evidence TEXT,
  text_ar TEXT,
  verified INTEGER
);
CREATE INDEX IF NOT EXISTS idx_pegs_pos ON pegs(pos_id);
CREATE INDEX IF NOT EXISTS idx_pegs_phrase ON pegs(phrase_id);
"""

# Fixed connective vocabulary. Template words only — never Qur'anic text, never
# a claim about meaning (C1, C5).
_BEFORE_IT = "ما قبله"
_ALONE_AMONG = "وحده من بين {n} مواضع"
_AFTER_IT = "وما بعده"
_SOLE_IN_SURAH = "الموضع الوحيد في سورة {surah} من بين {n} مواضع"
_ORDINAL_IN_SURAH = "الموضع {ordinal} من {m} في سورة {surah}، من بين {n} مواضع"
_END_OF_SURAH = "وهو في آخر السورة"
_LOCATION = "سورة {surah} — {key}، ص {page}"
_STILL_SHARED = "وما بعده ({tokens}) وهو مشترك مع مواضع أخرى"

_ORDINALS = {
    1: "الأول",
    2: "الثاني",
    3: "الثالث",
    4: "الرابع",
    5: "الخامس",
    6: "السادس",
    7: "السابع",
    8: "الثامن",
    9: "التاسع",
    10: "العاشر",
}


def _ordinal(n: int) -> str:
    """Arabic ordinal, falling back to the numeral rather than inventing a word."""
    return _ORDINALS.get(n, f"رقم {n}")


class Stream:
    """The word stream, read once."""

    def __init__(self, con: sqlite3.Connection) -> None:
        rows = con.execute(
            "SELECT word_id, surah, text_uthmani, text_norm FROM words ORDER BY word_id"
        ).fetchall()
        self.surah = {r[0]: r[1] for r in rows}
        self.display = {r[0]: r[2] for r in rows}
        self.norm = {r[0]: r[3] for r in rows}

    def _run(self, word_id: int, count: int, step: int, surah: int) -> list[int] | None:
        """`count` word ids stepping away from `word_id`, or None at a sūrah edge."""
        out = []
        for i in range(1, count + 1):
            w = word_id + step * i
            if self.surah.get(w) != surah:
                return None
            out.append(w)
        return out

    def before(self, start: int, k: int, surah: int) -> list[int] | None:
        run = self._run(start, k, -1, surah)
        return list(reversed(run)) if run else None

    def after(self, end: int, k: int, surah: int) -> list[int] | None:
        return self._run(end, k, 1, surah)

    def norm_text(self, ids: list[int]) -> str:
        return " ".join(self.norm[w] for w in ids)

    def display_text(self, ids: list[int]) -> str:
        return " ".join(self.display[w] for w in ids)


def _continuation(stream: Stream, positions: list[sqlite3.Row], max_window: int) -> dict:
    """Per position: the shortest continuation that no sibling shares.

    Where nothing within the window is unique, the widest continuation is still
    reported — with `unique` false, so the page can say the difference lies
    further on rather than implying a distinction that was not found.
    """
    out: dict[int, dict] = {}
    for k in range(1, max_window + 1):
        runs = {
            p["pos_id"]: stream.after(p["end_word_id"], k, p["surah"]) for p in positions
        }
        counts = Counter(
            stream.norm_text(run) for run in runs.values() if run is not None
        )
        for p in positions:
            run = runs[p["pos_id"]]
            if p["pos_id"] in out or run is None:
                continue
            if counts[stream.norm_text(run)] == 1:
                out[p["pos_id"]] = {
                    "text": stream.display_text(run),
                    "window": k,
                    "unique": True,
                }
    for p in positions:
        if p["pos_id"] in out:
            continue
        widest = None
        for k in range(max_window, 0, -1):
            widest = stream.after(p["end_word_id"], k, p["surah"])
            if widest:
                break
        out[p["pos_id"]] = (
            {"text": stream.display_text(widest), "window": len(widest), "unique": False}
            if widest
            else {"text": None, "window": 0, "unique": False}
        )
    return out


def _cues(stream: Stream, positions: list[sqlite3.Row], max_window: int) -> dict:
    """Per position: the shortest preceding run no sibling carries."""
    out: dict[int, dict] = {}
    for k in range(1, max_window + 1):
        runs = {
            p["pos_id"]: stream.before(p["start_word_id"], k, p["surah"])
            for p in positions
        }
        counts = Counter(
            stream.norm_text(run) for run in runs.values() if run is not None
        )
        for p in positions:
            run = runs[p["pos_id"]]
            if p["pos_id"] in out or run is None:
                continue
            if counts[stream.norm_text(run)] == 1:
                out[p["pos_id"]] = {
                    "text": stream.display_text(run),
                    "norm": stream.norm_text(run),
                    "window": k,
                }
    return out


def _render(kind: str, ev: dict) -> str:
    """The peg as one Arabic sentence. Every value here was counted or copied."""
    total = ev["set_count"]
    if kind == "CUE_BEFORE":
        head = f"{_BEFORE_IT} ({ev['cue']}) " + _ALONE_AMONG.format(n=total)
    elif kind == "SOLE_IN_SURAH":
        head = _SOLE_IN_SURAH.format(surah=ev["surah_name"], n=total)
    else:
        head = _ORDINAL_IN_SURAH.format(
            ordinal=_ordinal(ev["ordinal"]),
            m=ev["in_surah"],
            surah=ev["surah_name"],
            n=total,
        )

    if ev["continuation"] is None:
        tail = _END_OF_SURAH
    elif ev["continuation_unique"]:
        tail = f"{_AFTER_IT} ({ev['continuation']})"
    else:
        tail = _STILL_SHARED.format(tokens=ev["continuation"])

    where = _LOCATION.format(
        surah=ev["surah_name"], key=ev["verse_key"], page=ev["page"]
    )
    return f"{head}، {tail}. {where}."


def _strength(kind: str, ev: dict, weights: dict) -> float:
    if kind == "CUE_BEFORE":
        base = weights["cue_before"] - weights["per_extra_cue_word"] * (
            ev["cue_window"] - 1
        )
    elif kind == "SOLE_IN_SURAH":
        base = weights["sole_in_surah"]
    else:
        base = weights["ordinal_in_surah"]
    if not ev["continuation_unique"]:
        base *= weights["ambiguous_payload"]
    return round(max(base, 0.0), 4)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")
    with PARAMS.open(encoding="utf-8") as fh:
        params = yaml.safe_load(fh)["pegs"]
    max_window = params["cue"]["max_window"]
    weights = params["strength"]

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    con.executescript(SCHEMA)

    if not con.execute("SELECT COUNT(*) FROM official_phrases").fetchone()[0]:
        sys.exit("no official phrases; run: python -m pipeline.official --rebuild")
    if con.execute("SELECT COUNT(*) FROM pegs").fetchone()[0] and not args.rebuild:
        sys.exit("pegs already populated; pass --rebuild")
    if args.rebuild:
        con.execute("DELETE FROM pegs")

    stream = Stream(con)
    surah_names = dict(con.execute("SELECT surah, name_ar FROM surahs"))
    by_phrase: dict[int, list[sqlite3.Row]] = defaultdict(list)
    for row in con.execute(
        "SELECT pos_id, phrase_id, verse_key, surah, ayah, start_word_id, "
        "       end_word_id, page, juz FROM official_positions "
        "ORDER BY phrase_id, start_word_id"
    ):
        by_phrase[row["phrase_id"]].append(row)

    rows = []
    peg_id = 0
    fired = Counter()
    windows = Counter()
    singletons = 0

    for phrase_id, positions in sorted(by_phrase.items()):
        if len(positions) < 2:
            # One position is not a confusion; there is nothing to tell apart.
            singletons += 1
            continue

        cues = _cues(stream, positions, max_window)
        continuations = _continuation(stream, positions, max_window)
        per_surah = defaultdict(list)
        for p in positions:
            per_surah[p["surah"]].append(p)

        for p in positions:
            cont = continuations[p["pos_id"]]
            evidence = {
                "verse_key": p["verse_key"],
                "surah_name": surah_names[p["surah"]],
                "page": p["page"],
                "juz": p["juz"],
                "set_count": len(positions),
                "continuation": cont["text"],
                "continuation_window": cont["window"],
                "continuation_unique": cont["unique"],
            }

            cue = cues.get(p["pos_id"])
            if cue:
                kind = "CUE_BEFORE"
                evidence |= {"cue": cue["text"], "cue_norm": cue["norm"], "cue_window": cue["window"]}
            else:
                siblings = per_surah[p["surah"]]
                evidence |= {"cue": None, "cue_window": 0, "in_surah": len(siblings)}
                if len(siblings) == 1:
                    kind = "SOLE_IN_SURAH"
                else:
                    kind = "ORDINAL_IN_SURAH"
                    evidence["ordinal"] = (
                        sorted(s["start_word_id"] for s in siblings).index(
                            p["start_word_id"]
                        )
                        + 1
                    )

            peg_id += 1
            rows.append(
                (
                    peg_id,
                    phrase_id,
                    p["pos_id"],
                    kind,
                    evidence["cue_window"],
                    evidence["cue"],
                    cont["text"],
                    cont["window"],
                    1 if cont["unique"] else 0,
                    _strength(kind, evidence, weights),
                    json.dumps(evidence, ensure_ascii=False, sort_keys=True),
                    _render(kind, evidence),
                    1,
                )
            )
            fired[kind] += 1
            if kind == "CUE_BEFORE":
                windows[cue["window"]] += 1

    con.executemany("INSERT INTO pegs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    con.commit()

    total = sum(fired.values())
    print(f"phrases with a confusion set: {len(by_phrase) - singletons:,}")
    print(f"positions pegged: {total:,}")
    for kind, n in fired.most_common():
        print(f"  {kind:<18} {n:>6,}  ({n / total:.1%})")
    print(
        "  cue width: "
        + ", ".join(f"{k} word(s): {n:,}" for k, n in sorted(windows.items()))
    )
    ambiguous = sum(1 for r in rows if r[8] == 0)
    print(f"  continuation still shared at {max_window} words: {ambiguous:,}")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
