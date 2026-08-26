"""The single page served at `/`.

Design tokens are the ones `pipeline.report` already uses, so the interactive
lookup and the static review report read as one thing. All Qur'anic text on the
page arrives from the API, which copies it byte-for-byte out of the database;
the page never composes Arabic Qur'anic text of its own.
"""
from __future__ import annotations

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
  --ground:#FCFCFA; --surface:#FFFFFF; --surface-sunk:#F3F4F0;
  --ink:#191C19; --ink-soft:#4A5049; --ink-mute:#767C74;
  --rule:#DFE2DC; --rule-soft:#ECEEE9;
  --accent:#16584A; --accent-soft:#E4EFEA;
  --vary-bg:#FBEFD2; --vary-ink:#6B4708; --vary-edge:#D8A93C;
  --shadow:0 1px 2px rgba(25,28,25,.05), 0 8px 24px -16px rgba(25,28,25,.25);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ground:#101310; --surface:#171B17; --surface-sunk:#1E231E;
    --ink:#E8EBE6; --ink-soft:#B3BAB1; --ink-mute:#7F877E;
    --rule:#2A302A; --rule-soft:#232823;
    --accent:#6FC2A8; --accent-soft:#1B2E28;
    --vary-bg:#33280E; --vary-ink:#F0CE7E; --vary-edge:#8A6C22;
    --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px -16px rgba(0,0,0,.8);
  }
}
:root[data-theme="dark"] {
  --ground:#101310; --surface:#171B17; --surface-sunk:#1E231E;
  --ink:#E8EBE6; --ink-soft:#B3BAB1; --ink-mute:#7F877E;
  --rule:#2A302A; --rule-soft:#232823;
  --accent:#6FC2A8; --accent-soft:#1B2E28;
  --vary-bg:#33280E; --vary-ink:#F0CE7E; --vary-edge:#8A6C22;
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 8px 24px -16px rgba(0,0,0,.8);
}

* { box-sizing:border-box; }
body {
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"IBM Plex Sans", system-ui, sans-serif; font-size:15px; line-height:1.6;
  -webkit-font-smoothing:antialiased;
}
.wrap { max-width:64rem; margin:0 auto; padding:3rem 1.25rem 5rem; }

.eyebrow {
  font-family:"IBM Plex Mono", monospace; font-size:.7rem;
  letter-spacing:.14em; text-transform:uppercase; color:var(--accent);
}
h1 {
  font-family:Newsreader, Georgia, serif; font-size:clamp(1.9rem,4.2vw,2.7rem);
  font-weight:500; line-height:1.12; margin:.4rem 0 .6rem; letter-spacing:-.015em;
}
.standfirst { color:var(--ink-soft); max-width:44rem; margin:0; }

form.query {
  display:grid; gap:.75rem 1rem; align-items:end; margin:2rem 0 1rem;
  grid-template-columns:minmax(11rem,1.6fr) minmax(6rem,.7fr) auto;
  background:var(--surface); border:1px solid var(--rule); border-radius:12px;
  padding:1.1rem 1.2rem; box-shadow:var(--shadow);
}
@media (max-width:640px){ form.query { grid-template-columns:1fr 1fr; } form.query .go { grid-column:1/-1; } }
label { display:block; font-size:.68rem; letter-spacing:.1em; text-transform:uppercase;
        color:var(--ink-mute); margin-bottom:.35rem; }
select, input[type=number] {
  width:100%; padding:.55rem .65rem; font:inherit; color:var(--ink);
  background:var(--ground); border:1px solid var(--rule); border-radius:8px;
}
select { font-family:"IBM Plex Sans Arabic","IBM Plex Sans",sans-serif; }
button {
  padding:.6rem 1.3rem; font:inherit; font-weight:500; cursor:pointer;
  color:var(--ground); background:var(--accent); border:1px solid var(--accent);
  border-radius:8px;
}
button.ghost { color:var(--accent); background:transparent; }
button:disabled { opacity:.55; cursor:progress; }

.opts { display:flex; flex-wrap:wrap; gap:1.25rem; align-items:center;
        font-size:.8rem; color:var(--ink-mute); margin:0 .2rem 2rem; }
