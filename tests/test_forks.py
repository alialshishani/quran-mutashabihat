"""Tests for the fork shaping and the official-only page's API.

The fork is re-derived from `words` here rather than read back from the tables
that made it: the claim that matters is that the road really is shared and that
the branch really is where the positions part.
"""
from __future__ import annotations

from collections import defaultdict
from http import HTTPStatus

import pytest

from app import lookup as L
from app.server import BadRequest, PAGE_FORKS, build_response


@pytest.fixture(scope="module")
def con():
    if not L.DB.exists():
        pytest.skip(f"{L.DB} not built")
    connection = L.connect()
    if not L.has_forks(connection):
        pytest.skip("run: python -m pipeline.forks --rebuild")
    yield connection
    connection.close()


@pytest.fixture(scope="module")
def stream(con):
    rows = con.execute("SELECT word_id, surah, text_norm FROM words").fetchall()
    return (
        {r["word_id"]: r["surah"] for r in rows},
        {r["word_id"]: r["text_norm"] for r in rows},
    )


@pytest.fixture(scope="module")
def members(con):
    out = defaultdict(list)
    for row in con.execute(
        "SELECT b.phrase_id, b.branch_id, o.pos_id, o.surah, o.end_word_id "
        "FROM fork_branches b JOIN fork_members m ON m.branch_id = b.branch_id "
        "JOIN official_positions o ON o.pos_id = m.pos_id"
    ):
        out[row["phrase_id"]].append(row)
    return out


def _word(stream, position, offset):
    surah_of, _ = stream
    word = position["end_word_id"] + offset
    return word if surah_of.get(word) == position["surah"] else None


# -- the shape ----------------------------------------------------------------


def test_the_road_is_actually_shared(con, stream, members):
    """Every word counted as shared must be the same word at every position."""
    _, norm = stream
    for fork in con.execute("SELECT phrase_id, shared_after FROM forks"):
        positions = members[fork["phrase_id"]]
        for offset in range(1, fork["shared_after"] + 1):
            tokens = {
                norm[w] if (w := _word(stream, p, offset)) else None for p in positions
            }
            assert len(tokens) == 1 and None not in tokens, (
                f"phrase {fork['phrase_id']} claims {fork['shared_after']} shared words "
                f"but they differ at word {offset}"
            )


def test_the_fork_is_where_they_stop_agreeing(con, stream, members):
    """One word past the shared run, the positions must not all agree."""
    _, norm = stream
    for fork in con.execute(
        "SELECT phrase_id, shared_after, branch_count FROM forks WHERE branch_count > 1"
    ):
        positions = members[fork["phrase_id"]]
        offset = fork["shared_after"] + 1
        tokens = {
            norm[w] if (w := _word(stream, p, offset)) else None for p in positions
        }
        assert len(tokens) > 1


def test_branch_token_matches_its_members(con, stream, members):
    _, norm = stream
    by_branch = defaultdict(list)
    for phrase_positions in members.values():
        for row in phrase_positions:
            by_branch[row["branch_id"]].append(row)
    for branch in con.execute(
        "SELECT b.branch_id, b.token_norm, b.ends_surah, b.position_count, f.shared_after "
        "FROM fork_branches b JOIN forks f ON f.phrase_id = b.phrase_id"
    ):
        rows = by_branch[branch["branch_id"]]
        assert len(rows) == branch["position_count"]
        for row in rows:
            word = _word(stream, row, branch["shared_after"] + 1)
            if branch["ends_surah"]:
                assert word is None
            else:
                assert norm[word] == branch["token_norm"]


def test_every_position_is_on_exactly_one_branch(con):
    doubled = con.execute(
        "SELECT COUNT(*) FROM (SELECT pos_id FROM fork_members "
        "GROUP BY pos_id HAVING COUNT(*) > 1)"
    ).fetchone()[0]
    assert doubled == 0

    orphans = con.execute(
        "SELECT COUNT(*) FROM official_positions o "
        "JOIN forks f ON f.phrase_id = o.phrase_id "
        "LEFT JOIN fork_members m ON m.pos_id = o.pos_id WHERE m.pos_id IS NULL"
    ).fetchone()[0]
    assert orphans == 0


def test_branch_counts_sum_to_the_position_count(con):
    for fork in con.execute("SELECT phrase_id, position_count, branch_count FROM forks"):
        total, branches = con.execute(
            "SELECT SUM(position_count), COUNT(*) FROM fork_branches WHERE phrase_id = ?",
            (fork["phrase_id"],),
        ).fetchone()
        assert total == fork["position_count"]
        assert branches == fork["branch_count"]


def test_shape_matches_the_branch_sizes(con):
    from pipeline.forks import shape_of

    for fork in con.execute("SELECT * FROM forks"):
        assert fork["shape"] == shape_of(
            fork["branch_count"],
            fork["position_count"],
            fork["largest_branch"],
            fork["singleton_branches"],
        )


