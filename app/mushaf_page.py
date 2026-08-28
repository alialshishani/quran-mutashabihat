"""The muṣḥaf page: the printed page reproduced, line for line.

Every line break, every heading line and every āyah marker on this page comes
from the KFGQPC layout table that `pipeline.layout` carried into the corpus, so
a page here holds exactly the words the printed page holds, in the same order,
broken at the same places. What the print cannot do is say which of its āyāt a
memoriser confuses with another: that is what the marks and the panel add.

The typeface is the one part that is not the muṣḥaf's own. KFGQPC sets each page
in a font cut for that page; those fonts are licensed separately and are not
vendored here, so the page asks for an installed muṣḥaf font first and falls
back to Amiri Quran. See docs/MUSHAF.md.

As everywhere else in `app/`, no Qur'anic text is composed here — every token,
the basmalah included, arrives from the API byte-for-byte out of the database.
"""
from __future__ import annotations

from app.page import FONTS

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

/* The muṣḥaf's own font if it is installed on this machine; the names are the
   ones the King Fahd Complex ships its Uthmanic Hafs faces under. */
@font-face {
  font-family:"Mushaf";
  src:local("KFGQPC HAFS Uthmanic Script"), local("KFGQPC Uthmanic Script HAFS"),
      local("UthmanicHafs1 Ver18"), local("KFGQPC Uthman Taha Naskh"),
      local("Al Qalam Quran Majeed"), local("me_quran");
  font-display:swap;
}

* { box-sizing:border-box; }
body {
  margin:0; background:var(--ground); color:var(--ink);
  font-family:"IBM Plex Sans", system-ui, sans-serif; font-size:15px; line-height:1.6;
  -webkit-font-smoothing:antialiased;
}
a { color:var(--accent); }
code { font-family:"IBM Plex Mono",monospace; font-size:.85em; }
.wrap { max-width:64rem; margin:0 auto; padding:1.5rem 1.25rem 4rem; }

nav.pages { display:flex; gap:1rem; align-items:center; font-size:.85rem; margin-bottom:1.25rem; }
nav.pages a { text-decoration:none; }
nav.pages .here { color:var(--ink-mute); }

/* -- the toolbar ---------------------------------------------------------- */

.bar {
  display:flex; flex-wrap:wrap; gap:.6rem .9rem; align-items:center;
  background:var(--surface); border:1px solid var(--rule); border-radius:12px;
  padding:.7rem .9rem; box-shadow:var(--shadow); margin-bottom:1.4rem;
}
.bar .grow { flex:1 1 auto; }
.bar label { font-size:.66rem; letter-spacing:.1em; text-transform:uppercase;
             color:var(--ink-mute); margin-inline-end:.35rem; }
.bar select, .bar input[type=number] {
  padding:.35rem .45rem; font:inherit; font-size:.9rem; color:var(--ink);
  background:var(--ground); border:1px solid var(--rule); border-radius:8px;
}
.bar select { font-family:"IBM Plex Sans Arabic","IBM Plex Sans",sans-serif; max-width:12rem; }
.bar input[type=number] { width:4.6rem; font-variant-numeric:tabular-nums; }
button {
  padding:.4rem .9rem; font:inherit; font-size:.9rem; font-weight:500; cursor:pointer;
  color:var(--ground); background:var(--accent); border:1px solid var(--accent);
  border-radius:8px;
}
button.ghost { color:var(--accent); background:transparent; }
button.ghost:disabled { opacity:.35; cursor:default; }
/* A muṣḥaf turns leftward, so the left button is the next page. The arrows say
   which way, and the number on each says exactly where, so neither has to be
   guessed from the direction alone. */
button.step {
  display:inline-flex; align-items:center; gap:.3rem; padding:.4rem .7rem;
  font-size:.95rem; line-height:1; font-variant-numeric:tabular-nums;
}
button.step .to { font-family:"IBM Plex Mono",monospace; font-size:.8rem; }
.bar .count { font-family:"IBM Plex Mono",monospace; font-size:.75rem; color:var(--ink-mute);
              font-variant-numeric:tabular-nums; }

/* -- the sheet ------------------------------------------------------------ */

.sheet {
  --paper:#FBF7EA; --paper-edge:#EFE6CD; --paper-sunk:#F5EEDC; --qink:#17130C;
  --gold:#9E7C36; --gold-soft:#D6C393; --gold-ink:#7A5E24;
  background:var(--paper); color:var(--qink);
  max-width:42rem; margin:0 auto; padding:.85rem;
  border:1px solid var(--paper-edge); border-radius:3px;
  box-shadow:0 1px 2px rgba(0,0,0,.10), 0 30px 60px -45px rgba(0,0,0,.65);
}
.sheet-head {
  display:flex; justify-content:space-between; align-items:baseline; gap:1rem;
  padding:0 .5rem .5rem; color:var(--gold-ink); font-size:.8rem;
}
.sheet-head .sname { font-family:"Mushaf","Amiri Quran",serif; font-size:1.15rem; }
.sheet-head .juz { font-family:"IBM Plex Mono",monospace; font-size:.72rem;
                   letter-spacing:.1em; text-transform:uppercase; }