.opts label { display:inline; text-transform:none; letter-spacing:0; font-size:.8rem; margin:0; }
.opts input[type=number] { width:4.2rem; display:inline-block; padding:.25rem .4rem; }
.opts select { width:auto; display:inline-block; padding:.25rem .4rem; }

.stats { display:grid; gap:1px; margin:0 0 2rem;
  grid-template-columns:repeat(auto-fit,minmax(8rem,1fr));
  background:var(--rule); border:1px solid var(--rule); border-radius:10px; overflow:hidden; }
.stat { background:var(--surface); padding:.85rem 1rem; }
.stat dt { font-size:.66rem; letter-spacing:.1em; text-transform:uppercase; color:var(--ink-mute); margin:0 0 .25rem; }
.stat dd { margin:0; font-size:1.35rem; font-weight:500; font-variant-numeric:tabular-nums; }
.stat dd .unit { font-size:.85rem; color:var(--ink-mute); font-weight:400; }

.arabic {
  font-family:"Amiri Quran", serif; direction:rtl; text-align:right;
  font-size:1.5rem; line-height:2.35; word-spacing:.06em;
}
.arabic.small { font-size:1.22rem; line-height:2.15; }
.ar-ui { font-family:"IBM Plex Sans Arabic", sans-serif; direction:rtl; text-align:right; }

.tok-shared { color:var(--ink-mute); }
.tok-vary { background:var(--vary-bg); color:var(--vary-ink);
            box-shadow:inset 0 -2px 0 var(--vary-edge); border-radius:3px; padding:0 .12em; }
.tok-hit { color:var(--ink); background:var(--accent-soft); border-radius:3px; padding:0 .12em; }
.tok-adj { box-shadow:none; border-bottom:1px dashed var(--vary-edge); opacity:.9; }
.tok-none { font-family:"IBM Plex Mono",monospace; font-size:.72rem; color:var(--ink-mute); }

.ayah-card { background:var(--surface); border:1px solid var(--rule); border-radius:12px;
             padding:1.2rem 1.4rem; box-shadow:var(--shadow); margin-bottom:2rem; }
.ayah-head { display:flex; flex-wrap:wrap; gap:.5rem; align-items:center; margin-bottom:.4rem; }

.chip { font-family:"IBM Plex Mono",monospace; font-size:.7rem; color:var(--ink-soft);
        background:var(--surface-sunk); border:1px solid var(--rule-soft);
        border-radius:999px; padding:.15rem .55rem; white-space:nowrap; }
.chip.on { color:var(--accent); background:var(--accent-soft); border-color:transparent; }
.chip.flag { color:var(--vary-ink); background:var(--vary-bg); border-color:transparent; }
.chip.name { font-family:"IBM Plex Sans Arabic",sans-serif; font-size:.85rem; }

h2.section { font-family:Newsreader,Georgia,serif; font-weight:500; font-size:1.4rem;
             margin:2.5rem 0 .3rem; }
.section-note { color:var(--ink-mute); font-size:.85rem; margin:0 0 1.25rem; max-width:44rem; }

.group { background:var(--surface); border:1px solid var(--rule); border-radius:12px;
         padding:1.1rem 1.25rem 1.25rem; margin-bottom:1.25rem; box-shadow:var(--shadow); }
.group-head { display:flex; flex-wrap:wrap; gap:.4rem; align-items:center; margin-bottom:.75rem; }
.frame { background:var(--surface-sunk); border-radius:8px; padding:.5rem .9rem .7rem; margin-bottom:.9rem; }
.frame-label { font-size:.66rem; letter-spacing:.1em; text-transform:uppercase; color:var(--ink-mute); }

.dabit { border-inline-start:3px solid var(--accent); background:var(--accent-soft);
         border-radius:0 8px 8px 0; padding:.6rem .9rem; margin:.9rem 0 .2rem; }
.dabit-code { font-family:"IBM Plex Mono",monospace; font-size:.68rem; letter-spacing:.08em;
              text-transform:uppercase; color:var(--accent); margin-bottom:.25rem; }
.dabit-text { font-family:"IBM Plex Sans Arabic",sans-serif; direction:rtl; text-align:right;
              font-size:1.02rem; line-height:1.95; }

.peg { border-inline-start:3px solid var(--vary-edge); background:var(--vary-bg);
       border-radius:0 8px 8px 0; padding:.6rem .9rem; margin:.9rem 0 .2rem; }
