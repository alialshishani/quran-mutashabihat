# Data Provenance

Downloaded: **2026-08-26**. Source: QUL — Quranic Universal Library, `https://qul.tarteel.ai`.

All 14 resources were fetched through an authenticated browser session (QUL gates every
dataset download behind a signed-in account; there is no anonymous download URL and no API).
Archives are kept unmodified in this directory; `scripts/extract.py` unpacks them into
`extracted/`, which is what the pipeline reads.

## Downloaded resources

SHA-256 is of the archive as downloaded (first 16 hex digits shown; full values in
`data/interim/intake_report.md`, which also records the checksum of every extracted file).

| ID | Resource | Page URL | Archive | Bytes | SHA-256 |
|---|---|---|---|---|---|
| 56 | Uthmani word-by-word (spine) | `https://qul.tarteel.ai/resources/quran-script/56` | `qul-56-uthmani-wbw.db.zip` | 1,593,605 | `2848b6a9343703d0…` |
| 54 | Imlaei word-by-word | `https://qul.tarteel.ai/resources/quran-script/54` | `qul-54-imlaei-wbw.db.zip` | 1,574,140 | `99d40a09ee68892e…` |
| 15 | KFGQPC V1 layout (1405H) | `https://qul.tarteel.ai/resources/mushaf-layout/15` | `qul-15-layout-kfgqpc-v1.db.zip` | 99,413 | `fb04bdfb0da38925…` |
| 10 | KFGQPC V2 layout (1421H) | `https://qul.tarteel.ai/resources/mushaf-layout/10` | `qul-10-layout-kfgqpc-v2.db.zip` | 99,483 | `697cbc7f16db1f56…` |
| 70 | Surah names | `https://qul.tarteel.ai/resources/quran-metadata/70` | `qul-70-surah-names.sqlite.zip` | 3,597 | `067e108eaf97283c…` |
| 69 | Ayah metadata | `https://qul.tarteel.ai/resources/quran-metadata/69` | `qul-69-ayah-metadata.sqlite.zip` | 413,279 | `cbe824efb65136ac…` |
| 68 | Juz | `https://qul.tarteel.ai/resources/quran-metadata/68` | `qul-68-juz.sqlite.zip` | 1,493 | `32412ac4395b3a7d…` |
| 67 | Hizb | `https://qul.tarteel.ai/resources/quran-metadata/67` | `qul-67-hizb.sqlite.zip` | 2,025 | `890c3aecccd8840d…` |
| 63 | Rub | `https://qul.tarteel.ai/resources/quran-metadata/63` | `qul-63-rub.sqlite.zip` | 5,026 | `950334c31f819b1a…` |
| 76 | Word root | `https://qul.tarteel.ai/resources/morphology/76` | `qul-76-word-root.db.zip` | 472,972 | `a85c325c669fdf32…` |
| 75 | Word lemma | `https://qul.tarteel.ai/resources/morphology/75` | `qul-75-word-lemma.db.zip` | 736,040 | `8fd431f0b765d9a6…` |
| 77 | Word stem | `https://qul.tarteel.ai/resources/morphology/77` | `qul-77-word-stem.db.zip` | 960,429 | `57992661ebd776d2…` |
| 73 | Mutashabihat (baseline only) | `https://qul.tarteel.ai/resources/mutashabihat/73` | `qul-73-mutashabihat.json.bz2` | 39,009 | `2ac8d84e90cf8859…` |
| 74 | Similar Ayah (baseline only) | `https://qul.tarteel.ai/resources/similar-ayah/74` | `qul-74-similar-ayah.db.zip` | 40,077 | `f0d911bdff94e1e9…` |

Resources 73 and 74 are the evaluation baselines of brief §2 and §8a. They are **not** shipped
as product.

### Container note
`qul-73-mutashabihat.json.bz2` is named `.bz2` but is a **ZIP** container holding
`phrases.json` and `phrase_verses.json`. `scripts/extract.py` dispatches on magic bytes rather
than filename; trusting the extension silently loses this resource.

## KFGQPC page fonts and glyph codes

Fetched **2026-08-28** by `python -m scripts.fetch_qcf`, which also wrote a SHA-256 per
file to `data/raw/qcf-v1-manifest.json` (tracked). Neither origin is gated: no account,
no sign-in.

The muṣḥaf is not set in one typeface. KFGQPC cuts a font **per page**, holding that
page's glyphs already shaped and already elongated to fill their lines, addressed through
a private encoding. A page therefore needs two things, and they come from two places.

| What | Files | Bytes | Origin |
|---|---|---|---|
| QCF V1 page fonts (woff2) | 604 | 41,634,228 | `static-cdn.tarteel.ai/qul/fonts/quran_fonts/v1-optimized/woff2/p{page}.woff2` |
| Per-word `code_v1`, with page and line | 604 | 26,275,322 | `api.quran.com/api/v4/verses/by_page/{page}` |

`api.quran.com` is a **new origin for this repository** — everything above it came from
QUL. It is the Quran.com v4 API, open and unauthenticated. It is used for one field,
`code_v1`, plus the `page_number` and `line_number` that make the field checkable; no
Qur'anic text is taken from it, since the corpus already has the text from QUL resource
56.

`pipeline.glyphs` binds the codes to the corpus by position and refuses to write if the
two disagree about which **page** a token prints on. They are independent records of the
same 1405H typesetting, and across all 604 pages they disagree about three things, all
recorded as notes rather than errors:

- **2 words** at a line boundary (13:37 word 9, 36:52 word 11) that the font and the QUL
  layout put on different lines. The glyph is cut to fill the line the font puts it on,
  so the font's placement is the one that renders, and it is the one stored.