.frame { border:2px solid var(--gold); border-radius:2px; padding:3px; }
.frame-in { border:1px solid var(--gold-soft); border-radius:1px; padding:1rem .95rem; }
.sheet-foot {
  display:flex; justify-content:center; padding:.6rem .5rem 0;
}
.folio {
  font-family:"IBM Plex Sans Arabic",sans-serif; font-size:.85rem; color:var(--gold-ink);
  border:1px solid var(--gold-soft); border-radius:999px; padding:.05rem .8rem;
  font-variant-numeric:tabular-nums;
}

/* A muṣḥaf page is a fixed shape: the text block keeps its proportions and its
   lines are spread down it, so a page of 15 lines and the eight-line opening
   both sit on the same sheet. Only the width is fitted; the height follows. */
.lines {
  font-size:clamp(1.12rem, 3.3vw, 1.62rem);
  display:flex; flex-direction:column; justify-content:space-between;
  aspect-ratio:1 / 1.55;
}
.qline { position:relative; direction:rtl; line-height:1.35; }

/* A page set in its own KFGQPC font. The glyphs arrive already elongated to
   fill their line, so the line needs no justification at all — only a type size
   at which one line-width lands on the measure. `cqi` is a length in the text
   block's own content box, so that size is taken from the measure itself and
   re-taken whenever the window changes, with nothing measured in script. */
.lines.glyphs { container-type:inline-size; }
/* Only a line whose tokens carry glyph codes. A page's font holds that page's
   glyphs and nothing else, so the heading and basmalah lines — which have no
   codes — must keep the ordinary face or they render as empty boxes. */
.qtext.qcf {
  display:block; font-family:var(--qcf), serif; white-space:nowrap;
  font-size:calc(100cqi / var(--em, 14.2)); text-align:right;
}
.qtext.qcf .w { padding:0; }
.qtext.qcf .w.shared { box-shadow:inset 0 -.06em 0 var(--gold-soft); }
/* The marker is a glyph of the page's own font here, not a drawn circle. */
.qtext.qcf .ayah-num {
  display:inline; width:auto; height:auto; margin:0; font-size:inherit;
  font-family:inherit; border:0; border-radius:0; box-shadow:none;
  color:var(--gold-ink);
}
.qtext.qcf .ayah-num.flag { background:transparent; color:#8A6410; }
/* The lines the font cannot set are still set from the page's measure, at about
   the size the print gives them. */
/* Amiri's vowelled glyphs reach well past their line box, so the box has to be
   tall enough to hold them or they collide with the āyah line beneath. */
.lines.glyphs .qtext:not(.qcf) { font-size:calc(100cqi / 17.5); line-height:1.75; }
/* The words of the line, justified to the measure by their spaces alone. The
   letterforms are never scaled: a stretched glyph is not the muṣḥaf's glyph. */
.qtext {
  display:flex; align-items:baseline; justify-content:space-between;
  font-family:"Mushaf","Amiri Quran",serif; white-space:nowrap;
}
.qtext.center { width:max-content; margin-inline:auto; justify-content:center; }
.qline.measure .qtext { width:max-content; justify-content:flex-start;
                        visibility:hidden; }
#probe {
  position:absolute; visibility:hidden; pointer-events:none; white-space:nowrap;
  width:max-content; font-family:"Mushaf","Amiri Quran",serif; direction:rtl;
}
.qtext .w { cursor:pointer; padding:0 .05em; border-radius:3px; }
.qtext .w.shared { box-shadow:inset 0 -.09em 0 var(--gold-soft); }
.qtext .w.pick { background:rgba(22,88,74,.20); }

