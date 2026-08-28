# The muṣḥaf page (`/mushaf`)

The printed page, reproduced line for line, with the mutashābihāt marked on it.
Click any word or āyah number and a panel opens with every phrase that āyah
shares with another, the peg that tells them apart, and a way to jump straight
to each of the other positions in the muṣḥaf.

```bash
python -m pipeline.layout --rebuild     # once, after pipeline.ingest
python -m scripts.fetch_qcf             # the muṣḥaf's own fonts, ~69 MB
python -m pipeline.glyphs --rebuild
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
| Every glyph, on āyah lines | `glyphs.code_v1` in the page's own KFGQPC font |

## The typeface

KFGQPC sets each page of the muṣḥaf in a font cut **for that page** — 604 fonts, each
holding that page's glyphs in a private encoding, already shaped and already elongated
to fill their lines, addressed by a per-word code. Both halves are public and
unauthenticated, and both are vendored:

```bash
python -m scripts.fetch_qcf        # 604 fonts + 604 code files, ~69 MB, resumable
python -m pipeline.glyphs --rebuild
```

`scripts.fetch_qcf` takes the fonts from the QUL CDN and the codes from the Quran.com v4
API; `pipeline.glyphs` binds the codes to `words` by position and checks them against the
layout the corpus was built on. Sources, checksums and the three places the two records
disagree are in `data/raw/PROVENANCE.md`, along with a licence question that is sharper
for font binaries than it was for the text.

With those bound, an āyah line is the print: the same glyphs, in the same order, on the
same line. What that buys is best said as a measurement — the fifteen lines of page 89,
in page 89's own font, at 100px:

```
1412 1408 1412 1412 1409 1412 1404 1404 1406 1403 1410 1415 1407 1407 1409
```

A spread of **0.9%**. Every line is the same width because the elongation is cut into the
glyphs. So there is nothing to justify and nothing to fit: the page is set at the one size
where a line-width lands on the measure, in CSS, from the measure itself —

```css
.qtext.qcf { font-size: calc(100cqi / var(--em)); text-align: right; }
```

— and re-sets itself on any resize with nothing measured in script. `--em` is taken once
per page from its widest line, since the width differs slightly between pages.

### Without the fonts

The page still works: it falls back to the Uthmānī text in an installed muṣḥaf font, or
Amiri Quran. That path is honest but visibly not the print, and the reason is worth
keeping written down. Over all 8,820 printed lines the median line asks for only **68%**
of the measure it is set in. In print that missing third disappears into elongation. A
general Arabic face cannot elongate, so it has to surface somewhere, and there are only
three places to put it:

| | Artefact |
|---|---|
| Fit each page to its own densest line | Type size swings 2.27× between pages |
| Scale lines sideways to the measure | Distorted letterforms; stroke weights go wrong |
| **One size for the book, gaps take the slack** | Word spaces open up — ~32% on the median line |

The fallback takes the third, as print would: `pipeline.layout` records `width_chars` per
line, `/api/measure` hands the densest few lines to the page, and the page measures them
in whatever face is drawing. Pages 1 and 2 are fitted to themselves, the exception the
print makes too.

### Still not the print

Sūrah headings and basmalah lines have no glyph codes — the API returns verses, and
neither is one — so they are drawn rather than set: a ruled cartouche carrying the sūrah
name, and the basmalah in the fallback face. On a page like 604 the difference between a
set line and a drawn one is visible. Closing it needs the Complex's heading font and its
codes; see "Next".

The text block holds a fixed 1:1.55 proportion and spreads its lines down it, so a
15-line page and the eight-line opening sit on the same sheet.

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
| `GET /api/measure` | The densest lines in the muṣḥaf, for the fallback face to set one type size by. |
| `GET /fonts/qcf-v1/p89.woff2` | The font KFGQPC cut for page 89. Immutable, so it is cached hard. |

`/api/health` reports `pages` alongside the row counts; it is `0` until
`pipeline.layout` has run, and the page route answers `503` with the command to
run.

## Next

Roughly in the order the value lands.

1. **Tests.** `tests/test_mushaf.py` does not exist yet. The invariants worth holding:
   every word appears on exactly one page and one line, in `word_id` order within it; a
   page's tokens concatenate to the same text as `words` for the āyāt on it; all 604
   pages render without raising; marker count per page equals the āyāt ending on it; the
   `lines` table agrees with `words.page`/`words.line`; every page has a font on disk and
   a glyph row for every token; `/api/page/0` and `/api/page/605` are 404, a corpus
   without `lines` gives 503, and `/fonts/qcf-v1/p9999.woff2` is 404.
2. **Sūrah headings and basmalah lines** are drawn rather than set — the only part of the
   page that is not the print. KFGQPC ships a heading font (sūrah names and basmalah) and
   QUL serves fonts beyond the page set; find it, and the codes that address it, and the
   last drawn thing on the page goes away.
3. **The 604 fonts are fetched, not shipped.** `.gitignore` keeps them out and
   `scripts.fetch_qcf` refetches them, so a fresh clone needs the network once. That is a
   stopgap for the licence question in `PROVENANCE.md`, not an answer to it, and M8 —
   which ships to end users — cannot go out with it unresolved.
4. **Only the current page's font is loaded.** Turning a page fetches ~65 KB. Prefetching
   the next and previous page's font on idle would make paging instant; the fonts are
   served `immutable`, so the browser keeps them.
5. **The V2 layout.** Both layouts are vendored and the V2 fonts are on the same CDN, but
   switching means re-running `pipeline.ingest --rebuild` and everything downstream,
   because page and line are stamped on the words.
6. **Sajdah marks** are printed in the muṣḥaf and are not reproduced; the positions are
   in no vendored resource. The rub'-el-ḥizb sign needs nothing — the text carries it.
7. **Print stylesheet.** The sheet is already a fixed-proportion page; `@media print`
   would make it an actual one, one muṣḥaf page per sheet.
