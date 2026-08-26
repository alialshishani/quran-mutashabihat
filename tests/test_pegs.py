"""Tests for the official mutashābihāt ingest and the pegs built over it.

Every claim a peg makes is re-derived here from `words` directly, not read back
from the row that made it. A peg that is checked against its own bookkeeping is
not checked at all: the failure mode that matters is a cue that looks unique to
the generator and is not unique in the muṣḥaf.
"""
from __future__ import annotations

import json
import re
from collections import Counter, defaultdict

import pytest

from app import lookup as L

ARABIC_COUNT = re.compile(r"من بين (\d+) مواضع")


@pytest.fixture(scope="module")
def con():
    if not L.DB.exists():
        pytest.skip(f"{L.DB} not built")
    connection = L.connect()
    tables = {
        r[0]
        for r in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
    }
    if not {"official_phrases", "official_positions", "pegs"} <= tables:
        pytest.skip("run: python -m pipeline.official --rebuild && python -m pipeline.pegs --rebuild")
    if not connection.execute("SELECT COUNT(*) FROM pegs").fetchone()[0]:
        pytest.skip("pegs table empty; run python -m pipeline.pegs --rebuild")
    yield connection
    connection.close()


@pytest.fixture(scope="module")
def stream(con):
    rows = con.execute(
        "SELECT word_id, surah, text_uthmani, text_norm FROM words ORDER BY word_id"
    ).fetchall()
    return {
        "surah": {r[0]: r[1] for r in rows},
        "display": {r[0]: r[2] for r in rows},
        "norm": {r[0]: r[3] for r in rows},
    }


@pytest.fixture(scope="module")
def positions_by_phrase(con):
    out = defaultdict(list)
    for row in con.execute(
        "SELECT pos_id, phrase_id, verse_key, surah, start_word_id, end_word_id "
        "FROM official_positions ORDER BY phrase_id, start_word_id"
    ):
        out[row["phrase_id"]].append(row)
    return out


def _run(stream, word_id, count, step, surah):
    ids = []
    for i in range(1, count + 1):
        w = word_id + step * i
        if stream["surah"].get(w) != surah:
            return None
        ids.append(w)
    return list(reversed(ids)) if step < 0 else ids


# -- ingest -------------------------------------------------------------------


def test_every_official_position_maps_onto_real_words(con):
    orphans = con.execute(
        "SELECT COUNT(*) FROM official_positions o "
        "LEFT JOIN words w ON w.word_id = o.start_word_id WHERE w.word_id IS NULL"
    ).fetchone()[0]
    assert orphans == 0


def test_position_span_length_matches_the_phrase(con):
    """Every member of a confusion set spans the same number of words."""
    bad = con.execute(
        "SELECT COUNT(*) FROM official_positions o "
        "JOIN official_phrases f ON f.phrase_id = o.phrase_id "
        "WHERE o.end_word_id - o.start_word_id + 1 <> f.span_len "
        "AND o.in_exact = 1"
    ).fetchone()[0]
    assert bad == 0


def test_confusion_set_contains_the_official_list(con, positions_by_phrase):
    for phrase in con.execute("SELECT * FROM official_phrases"):
        listed = sum(
            1 for p in positions_by_phrase[phrase["phrase_id"]]
            if con.execute(
                "SELECT in_official FROM official_positions WHERE pos_id = ?",
                (p["pos_id"],),
            ).fetchone()[0]
        )
        assert listed == phrase["official_count"]
        assert phrase["set_count"] == len(positions_by_phrase[phrase["phrase_id"]])
        assert phrase["set_count"] >= phrase["official_count"]


def test_exact_link_means_the_same_span(con):
    """`link = 'exact'` must name a pass-A occurrence with identical bounds."""
    for row in con.execute(
        "SELECT start_word_id, end_word_id, group_id FROM official_positions "
        "WHERE link = 'exact' LIMIT 200"
    ):
        found = con.execute(
            "SELECT COUNT(*) FROM occurrences WHERE group_id = ? "
            "AND start_word_id = ? AND end_word_id = ?",
            (row["group_id"], row["start_word_id"], row["end_word_id"]),
        ).fetchone()[0]
        assert found == 1