.peg-code { font-family:"IBM Plex Mono",monospace; font-size:.68rem; letter-spacing:.08em;
            text-transform:uppercase; color:var(--vary-ink); margin-bottom:.25rem; }
.peg-text { font-family:"IBM Plex Sans Arabic",sans-serif; direction:rtl; text-align:right;
            font-size:1.02rem; line-height:1.95; color:var(--vary-ink); }
.peg.sibling { border-inline-start-width:2px; background:transparent; padding:.2rem .6rem; margin:.2rem 0 0; }
.peg.sibling .peg-text { font-size:.92rem; line-height:1.7; color:var(--ink-soft); }

details.siblings { margin-top:.6rem; }
details.siblings > summary { cursor:pointer; font-size:.8rem; color:var(--accent);
                             padding:.35rem 0; list-style-position:inside; }
details.siblings[open] > summary { margin-bottom:.4rem; }

.positions { border-top:1px solid var(--rule-soft); margin-top:.6rem; }
.pos { display:grid; gap:.15rem .9rem; grid-template-columns:11rem 1fr;
       padding:.7rem 0; border-bottom:1px solid var(--rule-soft); }
@media (max-width:700px){ .pos { grid-template-columns:1fr; } }
.pos:last-child { border-bottom:0; }
.pos.self { background:var(--accent-soft); border-radius:8px; padding-inline:.6rem; }
.pos-meta { display:flex; flex-direction:column; gap:.15rem; }
.pos-name { font-family:"IBM Plex Sans Arabic",sans-serif; font-size:1rem; }
.ref { font-family:"IBM Plex Mono",monospace; font-size:.72rem; color:var(--ink-mute); }
.pos-here { font-size:.66rem; letter-spacing:.1em; text-transform:uppercase; color:var(--accent); }

.note { background:var(--surface-sunk); border:1px solid var(--rule); border-radius:10px;
        padding:1rem 1.2rem; color:var(--ink-soft); margin:1.5rem 0; }
.err { border-color:var(--vary-edge); background:var(--vary-bg); color:var(--vary-ink); }
.legend { display:flex; flex-wrap:wrap; gap:1.1rem; font-size:.78rem; color:var(--ink-mute); margin:0 .2rem 1.5rem; }
.legend span.sw { display:inline-block; width:.8rem; height:.8rem; border-radius:3px; vertical-align:-1px; margin-inline-end:.35rem; }

footer { margin-top:3.5rem; padding-top:1.5rem; border-top:1px solid var(--rule);
         color:var(--ink-mute); font-size:.8rem; display:flex; flex-direction:column; gap:.6rem; }
code { font-family:"IBM Plex Mono",monospace; font-size:.85em; }
a { color:var(--accent); }
"""

JS = r"""
const $ = (s) => document.querySelector(s);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
};

let SURAHS = [];

async function loadSurahs() {
  const res = await fetch("/api/surahs");
  SURAHS = await res.json();
  const sel = $("#surah");
  for (const s of SURAHS) {
    const o = el("option", null, `${s.surah}. ${s.name_ar}`);
    o.value = s.surah;
    sel.appendChild(o);
  }
  sel.value = 2;
  syncAyahMax();
}

function syncAyahMax() {
  const s = SURAHS.find((x) => x.surah === Number($("#surah").value));
  const ayah = $("#ayah");
  ayah.max = s ? s.ayah_count : 286;
  $("#ayah-hint").textContent = s ? `1–${s.ayah_count}` : "";
  if (Number(ayah.value) > Number(ayah.max)) ayah.value = ayah.max;
}

// Render one āyah's words, dimming the shared span and marking the slots that
// vary on either side of it.
function ayahLine(words, start, end, cls) {
  const line = el("div", "arabic small " + (cls || ""));
  for (const w of words) {
    const tok = el("span", null, w.text);
    if (w.in_span || (w.word_id >= start && w.word_id <= end)) tok.className = "tok-shared";
    else if (w.word_id === start - 1 || w.word_id === end + 1) tok.className = "tok-vary";
    line.appendChild(tok);
    line.appendChild(document.createTextNode(" "));
  }
  return line;
}