.ayah-num {
  display:inline-flex; align-items:center; justify-content:center;
  width:1.5em; height:1.5em; margin:0 .12em; font-size:.6em; flex:none;
  font-family:"IBM Plex Sans Arabic",sans-serif; color:var(--gold-ink);
  border:1px solid var(--gold); border-radius:50%;
  box-shadow:0 0 0 1.5px var(--paper), 0 0 0 2.5px var(--gold-soft);
  font-variant-numeric:tabular-nums; cursor:pointer;
}
.ayah-num.flag { background:var(--gold-soft); color:#4A3810; }

/* The muṣḥaf sets a sūrah heading in a cartouche the full width of the text
   block: a ruled frame, the name centred in it, and the space either side
   filled with ornament rather than left blank. All of it is drawn in CSS, so
   nothing here depends on a glyph the font may not carry. */
.qtext.band-line { display:block; width:100%; }
.band {
  display:grid; grid-template-columns:1fr auto 1fr; align-items:center; gap:.8em;
  width:100%; padding:.16em .8em; border:1px solid var(--gold); border-radius:1px;
  background:linear-gradient(var(--paper-sunk), var(--paper));
  box-shadow:inset 0 0 0 1.5px var(--paper), inset 0 0 0 2.5px var(--gold-soft);
}
/* Each flank is a pair of hairlines closed by a diamond at the name's side. */
.band .orn {
  position:relative; height:.42em;
  background:linear-gradient(var(--gold-soft), var(--gold-soft)) 0 28%/100% 1px no-repeat,
             linear-gradient(var(--gold-soft), var(--gold-soft)) 0 72%/100% 1px no-repeat;
}
.band .orn::before {
  content:""; position:absolute; top:50%; margin-top:-.19em;
  width:.38em; height:.38em; background:var(--gold); transform:rotate(45deg);
  box-shadow:0 0 0 1.5px var(--paper);
}
.band .orn:first-child::before { inset-inline-end:0; }
.band .orn:last-child::before { inset-inline-start:0; }
.band .bname { font-family:"Mushaf","Amiri Quran",serif; font-size:.92em; direction:rtl;
               color:var(--gold-ink); line-height:1.5; white-space:nowrap; }
.bism { justify-content:center; }

.legend { display:flex; flex-wrap:wrap; gap:1rem; justify-content:center;
          font-size:.75rem; color:var(--ink-mute); margin:1.1rem 0 0; }
.legend .sw { display:inline-block; width:.85rem; height:.85rem; border-radius:3px;
              vertical-align:-2px; margin-inline-end:.35rem; }

/* -- the panel ------------------------------------------------------------ */

.scrim { position:fixed; inset:0; background:rgba(10,12,10,.35); opacity:0;
         pointer-events:none; transition:opacity .18s; z-index:8; }
.scrim.open { opacity:1; pointer-events:auto; }
.panel {
  position:fixed; inset-block:0; inset-inline-end:0; width:min(32rem, 100%);
  background:var(--surface); border-inline-start:1px solid var(--rule);
  box-shadow:-20px 0 50px -35px rgba(0,0,0,.7); z-index:9;
  transform:translateX(102%); transition:transform .2s ease-out;
  display:flex; flex-direction:column;
}
.panel[dir="rtl"] { transform:translateX(-102%); }
.panel.open { transform:none; }
@media (max-width:640px) {
  .panel { inset-block:auto 0; inset-inline:0; width:auto; height:78vh;
           border-inline-start:0; border-top:1px solid var(--rule);
           border-radius:14px 14px 0 0; transform:translateY(102%); }
  .panel.open { transform:none; }
}
.panel-head { padding:1rem 1.1rem .8rem; border-bottom:1px solid var(--rule); }
.panel-body { overflow:auto; padding:1rem 1.1rem 2.5rem; flex:1; }
.panel-title { display:flex; align-items:center; gap:.5rem; flex-wrap:wrap; }
.panel-title h2 { font-family:"IBM Plex Sans Arabic",sans-serif; font-size:1.1rem;
                  font-weight:500; margin:0; }
.panel .close { margin-inline-start:auto; background:transparent; border:0; color:var(--ink-mute);
                font-size:1.3rem; line-height:1; padding:.1rem .3rem; cursor:pointer; }

.chip { font-family:"IBM Plex Mono",monospace; font-size:.7rem; color:var(--ink-soft);
        background:var(--surface-sunk); border:1px solid var(--rule-soft);
        border-radius:999px; padding:.15rem .55rem; white-space:nowrap; }
.chip.on { color:var(--accent); background:var(--accent-soft); border-color:transparent; }
.chip.flag { color:var(--vary-ink); background:var(--vary-bg); border-color:transparent; }

.arabic { font-family:"Mushaf","Amiri Quran",serif; direction:rtl; text-align:right;
          font-size:1.3rem; line-height:2.3; }
.arabic.small { font-size:1.1rem; line-height:2.1; }
.tok-hit { background:var(--accent-soft); border-radius:3px; padding:0 .12em; }
.tok-shared { color:var(--ink-mute); }
.tok-vary { background:var(--vary-bg); color:var(--vary-ink);
            box-shadow:inset 0 -2px 0 var(--vary-edge); border-radius:3px; padding:0 .12em; }

.card { background:var(--surface); border:1px solid var(--rule); border-radius:10px;
        padding:.8rem .9rem; margin-bottom:.9rem; }
.card-head { display:flex; flex-wrap:wrap; gap:.35rem; align-items:center; margin-bottom:.5rem; }
.frame-box { background:var(--surface-sunk); border-radius:8px; padding:.4rem .8rem .55rem; }
.frame-label { font-size:.62rem; letter-spacing:.1em; text-transform:uppercase;
               color:var(--ink-mute); }
.peg { border-inline-start:3px solid var(--vary-edge); background:var(--vary-bg);
       border-radius:0 8px 8px 0; padding:.5rem .8rem; margin:.7rem 0 .2rem; }
.peg-code { font-family:"IBM Plex Mono",monospace; font-size:.64rem; letter-spacing:.08em;
            text-transform:uppercase; color:var(--vary-ink); margin-bottom:.2rem; }
.peg-text { font-family:"IBM Plex Sans Arabic",sans-serif; direction:rtl; text-align:right;
            font-size:.98rem; line-height:1.9; color:var(--vary-ink); }
.peg.sibling { border-inline-start-width:2px; background:transparent; padding:.15rem .55rem;
               margin:.15rem 0 .5rem; }
.peg.sibling .peg-text { font-size:.88rem; line-height:1.65; color:var(--ink-soft); }
.dabit { border-inline-start:3px solid var(--accent); background:var(--accent-soft);
         border-radius:0 8px 8px 0; padding:.5rem .8rem; margin:.7rem 0 .2rem; }
.dabit-code { font-family:"IBM Plex Mono",monospace; font-size:.64rem; letter-spacing:.08em;
              text-transform:uppercase; color:var(--accent); margin-bottom:.2rem; }
.dabit-text { font-family:"IBM Plex Sans Arabic",sans-serif; direction:rtl; text-align:right;
              font-size:.98rem; line-height:1.9; }

.jump {
  display:flex; align-items:baseline; gap:.5rem; width:100%; text-align:start;
  background:transparent; border:0; border-top:1px solid var(--rule-soft);
  padding:.5rem .2rem; color:var(--ink); font-weight:400; cursor:pointer;
}
.jump:hover { background:var(--surface-sunk); }
.jump .jname { font-family:"IBM Plex Sans Arabic",sans-serif; font-size:.95rem; }
.jump .jref { font-family:"IBM Plex Mono",monospace; font-size:.7rem; color:var(--ink-mute); }
.jump .jgo { margin-inline-start:auto; font-size:.7rem; color:var(--accent); }

details.more { margin-top:.4rem; }
details.more > summary { cursor:pointer; font-size:.8rem; color:var(--accent); padding:.3rem 0; }
.note { background:var(--surface-sunk); border:1px solid var(--rule); border-radius:10px;
        padding:.8rem 1rem; color:var(--ink-soft); margin:.8rem 0; font-size:.9rem; }
.note.err { border-color:var(--vary-edge); background:var(--vary-bg); color:var(--vary-ink); }
footer { margin-top:2.5rem; padding-top:1.2rem; border-top:1px solid var(--rule);
         color:var(--ink-mute); font-size:.8rem; display:flex; flex-direction:column; gap:.5rem; }
"""

JS = r"""
const $ = (s) => document.querySelector(s);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
};
// Arabic-Indic digits: the muṣḥaf numbers its āyāt and its pages in them.
const ind = (n) => String(n).replace(/[0-9]/g, (d) => String.fromCharCode(0x0660 + +d));

