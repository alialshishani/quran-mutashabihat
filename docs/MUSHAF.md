# The muṣḥaf page (`/mushaf`)

The printed page, reproduced line for line, with the mutashābihāt marked on it.
Click any word or āyah number and a panel opens with every phrase that āyah
shares with another, the peg that tells them apart, and a way to jump straight
to each of the other positions in the muṣḥaf.

```bash
python -m pipeline.layout --rebuild     # once, after pipeline.ingest
python -m app.server                    # http://127.0.0.1:8000/mushaf
```

## What makes it the muṣḥaf and not a reflow

`pipeline.ingest` stamps every word with the page, line and position it prints
at, which is enough to *find* a word but not to *set* a page: a printed page also
carries lines that hold no word (the sūrah heading, the basmalah), and an āyah
marker is a token with a place on a line and no row in `words`.

`pipeline.layout` closes both gaps. It reads the same KFGQPC layout database the
corpus was ingested from — whichever one `meta.layout` names, currently the V1
(1405H) layout — and writes one row per printed line into a `lines` table: its
type, whether it is centred, the sūrah a heading announces, and the source id
range the line covers.

The source range is what places the markers. A marker's id in the source script
is one past the last word of the āyah it closes, so walking the range token by
token puts every marker where the muṣḥaf prints it — including the 566 lines in
this layout that **open** with the marker of the āyah that ended on the line
before. Reconstructing markers by "last word of an āyah, therefore same line"
would put all 566 of them one line too high.

The pass refuses to write if any line disagrees with the page/line already
stamped on the words themselves, which is how the corpus and the layout are held
to the same source.

| Reproduced exactly | From |
|---|---|
| 604 pages, 15 lines (8 on pages 1–2) | `lines` |
| Every line break | `lines.src_first`/`src_last` |
| Sūrah headings and basmalah lines | `lines.line_type` |
| Centred lines | `lines.is_centered` |
| Āyah markers, in their printed position | source id range + `ayahs.last_word_id` |
| The rub'-el-ḥizb sign ۞ | the Uthmānī text carries it inline, on the word |
| Every token | `words.text_uthmani`, byte for byte |

## What is not exact: the typeface

KFGQPC sets each page of the muṣḥaf in a font cut **for that page** — 604 fonts,
each holding the glyphs of one page in a private encoding, driven by per-word
glyph codes. Neither the fonts nor the glyph codes are vendored here (see the
open licence item in `data/raw/PROVENANCE.md`), so the page renders the Uthmānī
text in a general Arabic face instead:

1. an installed muṣḥaf font, if there is one — the `@font-face` rule asks for
   `KFGQPC HAFS Uthmanic Script`, `KFGQPC Uthman Taha Naskh` and the other names
   the Complex ships under, via `local()`;
2. otherwise Amiri Quran, from Google Fonts.

### Why the lines look loose

The Complex's fonts justify by **elongating their own glyphs**, and that is not
a detail — measured over all 8,820 printed lines, the median line asks for only
68% of the measure it is set in. In print that missing third is absorbed by
elongation, invisibly. A general Arabic face cannot elongate, so the third has
to go somewhere, and there are only three places to put it:

| | Artefact |
|---|---|
| Fit each page to its own densest line | Type size swings 2.27× between pages — page 1 large, page 479 small |
| Scale lines sideways to the measure | Distorted letterforms; the stroke weights go wrong |
| **One size for the book, gaps take the slack** | Word spaces open up — ~32% on the median line |

The third is what the page does, because it is the only one that leaves the
letterforms alone and the one print itself would recognise: a muṣḥaf is set at
one size and holds it for 604 pages. `pipeline.layout` records `width_chars` per
line — characters that advance the pen, so combining marks do not count — and
`/api/measure` hands the densest few lines to the page, which measures them in
whatever face is actually drawing and sets the book from the widest. Pages 1 and
2 are fitted to themselves, which is the exception the print makes too: eight
lines in their own frame, set larger than the body of the book.

