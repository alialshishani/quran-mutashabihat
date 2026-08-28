# The app (`mobile/`)

Ḍābiṭ: the muṣḥaf on a phone, page for page in its own typeface, with the
mutashābihāt marked on it and the peg for each — reading the corpus directly,
with no server and no network.

```bash
python -m mobile.tools.stage_assets          # build what the app ships
cd mobile/app && flutter run                 # or: flutter build apk --release
```

## What it is

`app/lookup.py` does not run on the phone. `port/` is its translation into Dart,
and the app calls that against the same `quran.db` the web service reads —
shipped inside the APK and copied out on first launch.

| | |
|---|---|
| `port/lib/mushaf.dart` | `mushaf_page` — one printed page, its lines and tokens |
| `port/lib/official.dart` | `official_matches` — the curated phrases, each position with its peg |
| `port/lib/lookup.dart` | `lookup` — the above plus pass A's detected repeats and their ḍawābiṭ |
| `port/lib/forks.dart` | `fork_index`, `fork_detail` — the mutashābihāt as forks |
| `port/lib/drill.dart` | the drill. **Not a port** — see below |
| `app/lib/` | the Flutter app |
| `tools/` | what builds the assets, and what dumps the goldens |

## The port is verified, not reviewed

Every function is checked against the Python's own output, byte for byte. Both
sides emit canonical JSON — keys sorted, UTF-8, compact — so a difference in key
order cannot hide a difference in content.

```bash
python -m mobile.tools.dump_goldens mobile/golden           # the oracle
cd mobile/port && dart run bin/verify.dart ../../data/quran.db ../golden/pages
```

| Function | Cases | Result |
|---|---|---|
| `mushaf_page` | all 604 printed pages | 604 identical |
| `official_matches` | all 2,295 āyāt carrying an official phrase | 2,295 identical |
| `fork_index` | 35 filter/sort/paging combinations | 35 identical |
| `fork_detail` | all 809 forks | 809 identical |
| `lookup` | 169 āyāt across the muṣḥaf | 169 identical |

`bin/selfcheck.dart` additionally runs every page against two databases that
plan their queries differently, which is what caught the ordering bug below.
The drill has no oracle and is tested instead: `cd mobile/port && dart test`.

## The drill

The one part with no Python counterpart, so it cannot be checked against one. It
is covered by `port/test/drill_test.dart` instead — 11 tests, two of which walk
the entire pool rather than a sample.

A fork already has the shape of a question. The road is the wording every
position shares, the branches are the ways out, and each position takes exactly
one of them: *you are here, reciting this — which way does it go?* A miss is
answered with the peg `pipeline.pegs` verified for that position, because
knowing the way out is not the same as knowing what tells this place from the
others.

**3,734 questions** over 808 forks: `all_but_one` 264, `two_way` 804, `many`
2,666. `no_fork` is excluded — those positions never part, so there is nothing
to ask. Cheapest shape first, so a reciter meets *one exception to hold* before
*a peg per position*. Leitner boxes (0/1/3/7/21 days) on the device only.

### Why the question shows the whole āyah

Because without it a third of the drill is unanswerable. **491 forks have a
single sūrah taking two or more different ways out**, covering **1,313 of the
3,734 positions**. For those, naming the sūrah settles nothing and the road is
shared by definition — only the wording leading into the fork tells them apart.
So the question shows the āyah from its first word up to the fork, or the tail
of the āyah before when the road opens this one.

That leaves 18 where the same sūrah says the same words into the same fork
twice and then parts. Nothing in the recitation separates those, and the
reciter's only handle is which time it is — which is what an `ORDINAL_IN_SURAH`
peg is (`docs/PEGS.md`). The question carries that as a badge, and only where a
sūrah holds more than one occurrence.

```bash
cd mobile/port && dart run bin/drill_audit.dart ../../data/quran.db
```

| | |
|---|---|
| ambiguous within a sūrah | **0** |
| ambiguous only across sūrahs | 49 — the question names the sūrah, so answerable |
| no run-up at all | 4 — all of them open a sūrah |

## What the port found in the Python

Four things, all in the SQL, so all of them are worth the same to `app/`:

