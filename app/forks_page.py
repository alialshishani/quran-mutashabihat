"""The forks page: the official mutashābihāt, and only those.

One card per curated phrase. The road is the wording every position shares; the
fork is the first word where they stop agreeing; each branch is one way out,
with the positions that take it and the cue that tells you you are on it.

Nothing on this page comes from the pass-A repeated-span detection. It is the
official list, bound to the corpus and shaped by `pipeline.forks`.
"""
from __future__ import annotations

from app.page import CSS as BASE_CSS
from app.page import FONTS

CSS = (
    BASE_CSS
    + """
.toolbar {
  display:flex; flex-wrap:wrap; gap:.75rem 1rem; align-items:end; margin:2rem 0 1rem;
  background:var(--surface); border:1px solid var(--rule); border-radius:12px;
  padding:1rem 1.1rem; box-shadow:var(--shadow);
}
.toolbar > div { flex:1 1 9rem; min-width:8rem; }
.toolbar > div.wide { flex:2 1 14rem; }
.toolbar input[type=text] {
  width:100%; padding:.55rem .65rem; font:inherit; color:var(--ink);
  background:var(--ground); border:1px solid var(--rule); border-radius:8px;
  font-family:"IBM Plex Sans Arabic","IBM Plex Sans",sans-serif;
}

.shapebar { display:flex; flex-wrap:wrap; gap:.4rem; margin:0 .1rem 1.5rem; }
.shapebar button {
  background:var(--surface); color:var(--ink-soft); border:1px solid var(--rule);
  border-radius:999px; padding:.3rem .8rem; font-size:.8rem; font-weight:400;
}
.shapebar button[aria-pressed="true"] {
  background:var(--accent); border-color:var(--accent); color:var(--ground); font-weight:500;
}
.shapebar button .n { font-family:"IBM Plex Mono",monospace; font-size:.72rem; opacity:.75; }

.road { background:var(--surface-sunk); border-radius:8px; padding:.5rem .95rem .7rem; }
.road-label { font-size:.66rem; letter-spacing:.1em; text-transform:uppercase; color:var(--ink-mute); }
.road-tail { color:var(--ink-mute); }

.fork { margin-top:.9rem; border-inline-start:2px solid var(--rule); padding-inline-start:.9rem; }
.branch {
  display:grid; grid-template-columns:auto 1fr; gap:.2rem .9rem; align-items:baseline;
  padding:.55rem 0; border-bottom:1px solid var(--rule-soft);
}
.branch:last-child { border-bottom:0; }
.branch-word {
  font-family:"Amiri Quran", serif; direction:rtl; font-size:1.35rem; line-height:1.9;
  background:var(--vary-bg); color:var(--vary-ink); border-radius:4px; padding:0 .3em;
  box-shadow:inset 0 -2px 0 var(--vary-edge); white-space:nowrap;
}
.branch.most .branch-word { background:var(--accent-soft); color:var(--accent); box-shadow:none; }
.branch-end { font-family:"IBM Plex Mono",monospace; font-size:.75rem; color:var(--ink-mute); }
.branch-side { display:flex; flex-wrap:wrap; gap:.3rem .45rem; align-items:baseline; }
.branch-count {
  font-family:"IBM Plex Mono",monospace; font-size:.7rem; color:var(--ink-mute);
  white-space:nowrap;
}
.where {
  font-family:"IBM Plex Sans Arabic",sans-serif; font-size:.86rem; color:var(--ink-soft);
  background:var(--surface-sunk); border-radius:6px; padding:.05rem .45rem; white-space:nowrap;
}
.where .k { font-family:"IBM Plex Mono",monospace; font-size:.72rem; color:var(--ink-mute); }
.where.only { background:var(--vary-bg); color:var(--vary-ink); }

.shape-badge { font-weight:500; }
.shape-all_but_one { color:var(--vary-ink); background:var(--vary-bg); border-color:transparent; }
.shape-two_way { color:var(--accent); background:var(--accent-soft); border-color:transparent; }

.pager { display:flex; gap:.75rem; align-items:center; justify-content:center; margin:2rem 0 0; }
.pager .count { font-size:.85rem; color:var(--ink-mute); }
nav.pages { display:flex; gap:1rem; align-items:center; font-size:.85rem; margin-bottom:1.5rem; }
nav.pages a { text-decoration:none; }
nav.pages .here { color:var(--ink-mute); }
"""
)

