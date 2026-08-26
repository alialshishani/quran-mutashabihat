"""Run the ḍawābiṭ rules over the groups of a scope and persist what verifies.

    python -m pipeline.apply_rules --scope juz30 --rebuild

Groups where no rule fires are marked needs_review = 1 and still carry their
diff — a clean diff with no peg is a legitimate result (brief section 7).
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from collections import Counter
from pathlib import Path

import yaml

from pipeline.rules import Group, Occurrence, evidence_json, load_rules

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"
PARAMS = ROOT / "config" / "params.yaml"


def load_groups(con: sqlite3.Connection, scope: str) -> list[Group]:
    words = {
        wid: (disp, norm, surah, ayah, page)
        for wid, disp, norm, surah, ayah, page in con.execute(
            "SELECT word_id, text_uthmani, text_norm, surah, ayah, page FROM words"
        )
    }
    surah_names = dict(con.execute("SELECT surah, name_ar FROM surahs"))
    juz_of = dict(con.execute("SELECT verse_key, juz FROM ayahs"))

    by_group: dict[int, list[Occurrence]] = {}
    for occ_id, gid, start, end, verse_key, page in con.execute(
        "SELECT o.occ_id, o.group_id, o.start_word_id, o.end_word_id, o.verse_key, o.page "
        "FROM occurrences o JOIN groups g ON g.group_id = o.group_id "
        "WHERE g.scope = ? ORDER BY o.group_id, o.start_word_id",
        (scope,),
    ):
        surah, ayah = (int(x) for x in verse_key.split(":"))
        span = tuple(words[w][0] for w in range(start, end + 1))

        # The slot on each side of the frame. Confined to the same surah: a
        # token on the far side of a surah boundary is not part of the phrase.
        left = words.get(start - 1)
        right = words.get(end + 1)
        if left and left[2] != surah:
            left = None
        if right and right[2] != surah:
            right = None

        by_group.setdefault(gid, []).append(
            Occurrence(
                occ_id=occ_id,
                start_word_id=start,
                end_word_id=end,
                verse_key=verse_key,
                surah=surah,
                ayah=ayah,
                page=page,
                juz=juz_of.get(verse_key),
                surah_name=surah_names[surah],
                span_display=span,
                left_display=left[0] if left else None,
                left_norm=left[1] if left else None,
                right_display=right[0] if right else None,
                right_norm=right[1] if right else None,
            )
        )

    kinds = dict(
        con.execute("SELECT group_id, kind FROM groups WHERE scope = ?", (scope,))
    )
    return [
        Group(group_id=gid, kind=kinds[gid], occurrences=tuple(occs))
        for gid, occs in sorted(by_group.items())
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", default="juz30")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}; run: python -m pipeline.ingest --rebuild")

    with PARAMS.open(encoding="utf-8") as fh:
        params = yaml.safe_load(fh)

    con = sqlite3.connect(DB)
    if args.rebuild:
        con.execute(
            "DELETE FROM dawabit WHERE group_id IN "
            "(SELECT group_id FROM groups WHERE scope = ?)",
            (args.scope,),
        )

    groups = load_groups(con, args.scope)
    if not groups:
        sys.exit(f"no groups for scope {args.scope!r}; run pass_a first")

    rules = load_rules(params)
    next_id = con.execute("SELECT COALESCE(MAX(dabit_id), 0) FROM dawabit").fetchone()[0]

    fired = Counter()
    rows = []
    resolved = set()
    for group in groups:
        for rule in rules:
            if not rule.applies(group):
                continue
            evidence = rule.evidence(group)
            next_id += 1
            rows.append(
                (
                    next_id,
                    group.group_id,
                    rule.code,
                    rule.strength(evidence),
                    evidence_json(evidence),
                    rule.render(evidence),
                    "rule",
                    1,
                )
            )
            fired[rule.code] += 1
            resolved.add(group.group_id)

    con.executemany("INSERT INTO dawabit VALUES (?,?,?,?,?,?,?,?)", rows)
    con.executemany(
        "UPDATE groups SET needs_review = ? WHERE group_id = ?",
        [(0 if g.group_id in resolved else 1, g.group_id) for g in groups],
    )
    con.commit()

    print(f"scope={args.scope} groups={len(groups):,}")
    for rule in rules:
        n = fired[rule.code]
        print(f"  {rule.code:<10} fired on {n:,} group(s)  ({n / len(groups):.1%})")
    tail = len(groups) - len(resolved)
    print(f"  needs_review tail: {tail:,} of {len(groups):,} ({tail / len(groups):.1%})")
    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
