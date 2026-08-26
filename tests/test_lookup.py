"""Tests for the āyah lookup service.

They run against the real corpus: the claims worth testing here are claims about
the muṣḥaf, and a fixture would only test the fixture.
"""
from __future__ import annotations

import json
from http import HTTPStatus

import pytest

from app import lookup as L
from app.server import BadRequest, build_response


@pytest.fixture(scope="module")
def con():
    if not L.DB.exists():
        pytest.skip(f"{L.DB} not built")
    connection = L.connect()
    populated = connection.execute(
        "SELECT COUNT(*) FROM groups WHERE scope = 'full'"
    ).fetchone()[0]
    if not populated:
        pytest.skip("scope 'full' not populated; run pipeline.pass_a --scope full")
    yield connection
    connection.close()


def test_unknown_ayah_is_an_error(con):
    with pytest.raises(L.AyahNotFound):
        L.lookup(con, 2, 999)


def test_query_ayah_text_matches_the_word_table(con):
    data = L.lookup(con, 2, 25)
    words = con.execute(
        "SELECT text_uthmani FROM words WHERE surah = 2 AND ayah = 25 ORDER BY word_pos"
    ).fetchall()
    assert data["query"]["text"] == " ".join(w[0] for w in words)
    assert len(data["query"]["words"]) == len(words)


def test_every_match_includes_the_queried_ayah(con):
    """`here` is a real position of the group and overlaps the āyah asked for."""
    first, last = con.execute(
        "SELECT first_word_id, last_word_id FROM ayahs WHERE verse_key = '2:25'"
    ).fetchone()
    for match in L.lookup(con, 2, 25, limit=None)["matches"]:
        here = match["here"]
        assert here["is_query"] is True
        assert here["start_word_id"] <= last and here["end_word_id"] >= first
        assert sum(1 for p in match["positions"] if p["is_query"]) == 1


def test_occurrence_count_agrees_with_the_positions_returned(con):
    """C2: the number shown is the number of rows, never an asserted total."""
    for match in L.lookup(con, 2, 25, limit=None)["matches"]:
        assert match["occurrence_count"] == len(match["positions"])
        assert len(match["elsewhere"]) == match["occurrence_count"] - 1


def test_span_text_is_identical_at_every_position(con):
    """Pass A groups are exact repeats, so every position carries the same span."""
    for match in L.lookup(con, 55, 13, limit=None)["matches"]:
        assert {p["span_text"] for p in match["positions"]} == {match["span_text"]}


def test_dabit_groups_are_ranked_first(con):
    matches = L.lookup(con, 2, 25, limit=None)["matches"]
    ranked = [bool(m["dawabit"]) for m in matches]
    assert ranked == sorted(ranked, reverse=True)


def test_dabit_text_comes_from_the_database(con):
    """C1/C6: the service renders no Arabic of its own."""
    for match in L.lookup(con, 2, 25, limit=None)["matches"]:
        for dabit in match["dawabit"]:
            stored = con.execute(
                "SELECT text_ar FROM dawabit WHERE group_id = ? AND rule_code = ?",
                (match["group_id"], dabit["rule_code"]),
            ).fetchone()
            assert dabit["text_ar"] == stored["text_ar"]


def test_limit_caps_the_list_without_changing_the_summary(con):
    full = L.lookup(con, 2, 25, limit=None)
    capped = L.lookup(con, 2, 25, limit=2)
    assert capped["counts"]["matches"] == full["counts"]["matches"]
    assert capped["counts"]["other_positions"] == full["counts"]["other_positions"]
    assert capped["counts"]["returned"] == len(capped["matches"]) == 2


def test_min_len_and_min_occurrences_filter(con):
    data = L.lookup(con, 2, 25, min_len=5, min_occurrences=10, limit=None)
    for match in data["matches"]:
        assert match["span_len"] >= 5
        assert match["occurrence_count"] >= 10


def test_collapse_only_removes_redundant_spans(con):
    """Collapsing must not drop any position from view."""
    kept = L.lookup(con, 2, 25, limit=None, collapse=True)
    raw = L.lookup(con, 2, 25, limit=None, collapse=False)
    kept_keys = {p["verse_key"] for m in kept["matches"] for p in m["positions"]}
    raw_keys = {p["verse_key"] for m in raw["matches"] for p in m["positions"]}
    assert kept_keys == raw_keys


def test_neighbour_tokens_stay_inside_the_surah(con):
    """A token across a sūrah seam is not part of the phrase."""
    for match in L.lookup(con, 114, 6, limit=None)["matches"]:
        for pos in match["positions"]:
            for token, word_id in (
                (pos["before"], pos["start_word_id"] - 1),
                (pos["after"], pos["end_word_id"] + 1),
            ):
                if token is None:
                    continue
                row = con.execute(
                    "SELECT surah, text_uthmani FROM words WHERE word_id = ?", (word_id,)
                ).fetchone()
                assert row["surah"] == pos["surah"]
                assert row["text_uthmani"] == token


def test_first_and_last_ayah_of_the_mushaf_resolve(con):
    for surah, ayah in ((1, 1), (114, 6)):
        data = L.lookup(con, surah, ayah)
        assert data["query"]["verse_key"] == f"{surah}:{ayah}"


# -- routing ------------------------------------------------------------------


def test_route_path_and_query_forms_agree(con):
    _, by_path = build_response(con, "/api/mutashabih/2/25", {})
    _, by_query = build_response(con, "/api/mutashabih", {"surah": ["2"], "ayah": ["25"]})
    assert by_path["counts"] == by_query["counts"]


def test_route_requires_both_parameters(con):
    with pytest.raises(BadRequest):
        build_response(con, "/api/mutashabih", {"surah": ["2"]})


def test_route_rejects_a_non_numeric_ayah(con):
    with pytest.raises(BadRequest):
        build_response(con, "/api/mutashabih", {"surah": ["2"], "ayah": ["x"]})


def test_unknown_route_is_404(con):
    status, payload = build_response(con, "/api/nope", {})
    assert status == HTTPStatus.NOT_FOUND
    assert "error" in payload


def test_page_route_returns_no_payload(con):
    status, payload = build_response(con, "/", {})
    assert status == HTTPStatus.OK and payload is None


def test_surah_list_covers_the_mushaf(con):
    _, payload = build_response(con, "/api/surahs", {})
    assert len(payload) == 114
    assert sum(s["ayah_count"] for s in payload) == 6236


def test_response_is_json_serialisable(con):
    _, payload = build_response(con, "/api/mutashabih/2/25", {})
    json.dumps(payload, ensure_ascii=False)