let SURAHS = [];
let PAGE = null;      // the page payload currently drawn
let PICKED = null;    // verse_key of the selected āyah
let DENSEST = 0;      // width of the muṣḥaf's densest line, at the base size

/* -- the sheet ------------------------------------------------------------ */

// The font for the page being drawn. One @font-face rule is kept and rewritten
// rather than accumulating 604 of them.
function useFont(page, url) {
  let style = $("#qcf");
  if (!style) {
    style = el("style");
    style.id = "qcf";
    document.head.appendChild(style);
  }
  const family = "qcf-p" + page;
  style.textContent =
    `@font-face { font-family:"${family}"; src:url("${url}") format("woff2"); ` +
    `font-display:block; }`;
  $("#lines").style.setProperty("--qcf", `"${family}"`);
  return family;
}

function drawLine(line, marksBy) {
  const node = el("div", "qline");
  const text = el("div", "qtext" + (line.centered ? " center" : ""));
  node.appendChild(text);

  if (line.type === "surah_name") {
    text.classList.add("band-line");
    const box = el("div", "band");
    box.title = `${line.revelation_place} · ${line.ayah_count} ayat`;
    box.appendChild(el("span", "orn"));
    box.appendChild(el("span", "bname", line.name_ar));
    box.appendChild(el("span", "orn"));
    text.appendChild(box);
    return node;
  }

  if (line.type === "basmallah") {
    text.classList.add("center");
    for (const w of line.words) {
      text.appendChild(el("span", "w", w.text));
      text.appendChild(document.createTextNode(" "));
    }
    return node;
  }

  if (line.tokens.some((t) => t.code)) text.classList.add("qcf");
  for (const tok of line.tokens) {
    if (tok.kind === "marker") {
      const mark = marksBy[tok.verse_key] || {};
      const num = el("span", "ayah-num" + (mark.official ? " flag" : ""),
                     tok.code || ind(tok.ayah));
      num.dataset.key = tok.verse_key;
      num.title = mark.official
        ? `${tok.verse_key} · ${mark.official} official mutashabih phrase(s)`
        : tok.verse_key;
      text.appendChild(num);
      continue;
    }
    const word = el("span", "w" + (tok.phrase_ids.length ? " shared" : ""),
                    tok.code || tok.text);
    word.dataset.key = tok.verse_key;
    if (tok.code) word.title = tok.text;
    text.appendChild(word);
    if (!tok.code) text.appendChild(document.createTextNode(" "));
  }
  return node;
}