function positionRow(pos, isSelf) {
  const row = el("div", "pos" + (isSelf ? " self" : ""));
  const meta = el("div", "pos-meta");
  meta.appendChild(el("div", "pos-name", pos.surah_name_ar));
  meta.appendChild(
    el("div", "ref", `${pos.verse_key} · page ${pos.page} · juz' ${pos.juz ?? "—"}`)
  );
  if (isSelf) meta.appendChild(el("div", "pos-here", "this āyah"));
  row.appendChild(meta);

  // When the span fills the āyah edge to edge, the word that varies sits in the
  // neighbouring āyah. It is the whole point of the comparison, so draw it —
  // marked as borrowed, not as part of this āyah.
  const body = el("div");
  pos.ayat.forEach((a, i) => {
    if (pos.ayat.length > 1) body.appendChild(el("div", "ref", a.verse_key));
    const line = ayahLine(a.words, pos.start_word_id, pos.end_word_id);
    const first = a.words[0], last = a.words[a.words.length - 1];
    if (i === 0 && pos.before && first.word_id === pos.start_word_id) {
      const tok = el("span", "tok-vary tok-adj", pos.before);
      tok.title = "last word of the preceding āyah";
      line.insertBefore(document.createTextNode(" "), line.firstChild);
      line.insertBefore(tok, line.firstChild);
    }
    if (i === pos.ayat.length - 1 && pos.after && last.word_id === pos.end_word_id) {
      const tok = el("span", "tok-vary tok-adj", pos.after);
      tok.title = "first word of the following āyah";
      line.appendChild(tok);
    }
    body.appendChild(line);
  });
  row.appendChild(body);
  return row;
}

const PEG_LABEL = {
  CUE_BEFORE: "cue · the word before",
  SOLE_IN_SURAH: "cue · only one in the sūrah",
  ORDINAL_IN_SURAH: "cue · counted within the sūrah",
};

function pegBox(peg, sibling) {
  const box = el("div", "peg" + (sibling ? " sibling" : ""));
  if (!sibling) {
    box.appendChild(
      el(
        "div",
        "peg-code",
        `${PEG_LABEL[peg.kind] || peg.kind} · strength ${peg.strength.toFixed(2)}`
      )
    );
  }
  box.appendChild(el("div", "peg-text", peg.text_ar));
  return box;
}

// One official mutashābih phrase: what tells this position from its siblings.
function officialCard(p) {
  const card = el("div", "group");
  const head = el("div", "group-head");
  head.appendChild(el("span", "chip", `phrase ${p.phrase_id}`));
  head.appendChild(el("span", "chip on", `${p.set_count} positions`));
  head.appendChild(el("span", "chip", `${p.surah_count} sūrahs`));
  if (p.exact_count > p.official_count) {
    const chip = el("span", "chip flag", `+${p.set_count - p.official_count} unlisted`);
    chip.title =
      `The official list names ${p.official_count} positions; the muṣḥaf carries ` +
      `${p.set_count}. The peg is verified against all of them.`;
    head.appendChild(chip);
  }
  card.appendChild(head);

  const frame = el("div", "frame");
  frame.appendChild(el("div", "frame-label", "Shared phrase · official mutashābih"));
  const ft = el("div", "arabic");
  ft.textContent = p.text_ar;
  frame.appendChild(ft);
  card.appendChild(frame);

  for (const here of p.here) {
    if (here.peg) card.appendChild(pegBox(here.peg, false));
    const positions = el("div", "positions");
    positions.appendChild(positionRow(here, true));
    card.appendChild(positions);
  }

  if (p.elsewhere.length) {
    const details = el("details", "siblings");
    details.appendChild(
      el("summary", null, `The other ${p.elsewhere.length} position(s), each with its own peg`)
    );
    const positions = el("div", "positions");
    for (const other of p.elsewhere) {
      positions.appendChild(positionRow(other, false));
      if (other.peg) positions.appendChild(pegBox(other.peg, true));
    }
    details.appendChild(positions);
    card.appendChild(details);
  }
  return card;
}

