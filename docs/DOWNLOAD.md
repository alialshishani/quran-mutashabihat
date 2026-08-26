# Manual download checklist (M0)

QUL gates every dataset download behind a signed-in account (Google or GitHub OAuth).
Sign in once at `https://qul.tarteel.ai`, then visit each page below and click the
indicated button. Save every file into `data/raw/` **without renaming it**.

Prefer **SQLite** wherever offered; take JSON only where SQLite is unavailable.

| Save priority | Page | Button |
|---|---|---|
| 1 | https://qul.tarteel.ai/resources/quran-script/56 | Download sqlite |
| 2 | https://qul.tarteel.ai/resources/quran-script/54 | Download sqlite |
| 3 | https://qul.tarteel.ai/resources/mushaf-layout/15 | Download sqlite |
| 4 | https://qul.tarteel.ai/resources/mushaf-layout/10 | Download sqlite |
| 5 | https://qul.tarteel.ai/resources/quran-metadata/70 | Download sqlite |
| 6 | https://qul.tarteel.ai/resources/quran-metadata/69 | Download sqlite |
| 7 | https://qul.tarteel.ai/resources/quran-metadata/68 | Download sqlite |
| 8 | https://qul.tarteel.ai/resources/quran-metadata/67 | Download sqlite |
| 9 | https://qul.tarteel.ai/resources/quran-metadata/63 | Download sqlite |
| 10 | https://qul.tarteel.ai/resources/morphology/76 | Download sqlite |
| 11 | https://qul.tarteel.ai/resources/morphology/75 | Download sqlite |
| 12 | https://qul.tarteel.ai/resources/morphology/77 | Download sqlite |
| 13 | https://qul.tarteel.ai/resources/mutashabihat/73 | Download json |
| 14 | https://qul.tarteel.ai/resources/similar-ayah/74 | Download sqlite |

Optional but useful:
- https://qul.tarteel.ai/resources/quran-script/53 (Uthmani simple)
- https://qul.tarteel.ai/resources/quran-script/60 (Imlaei simple)

## Licence capture (required)

While on each page, copy the licence / attribution text shown for that resource into
`data/raw/PROVENANCE.md`. Brief §2 requires a recorded licence per resource, and the
pipeline should not consume a resource whose licence is unrecorded.

## After downloading

Run the intake script to hash every file, inspect its schema, and update PROVENANCE:

```bash
python -m scripts.intake
```

It writes SHA-256 sums, dumps each SQLite file's table/column layout, and **fails loudly
if a schema differs from what brief §3 expects** rather than improvising a mapping.