// Every line of a page is cut to the same width in its own font, but that width
// differs a little from page to page, so the divisor is taken per page — from
// the widest line, since that is the one the measure has to hold. CSS does the
// rest: the type is set from the measure, not from a pixel size fixed here.
async function sizeGlyphPage() {
  const box = $("#lines");
  const family = getComputedStyle(box).getPropertyValue("--qcf").trim();
  try {
    await document.fonts.load(`100px ${family}`);
  } catch (err) {
    /* the page still draws, just at the default divisor */
  }
  const probe = $("#probe");
  probe.style.font = `100px ${family}`;
  let widest = 0;
  for (const text of box.querySelectorAll(".qtext.qcf")) {
    probe.textContent = text.textContent;
    widest = Math.max(widest, probe.scrollWidth);
  }
  probe.textContent = "";
  probe.style.font = "";
  if (widest) box.style.setProperty("--em", (widest / 100 + 0.02).toFixed(3));
}

// The widest a line of this page wants to be, at the page's base size.
function widestHere(box) {
  let widest = 0;
  for (const line of box.querySelectorAll(".qline")) {
    line.classList.add("measure");
    widest = Math.max(widest, line.querySelector(".qtext").scrollWidth);
    line.classList.remove("measure");
  }
  return widest;
}

// The muṣḥaf's densest line, measured once in the face actually doing the
// drawing. `width_chars` only ranks the candidates; which of them is widest
// depends on the font, so all of them are measured and the largest wins.
async function measureBook() {
  const probe = $("#probe");
  const base = parseFloat(getComputedStyle($("#lines")).fontSize);
  probe.style.fontSize = base + "px";
  try {
    const data = await (await fetch("/api/measure")).json();
    for (const line of data.lines || []) {
      probe.textContent = line.text;
      DENSEST = Math.max(DENSEST, probe.scrollWidth);
    }
  } catch (err) {
    DENSEST = 0;   // fall back to fitting each page to itself
  }
  probe.textContent = "";
}

// KFGQPC justifies by elongating the glyphs themselves, which it can do because
// it cuts a font per page. A general face cannot, and faking it — scaling a line
// sideways to fill the measure — distorts the letterforms, which is worse than
// the thing it fixes. So the type is set the way print sets it: ONE size, held
// across the whole muṣḥaf, chosen so the densest line in the book fills the
// measure. Every other line is left with slack, which opens its word spaces.
//
// Pages 1 and 2 are the exception the print makes too: eight lines inside their
// own frame, set larger than the body of the book. A page that is not the usual
// fifteen lines is fitted to itself.
function fitLines() {
  const box = $("#lines");
  const width = box.clientWidth;
  if (!width) return;
  box.style.fontSize = "";
  const base = parseFloat(getComputedStyle(box).fontSize);
  const opening = PAGE && PAGE.lines_printed < 15;
  const reference = !opening && DENSEST ? DENSEST : widestHere(box);
  if (!reference) return;
  const fit = Math.max(0.5, Math.min(1.8, width / reference));
  box.style.fontSize = (base * fit).toFixed(2) + "px";
}

