# Linking the official mutashābihāt to a peg

The R1 majority rule describes a whole group in one sentence — "all the
positions take X except one, in sūrah Y". When the distribution allows it that
is the cheapest peg there is, and it fired on 308 of 4,610 detected groups.

Most confusable phrases have no majority to lean on. `يَـٰٓأَيُّهَا ٱلَّذِينَ
ءَامَنُوا۟` sits in 89 places; no statement about the set tells you which one you
are standing in. Each position needs its own handle. That is what this pass
builds, over the curated QUL mutashābihāt list rather than over detected repeats
alone.

## What can serve as a peg

At the moment of the decision, a reciter arriving at a shared phrase holds two
things: the words just recited, and the knowledge of which sūrah they are in.
They do **not** hold the continuation — that is the thing being chosen.

So a unique *following* word is not a peg. It is the answer the peg has to
select. An early version of this pass ranked "unique continuation" as the
strongest rung and would have reported it as the ḍābiṭ for 85% of positions;
that sentence tells a memoriser that the continuations differ, which they
already knew, and not which one belongs here.

The ladder therefore keys on the cue and reports the continuation as payload:

| Rung | Cue | Positions | Share |
|---|---|---|---|
| `CUE_BEFORE` | shortest run of preceding words carried by this position and no other | 3,378 | 90.4% |
| `SOLE_IN_SURAH` | the phrase occurs once in this sūrah, so the sūrah names it | 196 | 5.2% |
| `ORDINAL_IN_SURAH` | the nth of m inside one sūrah, anchored to its page | 162 | 4.3% |

Every one of the 3,736 positions gets a peg, and 2,427 of them need only a
single preceding word:

| Cue width | 1 word | 2 | 3 | 4 |
|---|---|---|---|---|
| Positions | 2,427 | 513 | 266 | 172 |

Reading one, for 2:153 — `يَـٰٓأَيُّهَا ٱلَّذِينَ ءَامَنُوا۟` among its 89 places:

> ما قبله (تَكْفُرُونِ) وحده من بين 89 مواضع، وما بعده (ٱسْتَعِينُوا۟). سورة البقرة — 2:153، ص 23.

## The confusion set

A peg is only as good as the set it was checked against, and neither available
source is that set on its own:

- The **official list omits real repeats.** 65 phrases occur in more places than
  the list names — one lists 62 positions where the muṣḥaf carries 89. A cue
  verified as unique among 62 and shared with one of the other 27 is exactly the
  peg that teaches a mistake.
- **Exact matching misses the near-variants**, which are what make a phrase
  confusable to begin with. 521 phrases carry at least one official position
  that is not a token-for-token repeat of the source phrase.

So the confusion set is the **union**: official positions ∪ every exact repeat of
the phrase's own token sequence. `pipeline.official` builds it; `pipeline.pegs`
verifies against it and nothing narrower.

## One window per set

The official list marks a different extent at different positions — four words
at the source of phrase 7060, six words at each occurrence. Reading a
continuation from one offset here and another offset there is not a comparison,
so every member of a set is measured over one window: the phrase's own length,
from the phrase's own start. The listed extent is kept in
`official_positions.listed_end_word_id` for provenance.

Normalizing the window cut the positions whose continuation is still ambiguous
at four words from 438 to 298 — those earlier "distinctions" were an artefact of
mismatched offsets.

## What a peg does not claim

- Not that the cue is unique **in the muṣḥaf** — only that it is unique **within
  this phrase's confusion set**. The sentence says `من بين N مواضع` and names N.
- Not why the wording differs. A peg says where a wording sits (C5).
- Nothing at all where the ladder finds no cue. Two positions with identical
  surroundings in one sūrah get `ORDINAL_IN_SURAH` with the page, or nothing.

Every claim is re-derived from `words` in `tests/test_pegs.py` rather than read
back from the row that made it — including that each cue is carried by exactly
one position, that a narrower cue would *not* have been unique (minimality), and
that the count in the Arabic sentence is the real count.

## The fork

A repeated phrase is not by itself worth studying. What costs a reciter is the
fork: a stretch of wording they have recited before, then a point where it goes
two ways and nothing in the road itself says which. `pipeline/forks.py` reshapes
each phrase that way — road, fork, branches — and `/official` is that view.

| Shape | Phrases | Meaning |
|---|---|---|
| `two_way` | 384 | the road splits in two |
| `many` | 349 | more than two ways out |
| `all_but_one` | 75 | one position leaves the road the others take |
| `no_fork` | 1 | the positions never disagree after the phrase |

731 of the 809 fork on the very next word; the rest run on together for up to
twelve more, and that shared tail is part of the road.

`all_but_one` is the cheapest shape to hold — learn the exception, default to
the rest — and the rule deliberately requires at least three positions. A
two-position phrase splitting one-and-one is a `two_way`, not an exception: the
first cut of this counted those and reported 448 "all but one" forks where there
are 75.

## Running it

```bash
python -m pipeline.official --rebuild   # confusion sets, linked to pass-A groups
python -m pipeline.pegs --rebuild       # the ladder
python -m pipeline.forks --rebuild      # road, fork, branches
python -m pytest tests/test_pegs.py tests/test_forks.py -q
```

`--rebuild` drops and recreates its own tables, so it carries a schema change.

## Tables

| Table | Row per | Notes |
|---|---|---|
| `official_phrases` | curated phrase | source span, `official_count` / `exact_count` / `set_count` |
| `official_positions` | position in a confusion set | `in_official`, `in_exact`, `group_id` + `link` to the pass-A group (`exact` 2,310 · `contained` 495 · `contains` 484 · `overlap` 206 · `none` 241) |
| `pegs` | position | `kind`, `cue_ar`, `continuation_ar`, `strength`, `evidence`, `text_ar` |
| `similar_ayahs` | āyah pair | QUL resource 74, 3,552 pairs, ingested for later use |
| `forks` | phrase | `shared_after`, `road_ar`, `branch_count`, `largest_branch`, `shape` |
| `fork_branches` / `fork_members` | branch / position | one way out of the fork and who takes it |

Thresholds and weights live in `config/params.yaml` under `pegs:`.
