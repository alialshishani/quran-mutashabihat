"""Tests for the quiz.

The question mechanics (filters, distractors, answer index) do not depend on
what the muṣḥaf says, so these run against a small synthetic corpus and need no
built database. Placeholder words stand in for text; none of it is Qur'anic.
"""
from __future__ import annotations

import random
import sqlite3
from http import HTTPStatus

import pytest

from app import quiz as Q
from app.server import PAGE_QUIZ, BadRequest, build_response

SURAHS = {s: (8 if s < 10 else 3) for s in range(1, 21)}


@pytest.fixture()
def con():
    c = sqlite3.connect(":memory:")
    c.row_factory = sqlite3.Row
    c.executescript(
        """
        CREATE TABLE surahs (surah INTEGER PRIMARY KEY, name_ar TEXT);
        CREATE TABLE ayahs (verse_key TEXT, surah INTEGER, ayah INTEGER,
                            juz INTEGER, page_start INTEGER);
        CREATE TABLE words (surah INTEGER, ayah INTEGER, word_pos INTEGER, text_uthmani TEXT);
        CREATE TABLE official_phrases (phrase_id INTEGER PRIMARY KEY, text_ar TEXT);
        CREATE TABLE official_positions (phrase_id INTEGER, surah INTEGER, ayah INTEGER);
        CREATE TABLE pegs (peg_id INTEGER);
        """
    )
    for s, n in SURAHS.items():
        c.execute("INSERT INTO surahs VALUES (?, ?)", (s, f"name{s}"))
        for a in range(1, n + 1):
            c.execute("INSERT INTO ayahs VALUES (?, ?, ?, ?, ?)", (f"{s}:{a}", s, a, 1 + s // 3, s))
            for w in range(1, 9):
                c.execute("INSERT INTO words VALUES (?, ?, ?, ?)", (s, a, w, f"w{s}_{a}_{w}"))
    c.execute("INSERT INTO official_phrases VALUES (1, 'shared')")
    c.executemany(
        "INSERT INTO official_positions VALUES (1, ?, ?)", [(2, 3), (5, 1), (12, 2)]
    )
    c.execute("INSERT INTO pegs VALUES (1)")
    yield c
    c.close()


def _check(q: dict) -> None:
    assert len(q["choices"]) == Q.CHOICES
    assert len({c["value"] for c in q["choices"]}) == Q.CHOICES
    assert 0 <= q["answer"] < Q.CHOICES


@pytest.mark.parametrize("seed", range(20))
def test_surah_question_answers_its_own_ayah(con, seed):
    q = Q.question(con, "surah", rng=random.Random(seed))
    _check(q)
    assert q["choices"][q["answer"]]["value"] == q["ref"]["surah"]
    assert q["text"].startswith(f"w{q['ref']['surah']}_{q['ref']['ayah']}_1 ")


@pytest.mark.parametrize("seed", range(20))
def test_filters_bound_the_ayah_asked(con, seed):
    q = Q.question(con, "surah", from_surah=4, to_surah=6, rng=random.Random(seed))
    assert 4 <= q["ref"]["surah"] <= 6
    q = Q.question(con, "juz", juz=3, rng=random.Random(seed))
    assert q["ref"]["juz"] == 3
    assert q["choices"][q["answer"]]["value"] == 3


@pytest.mark.parametrize("seed", range(20))
def test_next_answer_is_the_following_ayah(con, seed):
    q = Q.question(con, "next", rng=random.Random(seed))
    _check(q)
    s, a = q["ref"]["surah"], q["ref"]["ayah"]
    assert q["choices"][q["answer"]]["value"] == f"{s}:{a + 1}"
    assert SURAHS[s] > a  # never the last āyah of a sūrah


@pytest.mark.parametrize("seed", range(20))
def test_similar_offers_the_phrase_sibling_surahs(con, seed):
    q = Q.question(con, "similar", rng=random.Random(seed))
    _check(q)
    assert q["ref"]["surah"] in {2, 5, 12}
    values = {c["value"] for c in q["choices"]}
    assert {2, 5, 12} <= values
    assert q["phrase"] == "shared"


def test_empty_filters_raise(con):
    with pytest.raises(Q.NoQuestion):
        Q.question(con, "surah", juz=30)


def test_routes(con):
    assert build_response(con, "/quiz", {}) == (HTTPStatus.OK, PAGE_QUIZ)
    status, q = build_response(con, "/api/quiz", {"kind": ["next"], "from": ["3"], "to": ["3"]})
    assert status == HTTPStatus.OK and q["ref"]["surah"] == 3
    status, body = build_response(con, "/api/quiz", {"juz": ["30"]})
    assert status == HTTPStatus.NOT_FOUND and "error" in body
    with pytest.raises(BadRequest):
        build_response(con, "/api/quiz", {"kind": ["bogus"]})