def test_all_but_one_really_leaves_one_behind(con):
    """The cheapest shape must never be a 1-versus-1 split dressed up."""
    for fork in con.execute("SELECT * FROM forks WHERE shape = 'all_but_one'"):
        assert fork["position_count"] >= 3
        assert fork["position_count"] - fork["largest_branch"] == 1
        assert fork["singleton_branches"] == 1


def test_largest_branch_is_flagged_once(con):
    for fork in con.execute("SELECT phrase_id, largest_branch FROM forks"):
        flagged = con.execute(
            "SELECT COUNT(*), MAX(position_count) FROM fork_branches "
            "WHERE phrase_id = ? AND is_largest = 1",
            (fork["phrase_id"],),
        ).fetchone()
        assert flagged[0] == 1
        assert flagged[1] == fork["largest_branch"]


# -- the index ----------------------------------------------------------------


def test_index_pages_without_dropping_or_repeating(con):
    seen, offset = [], 0
    while True:
        page = L.fork_index(con, limit=100, offset=offset)
        seen += [p["phrase_id"] for p in page["phrases"]]
        if not page["phrases"]:
            break
        offset += 100
        if offset > page["counts"]["total"]:
            break
    total = con.execute("SELECT COUNT(*) FROM forks").fetchone()[0]
    assert len(seen) == len(set(seen)) == total


def test_useful_sort_puts_the_cheapest_shape_first(con):
    phrases = L.fork_index(con, limit=100)["phrases"]
    rank = {"all_but_one": 0, "two_way": 1, "many": 2, "no_fork": 3}
    ranks = [rank[p["shape"]] for p in phrases]
    assert ranks == sorted(ranks)


def test_shape_filter_only_returns_that_shape(con):
    for shape in ("all_but_one", "two_way", "many"):
        page = L.fork_index(con, shape=shape, limit=50)
        assert page["phrases"]
        assert {p["shape"] for p in page["phrases"]} == {shape}


def test_surah_filter_returns_forks_touching_that_surah(con):
    page = L.fork_index(con, surah=55, limit=50)
    for phrase in page["phrases"]:
        surahs = {
            position["surah"]
            for branch in phrase["branches"]
            for position in branch["positions"]
        }
        assert 55 in surahs


def test_min_positions_filter(con):
    page = L.fork_index(con, min_positions=10, limit=50)
    assert page["phrases"]
    for phrase in page["phrases"]:
        assert phrase["position_count"] >= 10


def test_unknown_shape_and_sort_are_rejected(con):
    with pytest.raises(ValueError):
        L.fork_index(con, shape="sideways")
    with pytest.raises(ValueError):
        L.fork_index(con, sort="alphabetical")


def test_road_tail_is_the_shared_run(con):
    page = L.fork_index(con, limit=200, sort="branches")
    for phrase in page["phrases"]:
        if phrase["shared_after"]:
            assert phrase["road_tail_ar"]
            assert phrase["road_ar"].startswith(phrase["phrase_ar"])
        else:
            assert phrase["road_tail_ar"] is None


# -- the detail ---------------------------------------------------------------


def test_detail_carries_a_peg_and_an_ayah_for_every_position(con):
    phrase_id = con.execute(
        "SELECT phrase_id FROM forks WHERE shape = 'all_but_one' "
        "ORDER BY position_count DESC LIMIT 1"
    ).fetchone()[0]
    detail = L.fork_detail(con, phrase_id)
    seen = 0
    for branch in detail["branches"]:
        for position in branch["positions"]:
            assert position["peg"]["text_ar"]
            assert position["ayat"] and position["ayat"][0]["words"]
            assert any(w["in_span"] for w in position["ayat"][0]["words"])
            seen += 1
    assert seen == detail["position_count"]


def test_unknown_phrase_is_an_error(con):
    with pytest.raises(L.PhraseNotFound):
        L.fork_detail(con, 999999)


# -- routing ------------------------------------------------------------------


def test_official_page_route(con):
    for path in ("/official", "/forks"):
        status, payload = build_response(con, path, {})
        assert status == HTTPStatus.OK and payload == PAGE_FORKS


def test_index_route_accepts_filters(con):
    status, payload = build_response(
        con, "/api/official", {"shape": ["all_but_one"], "limit": ["3"]}
    )
    assert status == HTTPStatus.OK
    assert payload["counts"]["returned"] == 3


def test_index_route_rejects_a_bad_shape(con):
    with pytest.raises(BadRequest):
        build_response(con, "/api/official", {"shape": ["sideways"]})


def test_detail_route(con):
    phrase_id = con.execute("SELECT phrase_id FROM forks LIMIT 1").fetchone()[0]
    status, payload = build_response(con, f"/api/official/{phrase_id}", {})
    assert status == HTTPStatus.OK
    assert payload["phrase_id"] == phrase_id
