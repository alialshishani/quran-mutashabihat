"""Dump the Python's own output, as the oracle the Dart port is checked against.

    python -m mobile.tools.dump_goldens mobile/golden

Canonical form throughout: keys sorted, UTF-8, no insignificant whitespace. The
Dart side emits the same, so the two are compared byte for byte and a difference
in key order cannot hide a difference in content.

Large — roughly 350 MB — and regenerated in a couple of minutes, so it is
gitignored rather than versioned.
"""
from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from app import lookup as L  # noqa: E402


def write(path: pathlib.Path, doc: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        json.dumps(doc, sort_keys=True, ensure_ascii=False,
                   separators=(",", ":")).encode("utf-8")
    )


def pages(con, out: pathlib.Path) -> None:
    total = L.page_count(con)
    for page in range(1, total + 1):
        write(out / f"p{page}.json", L.mushaf_page(con, page))
    print(f"mushaf_page      {total} pages")


def official(con, out: pathlib.Path, names, juz) -> None:
    keys = [r[0] for r in con.execute(
        "SELECT DISTINCT a.verse_key FROM ayahs a JOIN official_positions o "
        "ON o.start_word_id <= a.last_word_id AND o.end_word_id >= a.first_word_id "
        "ORDER BY a.first_word_id")]
    for key in keys:
        s, a = (int(x) for x in key.split(":"))
        write(out / f"{s}_{a}.json",
              L.official_matches(con, s, a, L._Words(con), names, juz))
    (out / "index.json").write_text(json.dumps(keys))
    print(f"official_matches {len(keys)} ayat")


def forks(con, out: pathlib.Path) -> None:
    cases: list[dict] = []
    for shape in (None, *L.SHAPES):
        for sort in L.SORTS:
            cases.append({"shape": shape, "sort": sort, "limit": 10, "offset": 0})
    for offset in (0, 10, 50, 200):
        cases.append({"sort": "useful", "limit": 10, "offset": offset})
    for surah in (2, 4, 7, 26, 114):
        cases.append({"surah": surah, "limit": 10})
    for mp in (2, 3, 5, 10):
        cases.append({"min_positions": mp, "limit": 10})
    for q in ("الله", "قال"):
        cases.append({"q": q, "limit": 10})

    for i, kw in enumerate(cases):
        write(out / f"index_{i}.json", L.fork_index(con, **kw))
    (out / "cases.json").write_text(json.dumps(cases, ensure_ascii=False),
                                    encoding="utf-8")

    ids = [r[0] for r in con.execute("SELECT phrase_id FROM forks ORDER BY phrase_id")]
    for pid in ids:
        write(out / f"detail_{pid}.json", L.fork_detail(con, pid))
    (out / "ids.json").write_text(json.dumps(ids))
    print(f"fork_index       {len(cases)} cases")
    print(f"fork_detail      {len(ids)} forks")


def lookups(con, out: pathlib.Path) -> None:
    # Every 37th āyah: a spread across the muṣḥaf that still includes āyāt with
    # nothing repeated in them, which are the ones an empty-case bug hides in.
    keys = [r[0] for r in con.execute(
        "SELECT verse_key FROM ayahs ORDER BY first_word_id")][::37]
    for key in keys:
        s, a = (int(x) for x in key.split(":"))
        write(out / f"{s}_{a}.json", L.lookup(con, s, a))
    (out / "keys.json").write_text(json.dumps(keys))
    print(f"lookup           {len(keys)} ayat")


def main() -> None:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "mobile" / "golden")
    con = L.connect()
    names = {r["surah"]: r["name_ar"]
             for r in con.execute("SELECT surah, name_ar FROM surahs")}
    juz = {r["verse_key"]: r["juz"]
           for r in con.execute("SELECT verse_key, juz FROM ayahs")}

    pages(con, out / "pages")
    official(con, out / "official", names, juz)
    forks(con, out / "forks")
    lookups(con, out / "lookup")
    print(f"\nwritten to {out}")


if __name__ == "__main__":
    main()
