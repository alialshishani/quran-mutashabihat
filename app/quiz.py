"""Quiz questions drawn from the corpus.

Four kinds, each a multiple-choice question about one āyah:

    surah     which sūrah is this āyah from?
    similar   the same, but the āyah carries an official mutashābih phrase and
              the wrong answers are the sūrahs where that phrase also occurs
    next      which āyah comes next?
    juz       which juz' is this āyah in?

The answer travels with the question: this is a local study tool, not an exam.
As everywhere in `app/`, Qur'anic text is copied byte-for-byte out of `words`.
"""
from __future__ import annotations

import random
import sqlite3

from app import lookup as L

KINDS = ("surah", "similar", "next", "juz")
CHOICES = 4
OPENING_WORDS = 6


class NoQuestion(LookupError):
    """The filters leave nothing to ask about."""


def _ayah_text(con: sqlite3.Connection, surah: int, ayah: int, words: int | None = None) -> str:
    rows = con.execute(
        "SELECT text_uthmani FROM words WHERE surah = ? AND ayah = ? ORDER BY word_pos",
        (surah, ayah),
    ).fetchall()
    if words is not None and len(rows) > words:
        return " ".join(r[0] for r in rows[:words]) + " …"
    return " ".join(r[0] for r in rows)


def _names(con: sqlite3.Connection) -> dict[int, str]:
    return {r[0]: r[1] for r in con.execute("SELECT surah, name_ar FROM surahs")}


def _pick_ayah(
    con: sqlite3.Connection, rng: random.Random, where: str, params: list
) -> sqlite3.Row:
    count = con.execute(f"SELECT COUNT(*) FROM ayahs WHERE {where}", params).fetchone()[0]
    if not count:
        raise NoQuestion("no āyah matches these filters")
    return con.execute(
        f"SELECT surah, ayah, juz, page_start FROM ayahs WHERE {where} "
        "ORDER BY surah, ayah LIMIT 1 OFFSET ?",
        [*params, rng.randrange(count)],
    ).fetchone()


def _surah_distractors(
    rng: random.Random, correct: int, pool: list[int], preferred: list[int] = ()
) -> list[int]:
    """Wrong sūrahs: the preferred ones first, then neighbours, then any."""
    picked: list[int] = []
    for s in [*dict.fromkeys(preferred)]:
        if s != correct and s not in picked:
            picked.append(s)
    rng.shuffle(picked)
    picked = picked[: CHOICES - 1]
    near = [s for s in pool if s != correct and s not in picked and abs(s - correct) <= 3]
    rng.shuffle(near)
    rest = [s for s in pool if s != correct and s not in picked and s not in near]
    rng.shuffle(rest)
    for s in near[:2] + rest + near[2:]:
        if len(picked) >= CHOICES - 1:
            break
        picked.append(s)
    return picked


def _finish(rng: random.Random, question: dict, correct: dict, wrong: list[dict]) -> dict:
    choices = [correct, *wrong]
    rng.shuffle(choices)
    question["choices"] = choices
    question["answer"] = choices.index(correct)
    return question


def _base(con: sqlite3.Connection, kind: str, row: sqlite3.Row, names: dict[int, str]) -> dict:
    return {
        "kind": kind,
        "text": _ayah_text(con, row["surah"], row["ayah"]),
        "ref": {
            "surah": row["surah"],
            "ayah": row["ayah"],
            "name_ar": names.get(row["surah"]),
            "juz": row["juz"],
            "page": row["page_start"],
        },
    }


def _surah_choice(s: int, names: dict[int, str]) -> dict:
    return {"value": s, "label": names.get(s, str(s))}


