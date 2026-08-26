"""Render a scope's groups as a reviewable HTML page.

Every Arabic Qur'anic token written here is copied byte-for-byte out of
`words.text_uthmani` (C1, C6). Every number is counted from the database at
render time (C2). The page makes no claim about why two wordings differ (C5).
"""
from __future__ import annotations

import argparse
import html
import json
import sqlite3
import sys
from pathlib import Path

from pipeline.pass_a import parse_scope

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "quran.db"

FONTS = (
    "https://fonts.googleapis.com/css2"
    "?family=Amiri+Quran"
    "&family=IBM+Plex+Sans:wght@400;500;600"
    "&family=IBM+Plex+Sans+Arabic:wght@400;500;600"
    "&family=IBM+Plex+Mono:wght@400;500"
    "&family=Newsreader:opsz,wght@6..72,400;6..72,500;6..72,600"
    "&display=swap"
)

CSS = """
:root {
  --ground: #FCFCFA;
  --surface: #FFFFFF;
  --surface-sunk: #F3F4F0;
  --ink: #191C19;
  --ink-soft: #4A5049;
  --ink-mute: #767C74;
  --rule: #DFE2DC;
  --rule-soft: #ECEEE9;
  --accent: #16584A;
  --accent-soft: #E4EFEA;
  --vary-bg: #FBEFD2;
  --vary-ink: #6B4708;
  --vary-edge: #D8A93C;
  --shadow: 0 1px 2px rgba(25, 28, 25, .05), 0 8px 24px -16px rgba(25, 28, 25, .25);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ground: #101310;
    --surface: #171B17;
    --surface-sunk: #1E231E;
    --ink: #E8EBE6;
    --ink-soft: #B3BAB1;
    --ink-mute: #7F877E;
    --rule: #2A302A;
    --rule-soft: #232823;
    --accent: #6FC2A8;
    --accent-soft: #1B2E28;
    --vary-bg: #33280E;
    --vary-ink: #F0CE7E;
    --vary-edge: #8A6C22;
    --shadow: 0 1px 2px rgba(0, 0, 0, .4), 0 8px 24px -16px rgba(0, 0, 0, .8);
  }
}
:root[data-theme="dark"] {
  --ground: #101310;
  --surface: #171B17;
  --surface-sunk: #1E231E;
  --ink: #E8EBE6;
  --ink-soft: #B3BAB1;
  --ink-mute: #7F877E;
  --rule: #2A302A;
  --rule-soft: #232823;
  --accent: #6FC2A8;
  --accent-soft: #1B2E28;
  --vary-bg: #33280E;
  --vary-ink: #F0CE7E;
  --vary-edge: #8A6C22;
  --shadow: 0 1px 2px rgba(0, 0, 0, .4), 0 8px 24px -16px rgba(0, 0, 0, .8);
}

* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--ground);
  color: var(--ink);
  font-family: "IBM Plex Sans", system-ui, sans-serif;
  font-size: 15px;
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
}
.wrap { max-width: 60rem; margin: 0 auto; padding: 3.5rem 1.5rem 5rem; }

header.masthead { display: flex; flex-direction: column; gap: .75rem; margin-bottom: 2.5rem; }
.eyebrow {
  font-family: "IBM Plex Mono", monospace;
  font-size: .7rem; letter-spacing: .14em; text-transform: uppercase;
  color: var(--accent);
}
h1 {
  font-family: Newsreader, Georgia, serif;
  font-size: clamp(2rem, 4.5vw, 2.9rem);
  font-weight: 500; line-height: 1.12; margin: 0; text-wrap: balance;
  letter-spacing: -.015em;
}
.standfirst { color: var(--ink-soft); max-width: 42rem; margin: 0; }

.stats {
  display: grid; gap: 1px; margin: 2.5rem 0 3rem;
  grid-template-columns: repeat(auto-fit, minmax(8.5rem, 1fr));
  background: var(--rule); border: 1px solid var(--rule);
  border-radius: 10px; overflow: hidden;
}
.stat { background: var(--surface); padding: .95rem 1.1rem; }
.stat dt {
  font-size: .68rem; letter-spacing: .1em; text-transform: uppercase;
  color: var(--ink-mute); margin: 0 0 .3rem;
}
.stat dd {
  margin: 0; font-family: "IBM Plex Mono", monospace;
  font-size: 1.35rem; font-variant-numeric: tabular-nums; color: var(--ink);
}
.stat dd .unit { font-size: .8rem; color: var(--ink-mute); }

.note {
  border-inline-start: 3px solid var(--accent);
  background: var(--accent-soft);
  padding: 1rem 1.15rem; border-radius: 0 8px 8px 0;
  margin: 0 0 3rem; color: var(--ink-soft);
}
.note strong { color: var(--ink); }

h2.section {
  font-family: Newsreader, Georgia, serif; font-weight: 500;
  font-size: 1.45rem; margin: 0 0 .4rem; letter-spacing: -.01em;
}
.section-note { color: var(--ink-mute); margin: 0 0 1.5rem; font-size: .92rem; }

.group { margin-bottom: 1.1rem; border: 1px solid var(--rule);
  border-radius: 12px; background: var(--surface); box-shadow: var(--shadow); overflow: hidden; }
.group-head {
  display: flex; flex-wrap: wrap; align-items: baseline; gap: .6rem;
  padding: .7rem 1.1rem; border-bottom: 1px solid var(--rule-soft);
  background: var(--surface-sunk);
}
.gid { font-family: "IBM Plex Mono", monospace; font-size: .75rem; color: var(--ink-mute); }
.chip {
  font-size: .7rem; letter-spacing: .04em; padding: .12rem .5rem;
  border-radius: 999px; border: 1px solid var(--rule);
  color: var(--ink-soft); background: var(--surface);
  font-variant-numeric: tabular-nums;
}
.chip.flag { border-color: var(--vary-edge); color: var(--vary-ink); background: var(--vary-bg); }

.frame { padding: 1.15rem 1.1rem .5rem; }
.frame-label {
  font-size: .68rem; letter-spacing: .1em; text-transform: uppercase;
  color: var(--ink-mute); margin-bottom: .5rem;
}
.arabic { font-family: "Amiri Quran", "Scheherazade New", serif; direction: rtl; }
.frame-text { font-size: 1.6rem; line-height: 2.1; color: var(--ink); }

.positions { padding: .25rem .4rem 1rem; overflow-x: auto; }
table { border-collapse: collapse; width: 100%; }
th {
  text-align: start; font-size: .66rem; letter-spacing: .09em;
  text-transform: uppercase; color: var(--ink-mute); font-weight: 500;
  padding: .45rem .7rem; border-bottom: 1px solid var(--rule-soft); white-space: nowrap;
}
td { padding: .5rem .7rem; border-bottom: 1px solid var(--rule-soft); vertical-align: middle; }
tr:last-child td { border-bottom: none; }
.ref {
  font-family: "IBM Plex Mono", monospace; font-size: .82rem;
  font-variant-numeric: tabular-nums; color: var(--ink-soft); white-space: nowrap;
}
.surah-name {
  font-family: "IBM Plex Sans Arabic", sans-serif; direction: rtl;
  font-size: .95rem; color: var(--ink); white-space: nowrap;
}
.line { direction: rtl; text-align: right; font-size: 1.35rem; line-height: 2; white-space: nowrap; }
.tok-shared { color: var(--ink-mute); }
.tok-vary {
  background: var(--vary-bg); color: var(--vary-ink);
  border-radius: 5px; padding: .05em .3em; box-decoration-break: clone;
}
.tok-none { color: var(--ink-mute); opacity: .5; font-family: "IBM Plex Mono", monospace; font-size: .8rem; }

.dabit { margin: 0 1.1rem 1.1rem; padding: .8rem 1rem; border-radius: 8px;
  background: var(--accent-soft); border: 1px solid var(--rule); }
.dabit-code { font-family: "IBM Plex Mono", monospace; font-size: .68rem;
  letter-spacing: .08em; color: var(--accent); margin-bottom: .35rem; }
.dabit-text { font-family: "IBM Plex Sans Arabic", sans-serif; direction: rtl;
  text-align: right; font-size: 1.02rem; color: var(--ink); }

footer {
  margin-top: 4rem; padding-top: 1.5rem; border-top: 1px solid var(--rule);
  color: var(--ink-mute); font-size: .85rem; display: flex;
  flex-direction: column; gap: .7rem;
}
footer code { font-family: "IBM Plex Mono", monospace; font-size: .8rem; color: var(--ink-soft); }
@media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
"""