None of the three is right. Elongation is, and only the Complex's own fonts do
it — see item 3 under "Next".

The text block holds a fixed 1:1.55 proportion and spreads its lines down it, so
a 15-line page and the eight-line opening sit on the same sheet.

Getting to a glyph-exact clone is a data problem, not a rendering one — see
"Next" below.

## What the print cannot say

Two marks, both computed per request from the database:

- **Words inside an official mutashābih phrase** carry a hairline under them.
  The underline is per word, not per āyah, so the shared wording is visible as
  wording — you can see where the agreement starts and stops on the page.
- **An āyah marker whose āyah carries an official phrase** is filled rather than
  outlined, and its tooltip says how many.

Clicking anything selects that āyah and opens the panel, which calls
`/api/mutashabih/{surah}/{ayah}` and shows the official phrases first (each with
the peg for this position and the peg for each sibling), then the detected
repeats behind a disclosure. Every sibling position is a button that turns the
muṣḥaf to that page and selects that āyah.

Keyboard: `←` turns to the next page and `→` to the previous, as the muṣḥaf
reads; `Esc` closes the panel. The view deep-links as `#p=89` and `#p=89&a=4:69`.

## API

| Route | Purpose |
|---|---|
| `GET /mushaf` | The page. |
| `GET /api/page/89` | One printed page: its lines, the tokens on each, the āyāt on it and what repeats there. |
| `GET /api/page?page=89` | Same, query form. Takes `scope` like the other endpoints. |
| `GET /api/measure` | The densest lines in the muṣḥaf, for the page to set one type size by. |

`/api/health` reports `pages` alongside the row counts; it is `0` until
`pipeline.layout` has run, and the page route answers `503` with the command to
run.

## Next

Roughly in the order the value lands.

1. **Tests.** `tests/test_mushaf.py` does not exist yet. The invariants worth
   holding: every word in the corpus appears on exactly one page and one line and
   in `word_id` order within it; the tokens of a page concatenate to the same
   text as `words` for the āyāt on it; all 604 pages render without raising;
   marker count per page equals the number of āyāt ending on it; the `lines`
   table agrees with `words.page`/`words.line` for every row (currently only
   checked at build time); `/api/page/0`, `/api/page/605` are 404 and a corpus
   without `lines` gives 503.
2. **Verify the panel end to end.** The page, the marks and the fitting were
   checked in a browser; the click-through to the panel and the jump buttons were
   not — the last check was interrupted. Click a marked word, confirm the panel
   fills, then confirm a sibling jump lands on the right page with the right āyah
   selected.
3. **Glyph exactness.** Needs two more QUL resources, both licence-gated behind
   a signed-in account like the rest (`docs/DOWNLOAD.md`): the QCF V1 or V2 page
   fonts, and the script resource carrying the per-word glyph code for that font
   version. With both, `pipeline.ingest` gains a `code_v1`/`code_v2` column,
   `app/server.py` gains a `/fonts/` route, and the page swaps
   `font-family: qcf-p089` in per page — at which point `fitLines`, `/api/measure`
   and `width_chars` can all go, because the Complex's fonts justify themselves
   and the loose-line problem above stops existing. Record
   the checksums and licence in `PROVENANCE.md` first; the redistribution item
   open there covers the fonts too, and more sharply.
4. **The V2 layout.** Both layouts are vendored and `pipeline.layout` follows
   whatever `meta.layout` names, but switching means re-running `pipeline.ingest
   --rebuild` and everything downstream of it, because page/line are stamped on
   the words. Worth a flag on the page rather than a rebuild only if a reader
   asks for it.
5. **Sajdah marks and the ḥizb quarter signs** are printed in the muṣḥaf and are
   not reproduced. The sajdah positions are not in any vendored resource; the
   quarter signs would come from `ayahs.rub` the way `starts_rub` already does.
6. **Print stylesheet.** The sheet is already a fixed-proportion page; `@media
   print` would make it an actual one, one page per sheet.