// The box is measured, so nothing can be fitted until it has a width: the first
// layout, a resize and a late-arriving font all have to be waited for.
function watchWidth() {
  let fitted = 0;
  new ResizeObserver((entries) => {
    const width = entries[0].contentRect.width;
    if (Math.abs(width - fitted) < 1) return;   // our own font change, not a resize
    fitted = width;
    requestAnimationFrame(fitLines);
  }).observe($("#lines"));
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(async () => {
      DENSEST = 0;
      await measureBook();
      requestAnimationFrame(fitLines);
    });
  }
}

function drawPage(data) {
  PAGE = data;
  const marksBy = {};
  for (const a of data.ayat) marksBy[a.verse_key] = a;

  $("#sname").textContent = data.surahs.map((s) => s.name_ar).join(" · ");
  const opens = data.ayat.filter((a) => a.starts_juz || a.starts_hizb);
  $("#juz").textContent = data.juz
    ? `juz' ${data.juz} · hizb ${data.hizb}` +
      opens.map((a) => (a.starts_juz ? ` · juz' ${a.juz} opens` : ` · hizb ${a.hizb} opens`)).join("")
    : "";
  $("#folio").textContent = ind(data.page);
  $("#page").value = data.page;
  $("#total").textContent = `page ${data.page} of ${data.pages} · ${data.counts.ayat} ayat · ` +
    `${data.counts.with_official} carrying an official mutashabih`;
  $("#prev").disabled = !data.prev;
  $("#next").disabled = !data.next;
  $("#prev-n").textContent = data.prev || "";
  $("#next-n").textContent = data.next || "";
  $("#prev").title = data.prev ? `back to page ${data.prev}` : "the first page";
  $("#next").title = data.next ? `on to page ${data.next}` : "the last page";

  const box = $("#lines");
  box.textContent = "";
  box.classList.toggle("glyphs", Boolean(data.glyph_font));
  if (data.glyph_font) useFont(data.page, data.glyph_font);
  for (const line of data.lines) box.appendChild(drawLine(line, marksBy));
  if (data.glyph_font) sizeGlyphPage();
  else {
    fitLines();
    requestAnimationFrame(fitLines);
  }
  paint();
}

function paint() {
  for (const node of $("#lines").querySelectorAll("[data-key]")) {
    node.classList.toggle("pick", node.dataset.key === PICKED);
  }
}

/* -- the panel ------------------------------------------------------------ */

const PEG_LABEL = {
  CUE_BEFORE: "cue · the word before",
  SOLE_IN_SURAH: "cue · only one in the surah",
  ORDINAL_IN_SURAH: "cue · counted within the surah",
};

function pegBox(peg, sibling) {
  const box = el("div", "peg" + (sibling ? " sibling" : ""));
  if (!sibling) {
    box.appendChild(
      el("div", "peg-code",
         `${PEG_LABEL[peg.kind] || peg.kind} · strength ${peg.strength.toFixed(2)}`)
    );
  }
  box.appendChild(el("div", "peg-text", peg.text_ar));
  return box;
}

function ayahLine(words, start, end) {
  const line = el("div", "arabic small");
  for (const w of words) {
    const tok = el("span", null, w.text);
    if (w.in_span || (w.word_id >= start && w.word_id <= end)) tok.className = "tok-shared";
    else if (w.word_id === start - 1 || w.word_id === end + 1) tok.className = "tok-vary";
    line.appendChild(tok);
    line.appendChild(document.createTextNode(" "));
  }
  return line;
}

// Every sibling position is a place in the muṣḥaf, so it is a place to go.
function jumpRow(pos) {
  const row = el("button", "jump");
  row.type = "button";
  row.appendChild(el("span", "jname", pos.surah_name_ar));
  row.appendChild(el("span", "jref", `${pos.verse_key} · page ${pos.page}`));
  row.appendChild(el("span", "jgo", "open page →"));
  row.addEventListener("click", () => go(pos.page, pos.verse_key));
  return row;
}

function officialCard(phrase) {
  const card = el("div", "card");
  const head = el("div", "card-head");
  head.appendChild(el("span", "chip", `phrase ${phrase.phrase_id}`));
  head.appendChild(el("span", "chip on", `${phrase.set_count} positions`));
  head.appendChild(el("span", "chip", `${phrase.surah_count} surahs`));
  card.appendChild(head);

  const frame = el("div", "frame-box");
  frame.appendChild(el("div", "frame-label", "shared phrase · official mutashabih"));
  const text = el("div", "arabic");
  text.textContent = phrase.text_ar;
  frame.appendChild(text);
  card.appendChild(frame);

  for (const here of phrase.here) if (here.peg) card.appendChild(pegBox(here.peg, false));

  if (phrase.elsewhere.length) {
    const more = el("details", "more");
    more.open = phrase.elsewhere.length <= 4;
    more.appendChild(
      el("summary", null, `the other ${phrase.elsewhere.length} position(s), each with its cue`)
    );
    for (const other of phrase.elsewhere) {
      more.appendChild(jumpRow(other));
      if (other.peg) more.appendChild(pegBox(other.peg, true));
      more.appendChild(ayahLine(other.ayat[0].words, other.start_word_id, other.end_word_id));
    }
    card.appendChild(more);
  }
  return card;
}