def question(
    con: sqlite3.Connection,
    kind: str = "surah",
    *,
    from_surah: int = 1,
    to_surah: int = 114,
    juz: int | None = None,
    rng: random.Random | None = None,
) -> dict:
    """One multiple-choice question, with `answer` the index of the right choice."""
    if kind not in KINDS:
        raise ValueError(f"kind must be one of {', '.join(KINDS)}, got {kind!r}")
    rng = rng or random.Random()
    lo, hi = sorted((max(1, from_surah), min(114, to_surah)))
    where, params = "{a}surah BETWEEN ? AND ?", [lo, hi]
    if juz is not None:
        where += " AND {a}juz = ?"
        params.append(juz)
    names = _names(con)
    pool = sorted(names)

    if kind == "similar":
        if not L._has_official(con):
            raise NoQuestion(
                "official mutashābihāt not built; run: python -m pipeline.official "
                "--rebuild and python -m pipeline.pegs --rebuild"
            )
        rows = con.execute(
            f"SELECT DISTINCT p.phrase_id, p.surah, p.ayah FROM official_positions p "
            f"JOIN ayahs a ON a.surah = p.surah AND a.ayah = p.ayah "
            f"WHERE {where.format(a='a.')} "
            "AND (SELECT COUNT(DISTINCT q.surah) FROM official_positions q "
            "     WHERE q.phrase_id = p.phrase_id) > 1",
            params,
        ).fetchall()
        if not rows:
            raise NoQuestion("no official mutashābih āyah matches these filters")
        phrase_id, surah, ayah = rng.choice(rows)
        row = con.execute(
            "SELECT surah, ayah, juz, page_start FROM ayahs WHERE surah = ? AND ayah = ?",
            (surah, ayah),
        ).fetchone()
        others = [
            r[0]
            for r in con.execute(
                "SELECT DISTINCT surah FROM official_positions WHERE phrase_id = ?",
                (phrase_id,),
            )
        ]
        q = _base(con, kind, row, names)
        q["phrase"] = con.execute(
            "SELECT text_ar FROM official_phrases WHERE phrase_id = ?", (phrase_id,)
        ).fetchone()[0]
        wrong = _surah_distractors(rng, surah, pool, others)
        return _finish(rng, q, _surah_choice(surah, names), [_surah_choice(s, names) for s in wrong])

    row = _pick_ayah(con, rng, where.format(a="") + (
        " AND EXISTS (SELECT 1 FROM ayahs n WHERE n.surah = ayahs.surah AND n.ayah = ayahs.ayah + 1)"
        if kind == "next" else ""
    ), params)
    q = _base(con, kind, row, names)

    if kind == "surah":
        wrong = _surah_distractors(rng, row["surah"], pool)
        return _finish(
            rng, q, _surah_choice(row["surah"], names), [_surah_choice(s, names) for s in wrong]
        )

    if kind == "juz":
        near = [j for j in range(max(1, row["juz"] - 2), min(30, row["juz"] + 2) + 1)]
        options = [j for j in near if j != row["juz"]]
        rng.shuffle(options)
        far = [j for j in range(1, 31) if j != row["juz"] and j not in options]
        rng.shuffle(far)
        wrong = (options + far)[: CHOICES - 1]
        label = lambda j: {"value": j, "label": f"Juz' {j}"}  # noqa: E731
        return _finish(rng, q, label(row["juz"]), [label(j) for j in wrong])

    # next: the opening of the following āyah, against openings from the same sūrah.
    surah, ayah = row["surah"], row["ayah"]
    count = con.execute(
        "SELECT COUNT(*) FROM ayahs WHERE surah = ?", (surah,)
    ).fetchone()[0]
    candidates = [a for a in range(1, count + 1) if a not in (ayah, ayah + 1)]
    if len(candidates) < CHOICES - 1:
        # Short sūrah: borrow openings from its neighbours.
        for s in (surah + 1, surah - 1, surah + 2):
            if s in names:
                n = con.execute("SELECT COUNT(*) FROM ayahs WHERE surah = ?", (s,)).fetchone()[0]
                candidates += [(s, a) for a in range(1, n + 1)]
    rng.shuffle(candidates)
    choice = lambda s, a: {  # noqa: E731
        "value": f"{s}:{a}",
        "label": _ayah_text(con, s, a, OPENING_WORDS),
    }
    correct = choice(surah, ayah + 1)
    wrong: list[dict] = []
    for c in candidates:
        s, a = c if isinstance(c, tuple) else (surah, c)
        option = choice(s, a)
        if option["label"] != correct["label"] and option["label"] not in {w["label"] for w in wrong}:
            wrong.append(option)
        if len(wrong) == CHOICES - 1:
            break
    return _finish(rng, q, correct, wrong)