| | |
|---|---|
| **`phrase_ids` order is nondeterministic** | `official_positions` is queried with no `ORDER BY`, so the row order — and with it the order of `phrase_ids` in the response — comes from the query plan. Adding an index reorders 66 pages with no change in content. An `ANALYZE` or a different SQLite version would do the same. |
| **`_page_marks` scans nearly the whole table** | `o.start_word_id <= a.last_word_id` is open-ended, so a late page walks most of `occurrences`. No span exceeds 28 words, so an overlapping one must *start* within 28 words of the āyah; bounding the range uses the index that already exists and returns the identical set. 29.9 ms → 0.22 ms. |
| **No index on `ayahs(juz/hizb/rub)`** | Three full scans of `ayahs` per āyah on the page. See `tools/read_path_indexes.sql`. 12.7 ms → 0.1 ms. |
| **`has_layout`/`has_glyphs` count every row** | `SELECT COUNT(*) FROM x LIMIT 1` — the `LIMIT` does not shorten an aggregate, so asking whether `glyphs` is populated walks all 83,665 rows, on every page turn. |

Page turn, 604 pages, same measurement both sides:

| | mean | median | p95 | max |
|---|---|---|---|---|
| Python, as it stands | 60.5 ms | 48.0 ms | 159.5 ms | 276.1 ms |
| Dart, literal port | 57.7 ms | 46.0 ms | 152.2 ms | 262.9 ms |
| Dart, with the four fixes | **15.1 ms** | **14.9 ms** | **16.2 ms** | **17.4 ms** |

The port costs nothing — it was marginally faster than Python before any fix.

## The typeface

The same argument as `docs/MUSHAF.md`, and it survives the move intact. The
KFGQPC page fonts carry **no GSUB and no GPOS** — 600 of the 604 have neither
table, and the four that do (p105, p270, p552, p554) carry empty ones. So there
is nothing for the Arabic shaper to substitute and every engine reduces to a
cmap lookup. HarfBuzz over all 8,820 printed lines gives `glyphs_out ==
chars_in` and no `notdef` anywhere, and Flutter's line widths for page 89 match
the browser's to the decimal.

One thing Flutter forces that the browser did not: **it cannot load WOFF2**.
`tools/stage_assets.py` strips the container, which costs size — 41.6 MB of
WOFF2 becomes 69.8 MB of TTF, 46.8 MB after store compression.

`em` per page is measured once from the widest line, and the type is set at
`width / em` — the same formula as the stylesheet's `calc(100cqi / var(--em))`.
Which is why margin is expensive here: every pixel of it comes off the measure,
and so off the size of the letters.

## Offline, and proved so

The release app requests **no `INTERNET` permission**. The OS would refuse a
network call. Two things had to be fixed to earn that, both web-only:

- Flutter web fetches its own engine from a CDN — `--no-web-resources-cdn`
  bundles it.
- CanvasKit fetches Arabic fallback fonts from the network, so sūrah headings
  rendered as tofu offline. The drawn lines name a bundled face instead.

## Licence — the same open question, now on a device

`data/raw/PROVENANCE.md` records that nothing establishes a right to
redistribute the KFGQPC fonts, and that it must be settled before M8 ships to
end users. A build of this app *is* that: it puts all 604 of them, and the
derived corpus, on a phone. That is fine for testing on your own hardware and is
not fine for anyone else's, and the app cannot go further until the question is
answered.

Amiri, the one font this repository does vendor into a build, is OFL.

## Not done yet

1. **The package id is `com.example.qcf_spike`** and the build is signed with
   Flutter's debug keystore. Play refuses `com.example.*`; a debug-signed build
   cannot be updated over. Both want fixing before this leaves the bench.
2. **The drill asks about official phrases only.** Pass A's own detected
   repeats have ḍawābiṭ too and are not drilled.
3. **`lookup` runs on the UI thread.** Fast in practice, but a phrase with 90
   positions loads a lot of āyah text; an isolate is the fix if a tap ever drags.
4. **No dark mode.** `app/mushaf_page.py` carries a full dark palette and the
   app ignores it.
5. **The page opens at 89 every time.** It should remember where you were.
6. **iOS is untouched** — the Dart is platform-agnostic and `corpus_native.dart`
   already covers it, but nothing has been built or run there.