def esc(text: str) -> str:
    return html.escape(text, quote=False)


def build(scope: str) -> str:
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

    words = {
        wid: (disp, surah)
        for wid, disp, surah in con.execute(
            "SELECT word_id, text_uthmani, surah FROM words"
        )
    }
    surah_names = dict(con.execute("SELECT surah, name_ar FROM surahs"))
    juz_of = dict(con.execute("SELECT verse_key, juz FROM ayahs"))

    all_groups = con.execute(
        "SELECT group_id, occurrence_count, span_len_min, span_len_max, kind, "
        "       needs_review, cross_surah "
        "FROM groups WHERE scope = ? "
        "ORDER BY occurrence_count DESC, span_len_max DESC, group_id",
        (scope,),
    ).fetchall()

    # Where rules fired, lead with those groups ranked by rule strength — a
    # verified peg is the product, and the unresolved tail is context.
    ranked = {
        gid: strength
        for gid, strength in con.execute(
            "SELECT d.group_id, MAX(d.strength) FROM dawabit d "
            "JOIN groups g ON g.group_id = d.group_id "
            "WHERE g.scope = ? GROUP BY d.group_id",
            (scope,),
        )
    }
    if ranked:
        groups = sorted(
            (g for g in all_groups if g[0] in ranked),
            key=lambda g: (-ranked[g[0]], -g[1], g[0]),
        )
    else:
        groups = all_groups

    dawabit: dict[int, list[tuple[str, str, float]]] = {}
    for gid, code, text_ar, strength in con.execute(
        "SELECT d.group_id, d.rule_code, d.text_ar, d.strength FROM dawabit d "
        "JOIN groups g ON g.group_id = d.group_id WHERE g.scope = ? "
        "ORDER BY d.strength DESC",
        (scope,),
    ):
        dawabit.setdefault(gid, []).append((code, text_ar, strength))

    juz = parse_scope(scope)
    if juz is None:
        scope_tokens = con.execute("SELECT COUNT(*) FROM words").fetchone()[0]
        scope_title = "the whole muṣḥaf"
        scope_range = "1:1 — 114:6"
        page_name = "Majority-Rule Ḍawābiṭ"
    else:
        scope_tokens = con.execute(
            "SELECT COUNT(*) FROM words w JOIN ayahs a "
            "ON a.surah = w.surah AND a.ayah = w.ayah WHERE a.juz = ?",
            (juz,),
        ).fetchone()[0]
        # Juz' 30 is universally called ʿAmma; the rest go by number.
        scope_title = "Juz' ʿAmma" if juz == 30 else f"Juz' {juz}"
        page_name = f"Repeated Phrases in {scope_title}"
        first_key, last_key = con.execute(
            "SELECT (SELECT verse_key FROM ayahs WHERE juz = ? "
            "        ORDER BY surah, ayah LIMIT 1), "
            "       (SELECT verse_key FROM ayahs WHERE juz = ? "
            "        ORDER BY surah DESC, ayah DESC LIMIT 1)",
            (juz, juz),
        ).fetchone()
        scope_range = f"{first_key} — {last_key}"
    occurrence_total = con.execute(
        "SELECT COUNT(*) FROM occurrences o JOIN groups g "
        "ON g.group_id = o.group_id WHERE g.scope = ?",
        (scope,),
    ).fetchone()[0]
    resolved = sum(1 for g in all_groups if g[5] == 0)

    parts: list[str] = [
        f"<title>{esc(page_name)}</title>",
        f'<link rel="stylesheet" href="{FONTS}">',
        f"<style>{CSS}</style>",
        '<div class="wrap">',
        '<header class="masthead">',
        f'<div class="eyebrow">Pass A · exact repeats · scope {esc(scope)}</div>',
        f"<h1>Repeated phrases in {esc(scope_title)}</h1>",
        f'<p class="standfirst">Every maximal repeated span in {esc(scope_title)} '
        f'<span class="ref">({esc(scope_range)})</span>, with the sūrahs it occurs '
        "in and the word on each side of it. The shared frame is dimmed; the words "
        "that vary between positions are highlighted.</p>",
        "</header>",
        '<dl class="stats">',
        f'<div class="stat"><dt>Tokens scanned</dt><dd>{scope_tokens:,}</dd></div>',
        f'<div class="stat"><dt>Groups</dt><dd>{len(all_groups):,}</dd></div>',
        f'<div class="stat"><dt>Positions</dt><dd>{occurrence_total:,}</dd></div>',
        f'<div class="stat"><dt>With a ḍābiṭ</dt><dd>{resolved:,}'
        f'<span class="unit"> / {len(all_groups):,}</span></dd></div>',
        "</dl>",
    ]

    if resolved == 0:
        parts.append(
            '<div class="note"><strong>No ḍābiṭ fired at this scope.</strong> '
            "Rule R1 (قاعدة الأغلبية) needs one wording to hold most positions of a "
            "phrase and another to hold one or two. A majority is a property of the "
            "whole muṣḥaf, so restricting the scan to a single juz' cuts most of a "
            "phrase's positions away and destroys the distribution R1 measures — "
            "a frame with four positions here may have twenty across the muṣḥaf. "
            "Run the same phrases at <code>--scope full</code> to see R1 fire. "
            "Nothing was loosened to force a rule at this scope.</div>"
        )

    parts += [
        f'<h2 class="section">{"Groups with a ḍābiṭ" if ranked else "Groups"}</h2>',
        f'<p class="section-note">'
        + (
            f"Showing the {len(groups):,} group(s) where a rule verified, strongest "
            f"first. The remaining {len(all_groups) - len(groups):,} carry a diff but "
            "no peg yet."
            if ranked
            else "Ordered by number of positions, then span length."
        )
        + " Positions are listed in muṣḥaf order.</p>",
    ]

    for gid, count, len_min, len_max, kind, needs_review, cross in groups:
        occurrences = con.execute(
            "SELECT start_word_id, end_word_id, verse_key, page "
            "FROM occurrences WHERE group_id = ? ORDER BY start_word_id",
            (gid,),
        ).fetchall()

        first_start, first_end, _, _ = occurrences[0]
        frame = " ".join(words[w][0] for w in range(first_start, first_end + 1))

        span_label = f"{len_min}" if len_min == len_max else f"{len_min}–{len_max}"
        parts += [
            '<div class="group">',
            '<div class="group-head">',
            f'<span class="gid">group {gid}</span>',
            f'<span class="chip">{count} positions</span>',
            f'<span class="chip">{span_label} tokens</span>',
            f'<span class="chip">{esc(kind)}</span>',
        ]
        if cross:
            parts.append('<span class="chip flag">crosses a sūrah seam</span>')
        parts += [
            "</div>",
            '<div class="frame">',
            '<div class="frame-label">Shared frame</div>',
            f'<div class="arabic frame-text">{esc(frame)}</div>',
            "</div>",
            '<div class="positions"><table>',
            "<thead><tr>"
            "<th>Sūrah</th><th>Āyah</th><th>Page</th><th>Juz'</th>"
            "<th>Preceded by · frame · followed by</th>"
            "</tr></thead><tbody>",
        ]

        for start, end, verse_key, page in occurrences:
            surah = int(verse_key.split(":")[0])
            left = words.get(start - 1)
            right = words.get(end + 1)
            left_tok = left[0] if left and left[1] == surah else None
            right_tok = right[0] if right and right[1] == surah else None
            shared = " ".join(words[w][0] for w in range(start, end + 1))

            # RTL: the preceding word sits to the right of the frame.
            cells = []
            if right_tok:
                cells.append(f'<span class="tok-vary">{esc(right_tok)}</span>')
            else:
                cells.append('<span class="tok-none">— āyah end</span>')
            cells.append(f'<span class="tok-shared">{esc(shared)}</span>')
            if left_tok:
                cells.append(f'<span class="tok-vary">{esc(left_tok)}</span>')
            else:
                cells.append('<span class="tok-none">āyah start —</span>')

            parts.append(
                "<tr>"
                f'<td class="surah-name">{esc(surah_names[surah])}</td>'
                f'<td class="ref">{esc(verse_key)}</td>'
                f'<td class="ref">{page}</td>'
                f'<td class="ref">{juz_of.get(verse_key, "")}</td>'
                f'<td class="arabic line">{" ".join(reversed(cells))}</td>'
                "</tr>"
            )

        parts.append("</tbody></table></div>")

        for code, text_ar, strength in dawabit.get(gid, []):
            parts += [
                '<div class="dabit">',
                f'<div class="dabit-code">{esc(code)} · strength {strength:.2f}</div>',
                f'<div class="dabit-text">{esc(text_ar)}</div>',
                "</div>",
            ]
        parts.append("</div>")

    parts += [
        "<footer>",
        "<div><strong>الضوابط وسيلة حفظ لا تفسير.</strong> The pegs on this page are "
        "memory aids. They say where a wording sits, never why it is worded that way, "
        "and they make no claim about meaning or wisdom.</div>",
        "<div>Qur'anic text is reproduced byte-for-byte from the Uthmānī word-by-word "
        "resource; page and line come from the KFGQPC V1 (1405H) layout. "
        "Sources and checksums: <code>data/raw/PROVENANCE.md</code>. Every count on "
        "this page is computed from the database at render time.</div>",
        "</footer>",
        "</div>",
    ]
    con.close()
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", default="juz30")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"missing {DB}")
    out = Path(args.out) if args.out else ROOT / "data" / "interim" / f"report_{args.scope}.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(build(args.scope), encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