- **3 āyāt** (2:181, 8:6, 13:37) where the font sets a word pair as one two-glyph token
  that the Uthmānī source splits. The merge never crosses an āyah, so nothing keyed by
  āyah loses by it.

### Licence — unresolved, and more sharply than for the text

These are **font binaries cut by the King Fahd Glorious Qur'an Printing Complex**, served
by a third party. The redistribution question already open below for the QUL datasets
applies here with less room for optimism: nothing in this repository establishes a right
to redistribute them. They are gitignored — `scripts.fetch_qcf` refetches them from the
origins above — so the repository ships the *means* to obtain them, not the files. That
is a stopgap, not an answer, and it must be settled before M8 ships anything to end
users.

## Licence

QUL publishes **no per-resource licence** on the download pages — inspected on 2026-08-26, the
resource pages carry only tags, a preview, field descriptions and the download buttons. The
only licence surface is the site-wide footer:

- Terms of use: `https://www.tarteel.ai/terms`
- Credits: `https://qul.tarteel.ai/credits`
- Application source (`github.com/TarteelAI/quranic-universal-library`): MIT

**Open item:** the redistribution terms for the *exported datasets* are not established. This
must be settled before M8, because the offline frontend ships the database to end users.

## QAC morphology mirror verification

QUL's morphology resources cover only lemma, root and stem — no part-of-speech tags and no
morphological features. Brief §3 requires `pos` and `features`, and the §6 codes `NUMBER`,
`DEFINITE`, `PRONOUN`, `PERSON` plus rule R8 depend on them. Brief §2 item 5 directs
supplementing from the Quranic Arabic Corpus.

The official download at `https://corpus.quran.com/download/` is gated behind a form requesting
a contact e-mail address (the direct path `/java/quranic-corpus-morphology-0.4.txt` returns
302 → `/`). Per user decision, GitHub mirrors were located and cross-checked instead.

### Verified verbatim copies

Content SHA-256 after normalising line endings to LF:

```
910b721a8f04f4334ac5d4c62b19e858f5d720c525bb975f2e750ea2c6bb532d
```

| Mirror | Path | EOL |
|---|---|---|
| `cltk/arabic_morphology_quranic-corpus` | `quranic-corpus-morphology-0.4.txt` | CRLF |
| `karimouda/qurananalysis` | `data/quranic-corpus-morphology-0.4.txt` | CRLF |
| `lAvArt/Quranic-Linguistics-Observatory` | `public/data/quranic-corpus-morphology-0.4.txt` | LF |

Three independent repositories agree exactly. The file retains its original 54-line copyright
header: *Quranic Arabic Corpus (morphology, version 0.4), Copyright (C) 2011 Kais Dukes,
License: GNU General Public License*, built on the Tanzil verified Arabic text. Format is
Buckwalter, tab-separated, location key `(surah:ayah:word:segment)`, with
`STEM|POS:…|LEM:…|ROOT:…` feature strings.

**Licence: GPL.** This is fine for a pipeline input but must be resolved before M8 if
morphology-derived fields ship inside the offline frontend database.

### Rejected derivative — do not use

`mustafa0x/quran-morphology` → `quran-morphology.txt` is **not** a mirror. It is a reformatted
derivative: Arabic script instead of Buckwalter, no copyright header, different segment
tagging, 130,030 lines against 128,276, and substantively different root assignments — the
final word of sūrah 114 carries root `nws` in the original and a different root in the
derivative. Rejected: it would inject unverifiable root data into rules R3 and R8.

**Status: staged in scratchpad, awaiting approval of a specific mirror. Not yet copied into
this directory, and `words.pos` / `words.features` are NULL until it is.**

## Findings recorded during ingestion

### 1. Ayah-number markers are tokens in the QUL word tables
`words` in resources 56 and 54 holds 83,668 rows, of which exactly 6,236 are ayah-number
tokens (one per ayah, always the last token of its ayah, always containing Arabic-Indic
digits). Real word tokens: **77,432**. The canonical `words.word_id` is a contiguous rank over
non-marker tokens; `src_word_id` preserves the original QUL id so the layout join stays exact.

### 2. QUL and QAC disagree on 3 ayahs, from one cause
Per-ayah token counts match everywhere except 2:181, 8:6 and 13:37, where QUL has one token
more. In all three the cause is identical: QUL splits `بَعْدَ مَا` into two tokens where QAC
joins it as one. Word indices therefore shift by +1 after that point in those three ayahs, and
the reconciliation must account for it. No other divergence exists.

### 3. Morphology locations with no matching word
Three lemma locations point one past the last real word of their ayah: `13:5:26`, `2:275:46`,
`4:176:51`. They are logged by `pipeline/ingest.py` on every run rather than silently dropped.

### 4. Two tokens contain an internal space
`37:130` (`إِلْ يَاسِينَ`) and `5:52` (`دَآئِرَ ةٌۭ`) are written with a space inside the
token in the Uthmānī rasm. `text_uthmani` preserves this byte-for-byte (C6); the index key
`text_norm` drops internal spaces so that one token yields one key.

### 5. The two script resources genuinely disagree on 16 ayahs
Round-tripping the word-by-word Uthmānī against the ayah-level QPC Hafs export leaves 16 of
6,236 ayahs differing, every difference a single character and every one a hamza-seat
alternation (ئ/ي, ؤ/و, ا/ي, bare ء). This is a property of the two sources, not of the
pipeline. `validate_db.py` tolerates single-character hamza-seat differences and **fails on
anything else**, so a dropped word or reordered phrase still breaks the gate.

## Reconciliation status
QUL↔QAC reconciliation by word index is pending the mirror decision. When it runs, every
mismatch is logged to `data/interim/morph_reconcile.md` per brief §2.
