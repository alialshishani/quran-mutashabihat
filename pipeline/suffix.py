"""Suffix array, LCP array, and maximal-repeat extraction over a token stream.

Operates on a list of integer token ids, not characters, because the unit of
comparison in this project is the word (brief section 2). Built once here so
pass A over one juz and pass A over the whole muṣḥaf run the same code.
"""
from __future__ import annotations

from dataclasses import dataclass


def suffix_array(tokens: list[int]) -> list[int]:
    """Suffix array by prefix doubling. O(n log^2 n), stable and deterministic."""
    n = len(tokens)
    if n == 0:
        return []
    sa = sorted(range(n), key=lambda i: tokens[i])
    rank = [0] * n
    prev = tokens[sa[0]]
    r = 0
    for i in sa:
        if tokens[i] != prev:
            r += 1
            prev = tokens[i]
        rank[i] = r

    k = 1
    while k < n and rank[sa[-1]] < n - 1:
        def key(i: int, k: int = k) -> tuple[int, int]:
            return (rank[i], rank[i + k] if i + k < n else -1)

        sa.sort(key=key)
        new = [0] * n
        r = 0
        prev_key = key(sa[0])
        for i in sa:
            cur = key(i)
            if cur != prev_key:
                r += 1
                prev_key = cur
            new[i] = r
        rank = new
        k <<= 1
    return sa


def lcp_array(tokens: list[int], sa: list[int]) -> list[int]:
    """Kasai's algorithm. lcp[i] = common prefix length of sa[i-1] and sa[i]."""
    n = len(tokens)
    if n == 0:
        return []
    rank = [0] * n
    for i, s in enumerate(sa):
        rank[s] = i
    lcp = [0] * n
    h = 0
    for i in range(n):
        if rank[i] > 0:
            j = sa[rank[i] - 1]
            while i + h < n and j + h < n and tokens[i + h] == tokens[j + h]:
                h += 1
            lcp[rank[i]] = h
            if h:
                h -= 1
        else:
            h = 0
    return lcp


@dataclass(frozen=True)
class Repeat:
    """A maximal repeated span: `length` tokens starting at each of `starts`."""

    length: int
    starts: tuple[int, ...]

    @property
    def count(self) -> int:
        return len(self.starts)


def maximal_repeats(tokens: list[int], min_length: int, min_count: int) -> list[Repeat]:
    """Every maximal repeated substring of the token stream.

    Maximal means the span cannot be extended left or right without losing an
    occurrence (brief section 5, pass A):

    - Right-maximality comes free: each LCP interval is an internal node of the
      suffix tree, so its occurrences already differ in the next token.
    - Left-maximality is checked explicitly — if every occurrence is preceded by
      the same token, the span is a suffix of a longer repeat and is dropped.

    Returns spans sorted by (-length, first start) so the output is stable.
    """
    n = len(tokens)
    if n == 0:
        return []
    sa = suffix_array(tokens)
    lcp = lcp_array(tokens, sa)

    found: dict[tuple[int, tuple[int, ...]], Repeat] = {}
    # Stack of (lcp_value, interval_start_index_in_sa).
    stack: list[tuple[int, int]] = []

    def emit(length: int, lo: int, hi: int) -> None:
        """Record the interval sa[lo:hi+1] as a repeat of the given length."""
        if length < min_length:
            return
        starts = tuple(sorted(sa[lo : hi + 1]))
        if len(starts) < min_count:
            return
        # Left-maximality: the preceding tokens must not all be identical.
        preceding = {tokens[s - 1] if s > 0 else None for s in starts}
        if len(preceding) == 1:
            return
        found[(length, starts)] = Repeat(length, starts)

    for i in range(1, n + 1):
        cur = lcp[i] if i < n else 0
        start = i - 1
        while stack and stack[-1][0] > cur:
            height, lo = stack.pop()
            emit(height, lo, i - 1)
            start = lo
        if not stack or stack[-1][0] < cur:
            stack.append((cur, start))

    return sorted(found.values(), key=lambda r: (-r.length, r.starts[0]))