function groupCard(m) {
  const card = el("div", "group");
  const head = el("div", "group-head");
  head.appendChild(el("span", "chip", `group ${m.group_id}`));
  head.appendChild(el("span", "chip on", `${m.occurrence_count} positions`));
  head.appendChild(el("span", "chip", `${m.span_len} tokens`));
  if (m.dawabit.length) head.appendChild(el("span", "chip on", "ḍābiṭ"));
  if (m.cross_surah) head.appendChild(el("span", "chip flag", "crosses a sūrah seam"));
  card.appendChild(head);

  const frame = el("div", "frame");
  frame.appendChild(el("div", "frame-label", "Shared phrase"));
  const ft = el("div", "arabic");
  ft.textContent = m.span_text;
  frame.appendChild(ft);
  card.appendChild(frame);

  for (const d of m.dawabit) {
    const box = el("div", "dabit");
    box.appendChild(
      el("div", "dabit-code", `${d.rule_code} · strength ${d.strength.toFixed(2)}`)
    );
    box.appendChild(el("div", "dabit-text", d.text_ar));
    card.appendChild(box);
  }

  const positions = el("div", "positions");
  for (const p of m.positions) positions.appendChild(positionRow(p, p.is_query));
  card.appendChild(positions);
  return card;
}

function stat(label, value, unit) {
  const d = el("div", "stat");
  d.appendChild(el("dt", null, label));
  const dd = el("dd", null, String(value));
  if (unit) {
    const u = el("span", "unit", " " + unit);
    dd.appendChild(u);
  }
  d.appendChild(dd);
  return d;
}

function render(data) {
  const out = $("#out");
  out.textContent = "";
  const q = data.query;

  const card = el("div", "ayah-card");
  const head = el("div", "ayah-head");
  head.appendChild(el("span", "chip name", q.surah_name_ar));
  head.appendChild(el("span", "chip", q.verse_key));
  head.appendChild(el("span", "chip", `page ${q.page}`));
  head.appendChild(el("span", "chip", `juz' ${q.juz}`));
  card.appendChild(head);

  const line = el("div", "arabic");
  for (const w of q.words) {
    const tok = el("span", w.repeated ? "tok-hit" : null, w.text);
    line.appendChild(tok);
    line.appendChild(document.createTextNode(" "));
  }
  card.appendChild(line);
  out.appendChild(card);

  const stats = el("dl", "stats");
  if (data.params.official) {
    stats.appendChild(stat("Official phrases", data.counts.official_phrases));
    stats.appendChild(stat("Positions to tell apart", data.counts.official_positions));
  }
  stats.appendChild(stat("Repeated phrases", data.counts.matches));
  stats.appendChild(stat("With a ḍābiṭ", data.counts.with_dabit));
  stats.appendChild(stat("Other āyāt", data.counts.distinct_ayat));
  out.appendChild(stats);

  if (data.official && data.official.length) {
    out.appendChild(el("h2", "section", "Official mutashābihāt, and what pegs each one"));
    out.appendChild(
      el(
        "p",
        "section-note",
        "Curated phrases from the QUL mutashābihāt list. The peg under each is the cue " +
          "that identifies this position and no other in the set — verified against every " +
          "position the muṣḥaf actually carries, not only the ones the list names."
      )
    );
    for (const p of data.official) out.appendChild(officialCard(p));
  }

  if (!data.matches.length) {
    const n = el("div", "note");
    n.innerHTML =
      "<strong>No repeated phrase of this length touches this āyah.</strong> " +
      "Pass A records maximal spans of at least the configured token length that " +
      "occur two or more times. Lower the minimum span length to widen the net.";
    out.appendChild(n);
    return;
  }

  out.appendChild(el("h2", "section", "Phrases shared with other āyāt"));
  const shown =
    data.counts.returned < data.counts.matches
      ? `Showing ${data.counts.returned} of ${data.counts.matches}. `
      : "";
  out.appendChild(
    el(
      "p",
      "section-note",
      shown +
        "Phrases with a verified ḍābiṭ come first, then the longest. " +
        "Within each phrase, positions are listed in muṣḥaf order; the shared words " +
        "are dimmed and the word on each side — the part that actually varies — is highlighted."
    )
  );
  for (const m of data.matches) out.appendChild(groupCard(m));
}

function fail(message) {
  const out = $("#out");
  out.textContent = "";
  const n = el("div", "note err");
  n.textContent = message;
  out.appendChild(n);
}

