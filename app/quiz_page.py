"""The quiz page served at `/quiz`.

Questions come from `/api/quiz`; the page only shows them and keeps score. The
score lives in localStorage, so it is per browser and survives a reload.
"""
from __future__ import annotations

from app.page import CSS as BASE_CSS
from app.page import FONTS

CSS = (
    BASE_CSS
    + """
.kinds { display:flex; flex-wrap:wrap; gap:.4rem; margin:2rem 0 1rem; }
.kinds button {
  background:var(--surface); color:var(--ink-soft); border:1px solid var(--rule);
  border-radius:999px; padding:.35rem .9rem; font-size:.85rem; font-weight:400;
}
.kinds button[aria-pressed="true"] {
  background:var(--accent); border-color:var(--accent); color:var(--ground); font-weight:500;
}
.filters { display:flex; flex-wrap:wrap; gap:.75rem 1rem; align-items:end; margin:0 0 1.5rem;
  background:var(--surface); border:1px solid var(--rule); border-radius:12px;
  padding:1rem 1.1rem; box-shadow:var(--shadow); }
.filters > div { flex:1 1 9rem; min-width:8rem; }

.prompt { font-size:.8rem; letter-spacing:.1em; text-transform:uppercase; color:var(--ink-mute); margin-bottom:.4rem; }
.phrase { font-size:.85rem; color:var(--ink-mute); margin:.2rem 0 .6rem; }
.choices { display:grid; gap:.6rem; grid-template-columns:repeat(auto-fit,minmax(14rem,1fr)); margin-top:1rem; }
.choices button {
  text-align:start; background:var(--surface); color:var(--ink); border:1px solid var(--rule);
  font-weight:400; padding:.7rem 1rem; display:flex; gap:.7rem; align-items:baseline;
}
.choices button .key { font-family:"IBM Plex Mono",monospace; font-size:.72rem; color:var(--ink-mute); }
.choices button .lbl { flex:1; }
.choices button.ar .lbl { font-family:"IBM Plex Sans Arabic",sans-serif; direction:rtl; text-align:right; font-size:1.05rem; }
.choices button.verse .lbl { font-family:"Amiri Quran",serif; direction:rtl; text-align:right; font-size:1.15rem; line-height:2; }
.choices button.right { background:var(--accent-soft); border-color:var(--accent); color:var(--accent); }
.choices button.wrong { background:var(--vary-bg); border-color:var(--vary-edge); color:var(--vary-ink); }
.choices button:disabled { cursor:default; opacity:1; }
.verdict { margin-top:1rem; display:flex; flex-wrap:wrap; gap:.75rem; align-items:center; }
.verdict .ref { font-size:.85rem; }
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

const KINDS = [
  ["surah", "Which sūrah?", "Which sūrah is this āyah from?"],
  ["similar", "Which sūrah? (mutashābih)", "Which sūrah is this āyah from? The other choices share its wording."],
  ["next", "What comes next?", "Which āyah comes next?"],
  ["juz", "Which juz'?", "Which juz' is this āyah in?"],
];
let kind = "surah";
let current = null;
let score = { right: 0, total: 0, streak: 0 };
try { score = JSON.parse(localStorage.getItem("quiz-score")) || score; } catch (e) {}

function saveScore() {
  try { localStorage.setItem("quiz-score", JSON.stringify(score)); } catch (e) {}
  $("#s-right").textContent = score.right;
  $("#s-total").textContent = score.total;
  $("#s-pct").textContent = score.total ? Math.round(100 * score.right / score.total) + "%" : "–";
  $("#s-streak").textContent = score.streak;
}

function kindBar() {
  const bar = $("#kinds");
  for (const [k, name] of KINDS) {
    const b = el("button", null, name);
    b.type = "button";
    b.setAttribute("aria-pressed", String(k === kind));
    b.onclick = () => {
      kind = k;
      for (const x of bar.children) x.setAttribute("aria-pressed", "false");
      b.setAttribute("aria-pressed", "true");
      next();
    };
    bar.append(b);
  }
}

async function loadSurahs() {
  const surahs = await (await fetch("/api/surahs")).json();
  for (const id of ["#from", "#to"]) {
    const sel = $(id);
    for (const s of surahs) {
      const o = el("option", null, `${s.surah}. ${s.name_ar}`);
      o.value = s.surah;
      sel.append(o);
    }
  }
  $("#to").value = "114";
}

async function next() {
  const params = new URLSearchParams({ kind, from: $("#from").value || 1, to: $("#to").value || 114 });
  if ($("#juz").value) params.set("juz", $("#juz").value);
  const out = $("#out");
  const res = await fetch("/api/quiz?" + params);
  const data = await res.json();
  out.replaceChildren();
  if (!res.ok) { out.append(el("div", "note err", data.error)); current = null; return; }
  current = data;
  const card = el("div", "ayah-card");
  card.append(el("div", "prompt", KINDS.find((k) => k[0] === kind)[2]));
  if (kind === "next") {
    const head = el("div", "ayah-head");
    head.append(el("span", "chip name", data.ref.name_ar), el("span", "chip", `${data.ref.surah}:${data.ref.ayah}`));
    card.append(head);
  }
  card.append(el("div", "arabic", data.text));
  if (data.phrase) card.append(el("div", "phrase", "Shared phrase: "), el("div", "arabic small", data.phrase));
  const grid = el("div", "choices");
  data.choices.forEach((c, i) => {
    const b = el("button", kind === "next" ? "verse" : kind === "juz" ? "" : "ar");
    b.type = "button";
    b.append(el("span", "key", String(i + 1)), el("span", "lbl", c.label));
    b.onclick = () => answer(i);
    grid.append(b);
  });
  card.append(grid, el("div", "verdict"));
  out.append(card);
}

function answer(i) {
  if (!current || current.answered) return;
  current.answered = true;
  const ok = i === current.answer;
  score.total += 1;
  if (ok) { score.right += 1; score.streak += 1; } else { score.streak = 0; }
  saveScore();
  const buttons = document.querySelectorAll(".choices button");
  buttons.forEach((b, j) => {
    b.disabled = true;
    if (j === current.answer) b.classList.add("right");
    else if (j === i) b.classList.add("wrong");
  });
  const v = $(".verdict");
  const r = current.ref;
  v.append(el("strong", null, ok ? "Correct" : "Not quite"));
  v.append(el("span", "ref", `${r.name_ar} ${r.surah}:${r.ayah} · juz' ${r.juz} · page ${r.page}`));
  const look = el("a", null, "Its mutashābihāt");
  look.href = `/#${r.surah}:${r.ayah}`;
  const page = el("a", null, "On the page");
  page.href = `/mushaf#p=${r.page}&a=${r.surah}:${r.ayah}`;
  const go = el("button", null, "Next →");
  go.type = "button";
  go.onclick = next;
  v.append(look, page, go);
  go.focus();
}

document.addEventListener("keydown", (e) => {
  if (e.target.tagName === "SELECT" || e.target.tagName === "INPUT") return;
  const n = Number(e.key);
  if (n >= 1 && n <= 4 && current && !current.answered) answer(n - 1);
  else if ((e.key === "Enter" || e.key === " ") && current && current.answered) { e.preventDefault(); next(); }
});

$("#reset").onclick = () => { score = { right: 0, total: 0, streak: 0 }; saveScore(); };
for (const id of ["#from", "#to", "#juz"]) $(id).onchange = next;
kindBar();
saveScore();
loadSurahs().then(next);
"""


def html() -> str:
    juz_options = "".join(f'<option value="{j}">{j}</option>' for j in range(1, 31))
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mutashābihāt quiz</title>
<link rel="stylesheet" href="{FONTS}">
<style>{CSS}</style>
</head>
<body>
<div class="wrap">
  <nav class="pages">
    <a href="/">Look up an āyah</a>
    <span class="here">·</span>
    <a href="/official">Forks in the road</a>
    <span class="here">·</span>
    <a href="/mushaf">The muṣḥaf</a>
    <span class="here">·</span>
    <span class="here">Quiz</span>
  </nav>

  <header>
    <div class="eyebrow">Revision</div>
    <h1>Test yourself</h1>
    <p class="standfirst">An āyah, four choices. Narrow it to what you have memorised
    with the sūrah range or a juz'. Keys <code>1</code>–<code>4</code> answer,
    <code>Enter</code> moves on.</p>
  </header>

  <div class="kinds" id="kinds"></div>

  <div class="filters">
    <div><label for="from">From sūrah</label><select id="from"></select></div>
    <div><label for="to">To sūrah</label><select id="to"></select></div>
    <div><label for="juz">Juz'</label><select id="juz"><option value="">any</option>{juz_options}</select></div>
  </div>

  <dl class="stats">
    <div class="stat"><dt>Right</dt><dd id="s-right">0</dd></div>
    <div class="stat"><dt>Asked</dt><dd id="s-total">0</dd></div>
    <div class="stat"><dt>Score</dt><dd id="s-pct">–</dd></div>
    <div class="stat"><dt>Streak</dt><dd id="s-streak">0</dd></div>
  </dl>

  <div id="out"></div>

  <footer>
    <div><button class="ghost" id="reset" type="button">Reset score</button></div>
    <div>Qur'anic text is served byte-for-byte from the corpus. JSON:
    <code>/api/quiz?kind=surah&amp;from=78&amp;to=114</code>.</div>
  </footer>
</div>
<script>{JS}</script>
</body>
</html>
"""