JS = r"""
const $ = (s) => document.querySelector(s);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
};

const SHAPES = [
  ["", "every fork"],
  ["all_but_one", "all but one"],
  ["two_way", "two ways"],
  ["many", "many ways"],
  ["no_fork", "no fork"],
];
const SHAPE_NOTE = {
  all_but_one: "one position leaves the road the others take",
  two_way: "the road splits in two",
  many: "more than two ways out",
  no_fork: "the positions never disagree after the phrase",
};

let STATE = { shape: "", min_positions: 2, surah: "", q: "", sort: "useful", offset: 0, limit: 25 };
let SURAHS = [];

function chip(text, cls) {
  return el("span", "chip" + (cls ? " " + cls : ""), text);
}

function whereChip(position, only) {
  const box = el("span", "where" + (only ? " only" : ""));
  box.appendChild(document.createTextNode(position.surah_name_ar + " "));
  const k = el("span", "k", position.verse_key);
  box.appendChild(k);
  const link = el("a", null, "");
  box.appendChild(link);
  box.title = `page ${position.page} · juz' ${position.juz}`;
  box.style.cursor = "pointer";
  box.addEventListener("click", () => {
    window.open("/#" + position.verse_key, "_blank");
  });
  return box;
}

function branchRow(branch, phrase) {
  const row = el("div", "branch" + (branch.is_largest && phrase.branch_count > 1 ? " most" : ""));
  if (branch.ends_surah) {
    row.appendChild(el("span", "branch-end", "— sūrah ends"));
  } else {
    row.appendChild(el("span", "branch-word", branch.token_ar));
  }

  const side = el("div", "branch-side");
  const only = branch.position_count === 1 && phrase.position_count > 2;
  side.appendChild(
    el(
      "span",
      "branch-count",
      branch.position_count === 1 ? "1 position" : `${branch.position_count} positions`
    )
  );
  for (const position of branch.positions.slice(0, 14)) {
    side.appendChild(whereChip(position, only));
  }
  if (branch.positions.length > 14) {
    side.appendChild(
      el("span", "branch-count", `+${branch.positions.length - 14} more`)
    );
  }
  row.appendChild(side);
  return row;
}

function forkCard(phrase) {
  const card = el("div", "group");

  const head = el("div", "group-head");
  head.appendChild(chip(SHAPE_NOTE[phrase.shape] || phrase.shape, "shape-badge shape-" + phrase.shape));
  head.appendChild(chip(`${phrase.position_count} positions`, "on"));
  head.appendChild(chip(`${phrase.branch_count} ways`));
  head.appendChild(chip(`${phrase.surah_count} sūrahs`));
  if (phrase.shared_after) {
    const c = chip(`+${phrase.shared_after} shared before the fork`);
    c.title =
      "The positions keep saying the same words for this many more words past " +
      "the listed phrase before they diverge.";
    head.appendChild(c);
  }
  card.appendChild(head);

  const road = el("div", "road");
  road.appendChild(el("div", "road-label", "The road"));
  const text = el("div", "arabic");
  text.appendChild(document.createTextNode(phrase.phrase_ar + " "));
  if (phrase.road_tail_ar) {
    text.appendChild(el("span", "road-tail", phrase.road_tail_ar));
  }
  road.appendChild(text);
  card.appendChild(road);

  const fork = el("div", "fork");
  for (const branch of phrase.branches) fork.appendChild(branchRow(branch, phrase));
  card.appendChild(fork);

  const details = el("details", "siblings");
  details.appendChild(el("summary", null, "The cue at each position"));
  details.addEventListener(
    "toggle",
    async () => {
      if (!details.open || details.dataset.loaded) return;
      details.dataset.loaded = "1";
      const res = await fetch("/api/official/" + phrase.phrase_id);
      const full = await res.json();
      const body = el("div", "positions");
      for (const branch of full.branches) {
        for (const position of branch.positions) {
          const row = el("div", "pos");
          const meta = el("div", "pos-meta");
          meta.appendChild(el("div", "pos-name", position.surah_name_ar));
          meta.appendChild(
            el("div", "ref", `${position.verse_key} · page ${position.page} · juz' ${position.juz}`)
          );
          row.appendChild(meta);
          const side = el("div");
          if (position.peg) {
            const peg = el("div", "peg sibling");
            peg.appendChild(el("div", "peg-text", position.peg.text_ar));
            side.appendChild(peg);
          }
          for (const ayah of position.ayat) {
            const line = el("div", "arabic small");
            for (const word of ayah.words) {
              const token = el("span", null, word.text);
              if (word.in_span) token.className = "tok-shared";
              else if (word.word_id === position.start_word_id - 1) token.className = "tok-vary";
              line.appendChild(token);
              line.appendChild(document.createTextNode(" "));
            }
            side.appendChild(line);
          }
          row.appendChild(side);
          body.appendChild(row);
        }
      }
      details.appendChild(body);
    },
    { once: false }
  );
  card.appendChild(details);
  return card;
}

function renderShapeBar(byShape) {
  const bar = $("#shapes");
  bar.textContent = "";
  for (const [value, label] of SHAPES) {
    const n = value ? byShape[value] || 0 : Object.values(byShape).reduce((a, b) => a + b, 0);
    const b = el("button", null, label + " ");
    b.appendChild(el("span", "n", String(n)));
    b.setAttribute("aria-pressed", String(STATE.shape === value));
    b.addEventListener("click", () => {
      STATE.shape = value;
      STATE.offset = 0;
      run();
    });
    bar.appendChild(b);
  }
}

function render(data) {
  const out = $("#out");
  out.textContent = "";
  const { total, returned } = data.counts;

  if (!returned) {
    const note = el("div", "note");
    note.textContent = "No fork matches these filters.";
    out.appendChild(note);
    return;
  }

  for (const phrase of data.phrases) out.appendChild(forkCard(phrase));

  const pager = el("div", "pager");
  const back = el("button", "ghost", "← previous");
  back.disabled = STATE.offset === 0;
  back.addEventListener("click", () => {
    STATE.offset = Math.max(0, STATE.offset - STATE.limit);
    run();
  });
  const forward = el("button", "ghost", "next →");
  forward.disabled = STATE.offset + returned >= total;
  forward.addEventListener("click", () => {
    STATE.offset += STATE.limit;
    run();
  });
  pager.appendChild(back);
  pager.appendChild(
    el("span", "count", `${STATE.offset + 1}–${STATE.offset + returned} of ${total}`)
  );
  pager.appendChild(forward);
  out.appendChild(pager);
}

async function run() {
  const params = new URLSearchParams({
    shape: STATE.shape,
    min_positions: STATE.min_positions,
    sort: STATE.sort,
    limit: STATE.limit,
    offset: STATE.offset,
  });
  if (STATE.surah) params.set("surah", STATE.surah);
  if (STATE.q) params.set("q", STATE.q);

  $("#out").setAttribute("aria-busy", "true");
  try {
    const res = await fetch("/api/official?" + params.toString());
    const data = await res.json();
    if (!res.ok) {
      $("#out").textContent = "";
      const note = el("div", "note err");
      note.textContent = data.error || `request failed (${res.status})`;
      $("#out").appendChild(note);
      return;
    }
    renderShapeBar(data.counts.by_shape);
    render(data);
    history.replaceState(null, "", "?" + params.toString());
  } finally {
    $("#out").removeAttribute("aria-busy");
  }
}

async function loadSurahs() {
  SURAHS = await (await fetch("/api/surahs")).json();
  const sel = $("#surah");
  for (const s of SURAHS) {
    const o = el("option", null, `${s.surah}. ${s.name_ar}`);
    o.value = s.surah;
    sel.appendChild(o);
  }
}

function fromQuery() {
  const params = new URLSearchParams(location.search);
  for (const key of ["shape", "sort", "q"]) {
    if (params.has(key)) STATE[key] = params.get(key);
  }
  for (const key of ["min_positions", "offset", "limit"]) {
    if (params.has(key)) STATE[key] = Number(params.get(key));
  }
  if (params.has("surah")) STATE.surah = params.get("surah");
  $("#sort").value = STATE.sort;
  $("#min_positions").value = STATE.min_positions;
  $("#q").value = STATE.q;
  $("#surah").value = STATE.surah;
}

window.addEventListener("DOMContentLoaded", async () => {
  await loadSurahs();
  fromQuery();
  $("#sort").addEventListener("change", () => {
    STATE.sort = $("#sort").value;
    STATE.offset = 0;
    run();
  });
  $("#min_positions").addEventListener("change", () => {
    STATE.min_positions = Number($("#min_positions").value) || 2;
    STATE.offset = 0;
    run();
  });
  $("#surah").addEventListener("change", () => {
    STATE.surah = $("#surah").value;
    STATE.offset = 0;
    run();
  });
  let timer = null;
  $("#q").addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      STATE.q = $("#q").value.trim();
      STATE.offset = 0;
      run();
    }, 250);
  });
  run();
});
"""