async function run(push) {
  const surah = Number($("#surah").value);
  const ayah = Number($("#ayah").value);
  const params = new URLSearchParams({
    surah,
    ayah,
    scope: $("#scope").value,
    min_len: $("#min_len").value,
    min_occurrences: $("#min_occ").value,
    limit: $("#limit").value,
  });
  $("#go").disabled = true;
  $("#out").setAttribute("aria-busy", "true");
  try {
    const res = await fetch("/api/mutashabih?" + params.toString());
    const data = await res.json();
    if (!res.ok) {
      fail(data.error || `request failed (${res.status})`);
      return;
    }
    render(data);
    if (push) history.replaceState(null, "", "#" + surah + ":" + ayah);
  } catch (e) {
    fail("Could not reach the API: " + e.message);
  } finally {
    $("#go").disabled = false;
    $("#out").removeAttribute("aria-busy");
  }
}

function fromHash() {
  const m = /^#(\d+):(\d+)$/.exec(location.hash || "");
  if (!m) return false;
  $("#surah").value = m[1];
  syncAyahMax();
  $("#ayah").value = m[2];
  return true;
}

window.addEventListener("DOMContentLoaded", async () => {
  await loadSurahs();
  $("#surah").addEventListener("change", syncAyahMax);
  $("#form").addEventListener("submit", (e) => {
    e.preventDefault();
    run(true);
  });
  for (const id of ["#scope", "#min_len", "#min_occ", "#limit"]) {
    $(id).addEventListener("change", () => run(true));
  }
  window.addEventListener("hashchange", () => {
    if (fromHash()) run(false);
  });
  fromHash();
  run(true);
});
"""


def html() -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mutashābihāt lookup</title>
<link rel="stylesheet" href="{FONTS}">
<style>{CSS}</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="eyebrow">Pass A · exact repeats · R1 ḍawābiṭ</div>
    <h1>Which āyāt is this one confused with?</h1>
    <p class="standfirst">Pick a sūrah and an āyah. Every repeated phrase that touches
    that āyah comes back with all its other positions in the muṣḥaf — and, where one
    verified, the ḍābiṭ that tells them apart.</p>
  </header>

  <form class="query" id="form">
    <div>
      <label for="surah">Sūrah</label>
      <select id="surah"></select>
    </div>
    <div>
      <label for="ayah">Āyah <span class="ref" id="ayah-hint"></span></label>
      <input type="number" id="ayah" min="1" value="25" required>
    </div>
    <div class="go"><button id="go" type="submit">Look up</button></div>
  </form>

  <div class="opts">
    <span><label for="min_len">min span</label>
      <input type="number" id="min_len" min="1" max="20" value="3"> tokens</span>
    <span><label for="min_occ">min positions</label>
      <input type="number" id="min_occ" min="2" max="99" value="2"></span>
    <span><label for="limit">show</label>
      <input type="number" id="limit" min="1" max="200" value="25"> phrases</span>
    <span><label for="scope">scope</label>
      <select id="scope"><option value="full">full muṣḥaf</option>
      <option value="juz30">juz' 30</option><option value="juz10">juz' 10</option></select></span>
  </div>

  <div class="legend">
    <span><span class="sw" style="background:var(--accent-soft)"></span>part of a repeated phrase</span>
    <span><span class="sw" style="background:var(--vary-bg);box-shadow:inset 0 -2px 0 var(--vary-edge)"></span>the word that varies between positions</span>
    <span><span class="sw" style="background:var(--surface-sunk)"></span>shared wording</span>
    <span><span class="sw" style="background:var(--vary-bg);border-bottom:1px dashed var(--vary-edge)"></span>varying word, carried in from the neighbouring āyah</span>
  </div>

  <div id="out"></div>

  <footer>
    <div><strong>الضوابط وسيلة حفظ لا تفسير.</strong> The pegs here are memory aids.
    They say where a wording sits, never why it is worded that way.</div>
    <div>Qur'anic text is served byte-for-byte from the Uthmānī word-by-word resource;
    page and line come from the KFGQPC V1 layout. Sources and checksums:
    <code>data/raw/PROVENANCE.md</code>. Every count is computed from the database
    per request. JSON for this view:
    <code>/api/mutashabih?surah=2&amp;ayah=25</code>.</div>
  </footer>
</div>
<script>{JS}</script>
</body>
</html>
"""