def test_exact_repeat_positions_really_carry_the_phrase(con, stream):
    """A position folded in by exact matching must match token for token."""
    for row in con.execute(
        "SELECT o.start_word_id, o.end_word_id, f.text_norm FROM official_positions o "
        "JOIN official_phrases f ON f.phrase_id = o.phrase_id "
        "WHERE o.in_exact = 1 ORDER BY o.pos_id LIMIT 400"
    ):
        actual = " ".join(
            stream["norm"][w] for w in range(row["start_word_id"], row["end_word_id"] + 1)
        )
        assert actual == row["text_norm"]


# -- pegs ---------------------------------------------------------------------


def test_every_confusable_position_has_exactly_one_peg(con, positions_by_phrase):
    pegged = Counter(r[0] for r in con.execute("SELECT pos_id FROM pegs"))
    for phrase_id, positions in positions_by_phrase.items():
        expected = 1 if len(positions) > 1 else 0
        for position in positions:
            assert pegged[position["pos_id"]] == expected


def test_cue_before_is_unique_in_the_confusion_set(con, stream, positions_by_phrase):
    """The claim 'وحده من بين N مواضع' recomputed from the word stream."""
    checked = 0
    for peg in con.execute(
        "SELECT p.pos_id, p.phrase_id, p.cue_window, o.start_word_id, o.surah "
        "FROM pegs p JOIN official_positions o ON o.pos_id = p.pos_id "
        "WHERE p.kind = 'CUE_BEFORE'"
    ):
        siblings = positions_by_phrase[peg["phrase_id"]]
        mine = _run(stream, peg["start_word_id"], peg["cue_window"], -1, peg["surah"])
        assert mine is not None
        mine_norm = " ".join(stream["norm"][w] for w in mine)
        matches = 0
        for sibling in siblings:
            run = _run(
                stream, sibling["start_word_id"], peg["cue_window"], -1, sibling["surah"]
            )
            if run and " ".join(stream["norm"][w] for w in run) == mine_norm:
                matches += 1
        assert matches == 1, f"cue for pos {peg['pos_id']} is shared by {matches} positions"
        checked += 1
    assert checked > 0


def test_cue_window_is_minimal(con, stream, positions_by_phrase):
    """A narrower cue would have been offered if it were unique, so it must not be."""
    for peg in con.execute(
        "SELECT p.pos_id, p.phrase_id, p.cue_window, o.start_word_id, o.surah "
        "FROM pegs p JOIN official_positions o ON o.pos_id = p.pos_id "
        "WHERE p.kind = 'CUE_BEFORE' AND p.cue_window > 1 LIMIT 300"
    ):
        siblings = positions_by_phrase[peg["phrase_id"]]
        narrower = peg["cue_window"] - 1
        mine = _run(stream, peg["start_word_id"], narrower, -1, peg["surah"])
        assert mine is not None
        mine_norm = " ".join(stream["norm"][w] for w in mine)
        matches = sum(
            1
            for s in siblings
            if (run := _run(stream, s["start_word_id"], narrower, -1, s["surah"]))
            and " ".join(stream["norm"][w] for w in run) == mine_norm
        )
        assert matches > 1


def test_sole_in_surah_positions_really_are_alone(con, positions_by_phrase):
    for peg in con.execute(
        "SELECT p.phrase_id, o.surah FROM pegs p "
        "JOIN official_positions o ON o.pos_id = p.pos_id "
        "WHERE p.kind = 'SOLE_IN_SURAH'"
    ):
        in_surah = [
            p for p in positions_by_phrase[peg["phrase_id"]] if p["surah"] == peg["surah"]
        ]
        assert len(in_surah) == 1