def html() -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Forks in the road</title>
<link rel="stylesheet" href="{FONTS}">
<style>{CSS}</style>
</head>
<body>
<div class="wrap">
  <nav class="pages">
    <a href="/">Look up an āyah</a>
    <span class="here">·</span>
    <span class="here">Forks in the road</span>
    <span class="here">·</span>
    <a href="/mushaf">The muṣḥaf</a>
  </nav>

  <header>
    <div class="eyebrow">Official mutashābihāt · QUL resource 73</div>
    <h1>Forks in the road</h1>
    <p class="standfirst">A stretch of wording you have recited before, and then the
    point where it goes two ways. Every phrase here comes from the curated
    mutashābihāt list — no repeated-word detection of ours is on this page.
    The road is what the positions share; the highlighted word is where they part.</p>
  </header>

  <div class="toolbar">
    <div>
      <label for="sort">Order</label>
      <select id="sort">
        <option value="useful">cheapest to hold</option>
        <option value="positions">most positions</option>
        <option value="branches">most ways out</option>
        <option value="surahs">most sūrahs</option>
      </select>
    </div>
    <div>
      <label for="min_positions">Min positions</label>
      <input type="number" id="min_positions" min="2" max="99" value="2">
    </div>
    <div>
      <label for="surah">In sūrah</label>
      <select id="surah"><option value="">any</option></select>
    </div>
    <div class="wide">
      <label for="q">Contains</label>
      <input type="text" id="q" placeholder="اكتب جزءًا من العبارة" dir="rtl">
    </div>
  </div>

  <div class="shapebar" id="shapes"></div>

  <div id="out"></div>

  <footer>
    <div><strong>الضوابط وسيلة حفظ لا تفسير.</strong> A fork says where a wording
    parts from another, never why it is worded that way.</div>
    <div>Phrases are QUL resource 73, bound to the corpus by
    <code>pipeline/official.py</code> and shaped by <code>pipeline/forks.py</code>.
    Positions include every exact repeat the muṣḥaf carries, not only those the
    list names, because a fork verified against a partial set is a fork that
    fails where it was never checked. Qur'anic text is served byte-for-byte from
    the Uthmānī word-by-word resource. JSON:
    <code>/api/official?shape=all_but_one</code>.</div>
  </footer>
</div>
<script>{JS}</script>
</body>
</html>
"""