function groupCard(match) {
  const card = el("div", "card");
  const head = el("div", "card-head");
  head.appendChild(el("span", "chip", `group ${match.group_id}`));
  head.appendChild(el("span", "chip on", `${match.occurrence_count} positions`));
  head.appendChild(el("span", "chip", `${match.span_len} tokens`));
  if (match.cross_surah) head.appendChild(el("span", "chip flag", "crosses a surah seam"));
  card.appendChild(head);

  const frame = el("div", "frame-box");
  frame.appendChild(el("div", "frame-label", "shared phrase"));
  const text = el("div", "arabic");
  text.textContent = match.span_text;
  frame.appendChild(text);
  card.appendChild(frame);

  for (const d of match.dawabit) {
    const box = el("div", "dabit");
    box.appendChild(el("div", "dabit-code", `${d.rule_code} · strength ${d.strength.toFixed(2)}`));
    box.appendChild(el("div", "dabit-text", d.text_ar));
    card.appendChild(box);
  }
  for (const other of match.elsewhere) card.appendChild(jumpRow(other));
  return card;
}

function renderPanel(data) {
  const q = data.query;
  const title = $("#panel-title");
  title.textContent = "";
  const h = el("h2", null, q.surah_name_ar);
  title.appendChild(h);
  title.appendChild(el("span", "chip", q.verse_key));
  title.appendChild(el("span", "chip", `juz' ${q.juz}`));
  const close = el("button", "close", "×");
  close.type = "button";
  close.setAttribute("aria-label", "close");
  close.addEventListener("click", closePanel);
  title.appendChild(close);

  const body = $("#panel-body");
  body.textContent = "";

  const line = el("div", "arabic");
  for (const w of q.words) {
    line.appendChild(el("span", w.repeated ? "tok-hit" : null, w.text));
    line.appendChild(document.createTextNode(" "));
  }
  body.appendChild(line);

  const counts = el("div", "card-head");
  counts.style.margin = ".8rem 0";
  counts.appendChild(
    el("span", "chip" + (data.counts.official_phrases ? " on" : ""),
       `${data.counts.official_phrases} official phrase(s)`)
  );
  counts.appendChild(el("span", "chip", `${data.counts.matches} repeated phrase(s)`));
  counts.appendChild(el("span", "chip", `${data.counts.distinct_ayat} other ayat`));
  body.appendChild(counts);

  if (data.official.length) {
    for (const phrase of data.official) body.appendChild(officialCard(phrase));
  }

  if (data.matches.length) {
    const more = el("details", "more");
    more.appendChild(
      el("summary", null, `${data.matches.length} detected repeat(s) touching this ayah`)
    );
    for (const match of data.matches) more.appendChild(groupCard(match));
    body.appendChild(more);
  }

  if (!data.official.length && !data.matches.length) {
    body.appendChild(
      el("div", "note", "Nothing repeated touches this ayah at the current thresholds.")
    );
  }

  const link = el("div", "note");
  const anchor = el("a", null, "full analysis for this ayah →");
  anchor.href = `/#${q.verse_key}`;
  link.appendChild(anchor);
  body.appendChild(link);
}

function openPanel() {
  $("#panel").classList.add("open");
  $("#scrim").classList.add("open");
}

function closePanel() {
  $("#panel").classList.remove("open");
  $("#scrim").classList.remove("open");
  PICKED = null;
  paint();
  setHash();
}

async function pick(key) {
  PICKED = key;
  paint();
  openPanel();
  setHash();
  const [surah, ayah] = key.split(":");
  $("#panel-body").textContent = "";
  $("#panel-body").appendChild(el("div", "note", "reading…"));
  try {
    const res = await fetch(`/api/mutashabih/${surah}/${ayah}?min_len=3&limit=12`);
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `request failed (${res.status})`);
    renderPanel(data);
  } catch (err) {
    $("#panel-body").textContent = "";
    $("#panel-body").appendChild(el("div", "note err", String(err.message || err)));
  }
}

/* -- navigation ----------------------------------------------------------- */

function setHash() {
  const parts = [`p=${PAGE ? PAGE.page : 1}`];
  if (PICKED) parts.push(`a=${PICKED}`);
  history.replaceState(null, "", "#" + parts.join("&"));
}

