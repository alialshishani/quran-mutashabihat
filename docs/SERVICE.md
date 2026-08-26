# Lookup service (`app/`)

A read-only HTTP service over what the pipeline already detected: given a sūrah
and an āyah, it returns every repeated phrase touching that āyah, all the other
places that phrase occurs, and any ḍābiṭ that verified for it.

Standard library only — nothing to install beyond what `pipeline/` already needs.

```bash
python -m app.server                       # http://127.0.0.1:8000
python -m app.server --port 8080 --cors    # allow calls from other local pages
```

It reads `data/quran.db` in read-only mode and never writes. If scope `full` is
empty it starts anyway and says what to run:

```bash
python -m pipeline.pass_a --scope full --rebuild
python -m pipeline.apply_rules --scope full --rebuild
```

For the official mutashābihāt section and its pegs:

```bash
python -m pipeline.official --rebuild
python -m pipeline.pegs --rebuild
```

## Endpoints

| Route | Purpose |
|---|---|
| `GET /` | The lookup page. Deep-links as `#2:25`. |
| `GET /api/mutashabih?surah=2&ayah=25` | Everything for one āyah (JSON). |
| `GET /api/mutashabih/2/25` | Same, path form. |
| `GET /api/surahs` | 114 sūrahs with āyah counts, for the picker. |
| `GET /api/scopes` | Which analysis scopes are populated. |
| `GET /api/health` | Row counts per table. |

### Query parameters

| Name | Default | Meaning |
|---|---|---|
| `scope` | `full` | Which pass-A scope to read (`full`, `juz30`, …). |
| `min_len` | `0` | Drop spans shorter than this many tokens. |
| `min_occurrences` | `2` | Drop phrases occurring fewer times than this. |
| `limit` | `25` | Cap the phrases returned. Summary counts ignore it. |
| `collapse` | `1` | Drop a span that a longer span covers **and** whose positions are a subset of that longer span's. Set `0` to see every span. |
| `official` | `1` | Include the official mutashābihāt section and its pegs. Set `0` to skip it. |

Errors are JSON: `400` for a parameter the caller can fix, `404` for a route or
an āyah that does not exist.

### Response shape

```jsonc
{
  "query":  { "verse_key": "2:25", "surah_name_ar": "…", "page": 5, "juz": 1,
              "text": "…", "words": [{ "word_id": 327, "text": "…", "repeated": true }] },
  "params": { "scope": "full", "min_len": 0, "…": "…" },
  "counts": { "matches": 10, "returned": 10, "with_dabit": 1,
              "other_positions": 156, "distinct_ayat": 78 },
  "matches": [{
    "group_id": 2447, "span_len": 3, "occurrence_count": 6,
    "span_text": "…", "span_tokens": ["…"],
    "here":      { /* the position inside the queried āyah */ },
    "elsewhere": [ /* every other position */ ],
    "positions": [ /* both, in muṣḥaf order, each flagged is_query */ ],
    "dawabit":   [{ "rule_code": "MAJORITY", "strength": 0.7,
                    "text_ar": "…", "evidence": { /* payload from apply_rules */ } }]
  }]
}
```

Each position carries `verse_key`, `page`, `line`, `juz`, `span_text`, the token
`before` and `after` the span (`null` at a sūrah boundary), and `ayat` — the full
word list of the āyah(s) it sits in, each word flagged `in_span`. That last field
is what lets the page show the similar āyah in full with the shared part dimmed.

Ranking: phrases with a verified ḍābiṭ first (strongest first), then the longest
span, then the most positions.

### The `official` section

Present when `pipeline.official` and `pipeline.pegs` have run (`params.official`
says whether it is). One entry per curated QUL mutashābih phrase touching the
āyah:

```jsonc
{
  "phrase_id": 16345, "text_ar": "…", "span_len": 4,
  "set_count": 89, "official_count": 62, "exact_count": 89, "surah_count": 20,
  "here":      [ { /* the position inside this āyah, with its peg */ } ],
  "elsewhere": [ { /* every sibling, each with its own peg */ } ]
}
```

Each position adds `pos_id`, `in_official`, `in_exact`, `group_id`, `link`, and
`peg`:

```jsonc
"peg": { "kind": "CUE_BEFORE", "cue_ar": "تَكْفُرُونِ", "cue_window": 1,
         "continuation_ar": "ٱسْتَعِينُوا۟", "continuation_unique": true,
         "strength": 0.95, "text_ar": "ما قبله (…) وحده من بين 89 مواضع…",
         "evidence": { /* everything the sentence was built from */ } }
```

`kind` is one of `CUE_BEFORE`, `SOLE_IN_SURAH`, `ORDINAL_IN_SURAH`. What each
means, and why a unique *following* word is not among them, is in
[PEGS.md](PEGS.md).

## What it does not do

- No new analysis. Every phrase, count, and ḍābiṭ is read from the tables
  `pipeline.pass_a` and `pipeline.apply_rules` wrote.
- No Qur'anic text of its own. Arabic is copied out of `words.text_uthmani` and
  ḍābiṭ sentences out of `dawabit.text_ar`.
- No claim about meaning. A ḍābiṭ says where a wording sits, not why.
- The `matches` section is this project's own pass-A detection. The `official`
  section is the curated QUL list (resource 73), bound to those groups by
  `pipeline.official`. Resource 74 is ingested into `similar_ayahs` but not yet
  surfaced.

## Tests

```bash
python -m pytest tests/ -q
```

They run against the real `data/quran.db` and skip if it is not built.