def test_ordinal_matches_mushaf_order(con, positions_by_phrase):
    for peg in con.execute(
        "SELECT p.evidence, p.phrase_id, o.surah, o.start_word_id FROM pegs p "
        "JOIN official_positions o ON o.pos_id = p.pos_id "
        "WHERE p.kind = 'ORDINAL_IN_SURAH'"
    ):
        evidence = json.loads(peg["evidence"])
        in_surah = sorted(
            p["start_word_id"]
            for p in positions_by_phrase[peg["phrase_id"]]
            if p["surah"] == peg["surah"]
        )
        assert evidence["in_surah"] == len(in_surah)
        assert evidence["ordinal"] == in_surah.index(peg["start_word_id"]) + 1


def test_unique_continuation_is_unique(con, stream, positions_by_phrase):
    for peg in con.execute(
        "SELECT p.phrase_id, p.continuation_window, o.end_word_id, o.surah FROM pegs p "
        "JOIN official_positions o ON o.pos_id = p.pos_id "
        "WHERE p.continuation_unique = 1 LIMIT 500"
    ):
        k = peg["continuation_window"]
        mine = _run(stream, peg["end_word_id"], k, 1, peg["surah"])
        assert mine is not None
        mine_norm = " ".join(stream["norm"][w] for w in mine)
        matches = sum(
            1
            for s in positions_by_phrase[peg["phrase_id"]]
            if (run := _run(stream, s["end_word_id"], k, 1, s["surah"]))
            and " ".join(stream["norm"][w] for w in run) == mine_norm
        )
        assert matches == 1


def test_peg_arabic_is_copied_not_composed(con, stream):
    """C1/C6: every Qur'anic token in a peg comes byte-for-byte from `words`."""
    for peg in con.execute(
        "SELECT p.cue_ar, p.cue_window, p.continuation_ar, p.continuation_window, "
        "       o.start_word_id, o.end_word_id, o.surah FROM pegs p "
        "JOIN official_positions o ON o.pos_id = p.pos_id LIMIT 600"
    ):
        if peg["cue_ar"]:
            ids = _run(stream, peg["start_word_id"], peg["cue_window"], -1, peg["surah"])
            assert peg["cue_ar"] == " ".join(stream["display"][w] for w in ids)
        if peg["continuation_ar"]:
            ids = _run(
                stream, peg["end_word_id"], peg["continuation_window"], 1, peg["surah"]
            )
            assert peg["continuation_ar"] == " ".join(stream["display"][w] for w in ids)


def test_the_count_in_the_sentence_is_the_real_count(con, positions_by_phrase):
    """C2: 'من بين N مواضع' is counted, never asserted."""
    for peg in con.execute("SELECT phrase_id, text_ar FROM pegs"):
        stated = ARABIC_COUNT.search(peg["text_ar"])
        assert stated, peg["text_ar"]
        assert int(stated.group(1)) == len(positions_by_phrase[peg["phrase_id"]])


def test_strength_is_ordered_by_rung(con):
    best = {
        kind: con.execute(
            "SELECT MAX(strength) FROM pegs WHERE kind = ?", (kind,)
        ).fetchone()[0]
        for kind in ("CUE_BEFORE", "SOLE_IN_SURAH", "ORDINAL_IN_SURAH")
    }
    assert best["CUE_BEFORE"] > best["SOLE_IN_SURAH"] > best["ORDINAL_IN_SURAH"]


# -- service ------------------------------------------------------------------


def test_lookup_returns_the_peg_for_the_queried_ayah(con):
    data = L.lookup(con, 2, 153)
    assert data["params"]["official"] is True
    assert data["official"], "2:153 carries an official mutashābih phrase"
    for phrase in data["official"]:
        assert phrase["here"], "the phrase must have a position inside the āyah"
        for here in phrase["here"]:
            assert here["peg"]["text_ar"]
        assert len(phrase["positions"]) == phrase["set_count"]


def test_every_sibling_carries_its_own_peg(con):
    for phrase in L.lookup(con, 2, 153)["official"]:
        for position in phrase["elsewhere"]:
            assert position["peg"] is not None


def test_official_can_be_switched_off(con):
    data = L.lookup(con, 2, 153, official=False)
    assert data["official"] == []
    assert data["params"]["official"] is False