async function go(page, key) {
  const target = Math.max(1, Math.min(Number(page) || 1, PAGE ? PAGE.pages : 604));
  if (!PAGE || PAGE.page !== target) {
    try {
      const res = await fetch(`/api/page/${target}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || `request failed (${res.status})`);
      drawPage(data);
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err) {
      $("#lines").textContent = "";
      $("#lines").appendChild(el("div", "note err", String(err.message || err)));
      return;
    }
  }
  if (key) pick(key);
  else setHash();
}

function fromHash() {
  const hash = new URLSearchParams((location.hash || "").replace(/^#/, ""));
  return { page: Number(hash.get("p")) || 1, key: hash.get("a") };
}

async function loadSurahs() {
  SURAHS = await (await fetch("/api/surahs")).json();
  const sel = $("#surah");
  for (const s of SURAHS) {
    const option = el("option", null, `${s.surah}. ${s.name_ar}`);
    option.value = s.surah;
    sel.appendChild(option);
  }
}

window.addEventListener("DOMContentLoaded", async () => {
  await Promise.all([loadSurahs(), measureBook()]);
  const start = fromHash();
  await go(start.page, start.key);

  $("#lines").addEventListener("click", (event) => {
    const node = event.target.closest("[data-key]");
    if (node) pick(node.dataset.key);
  });
  $("#prev").addEventListener("click", () => go(PAGE.prev));
  $("#next").addEventListener("click", () => go(PAGE.next));
  $("#page").addEventListener("change", () => go($("#page").value));
  $("#surah").addEventListener("change", () => {
    const surah = SURAHS.find((s) => s.surah === Number($("#surah").value));
    if (surah) go(surah.first_page, `${surah.surah}:1`);
  });
  $("#scrim").addEventListener("click", closePanel);
  window.addEventListener("hashchange", () => {
    const next = fromHash();
    if (!PAGE || next.page !== PAGE.page || next.key !== PICKED) go(next.page, next.key);
  });
  // The muṣḥaf reads right to left, so the left arrow turns to the next page.
  window.addEventListener("keydown", (event) => {
    if (event.target.matches("input, select, textarea")) return;
    if (event.key === "ArrowLeft" && PAGE && PAGE.next) go(PAGE.next);
    if (event.key === "ArrowRight" && PAGE && PAGE.prev) go(PAGE.prev);
    if (event.key === "Escape") closePanel();
  });
  watchWidth();
});
"""


def html() -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The mushaf</title>
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
    <span class="here">The muṣḥaf</span>
  </nav>

  <div class="bar">
    <button class="ghost step" id="next" type="button">&#8592;<span class="to" id="next-n"></span></button>
    <span><label for="page">page</label>
      <input type="number" id="page" min="1" max="604" value="1"></span>
    <button class="ghost step" id="prev" type="button"><span class="to" id="prev-n"></span>&#8594;</button>
    <span class="grow"><label for="surah">jump to</label>
      <select id="surah"><option value="">sūrah…</option></select></span>
    <span class="count" id="total"></span>
  </div>

  <div id="probe"></div>

  <div class="sheet">
    <div class="sheet-head">
      <div class="sname" id="sname"></div>
      <div class="juz" id="juz"></div>
    </div>
    <div class="frame"><div class="frame-in">
      <div class="lines" id="lines"></div>
    </div></div>
    <div class="sheet-foot"><span class="folio" id="folio"></span></div>
  </div>

  <div class="legend">
    <span><span class="sw" style="box-shadow:inset 0 -.35rem 0 #D6C393"></span>words inside an official mutashābih phrase</span>
    <span><span class="sw" style="background:#D6C393;border-radius:50%"></span>āyah carrying one</span>
    <span>click any word or āyah number</span>
  </div>

  <footer>
    <div><strong>الضوابط وسيلة حفظ لا تفسير.</strong> The pegs in the panel are memory
    aids. They say where a wording sits, never why it is worded that way.</div>
    <div>Lines, pages and headings come from the KFGQPC layout recorded in
    <code>data/raw/PROVENANCE.md</code>; every token is served byte-for-byte from the
    database. Āyah lines are set in the font KFGQPC cut for that page — sūrah
    headings and basmalah lines are not yet. See <code>docs/MUSHAF.md</code>.
    JSON for this view: <code>/api/page/1</code>.</div>
  </footer>
</div>

<div class="scrim" id="scrim"></div>
<aside class="panel" id="panel" aria-label="mutashabihat for the selected ayah">
  <div class="panel-head"><div class="panel-title" id="panel-title"></div></div>
  <div class="panel-body" id="panel-body"></div>
</aside>
<script>{JS}</script>
</body>
</html>
"""
