"""Fetch the KFGQPC page fonts and the glyph codes that address them.

The muṣḥaf is not set in one typeface. KFGQPC cuts a font **per page**, holding
that page's glyphs already shaped and already elongated to fill their lines, and
addresses them through a private encoding — so a page needs both its font and
the per-word code that names each glyph inside it. With both, a page reproduces
the print exactly and needs no justification at all; with neither, the text has
to be set in a general Arabic face that cannot elongate, and the lines come out
loose. See docs/MUSHAF.md.

    python -m scripts.fetch_qcf                 # fonts and codes, skipping what is there
    python -m scripts.fetch_qcf --fonts         # fonts only
    python -m scripts.fetch_qcf --pages 1-10    # a range, for a look before the lot

Two origins, neither of them gated:

  fonts  static-cdn.tarteel.ai — the QUL CDN, same project as every resource in
         data/raw/ already, serving the V1 set as woff2 (~65 KB a page)
  codes  api.quran.com v4 — `code_v1` per word, with the page and line it prints
         on, and the āyah-marker glyphs among the tokens

Resumable: a file already on disk is left alone, so an interrupted run is
finished by running it again. Writes a manifest of SHA-256 sums for PROVENANCE.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT / "data" / "raw" / "fonts" / "qcf-v1"
CODES = ROOT / "data" / "raw" / "qcf-v1-codes"
MANIFEST = ROOT / "data" / "raw" / "qcf-v1-manifest.json"

PAGES = 604
FONT_URL = "https://static-cdn.tarteel.ai/qul/fonts/quran_fonts/v1-optimized/woff2/p{page}.woff2?v=3.1"
CODE_URL = (
    "https://api.quran.com/api/v4/verses/by_page/{page}"
    "?words=true&word_fields=code_v1,page_number,line_number&per_page=300"
)
WOFF2_MAGIC = b"wOF2"
AGENT = "quran-msh/1.0 (+local research build)"
RETRIES = 3


class FetchError(RuntimeError):
    """A page that could not be fetched after every retry."""


def get(url: str) -> bytes:
    last: Exception | None = None
    for attempt in range(RETRIES):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": AGENT})
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            time.sleep(0.5 * (attempt + 1))
    raise FetchError(f"{url}: {last}")


def fetch_font(page: int) -> str:
    """One page's font. Verified by magic bytes: a 404 page is also 200 bytes."""
    path = FONTS / f"p{page}.woff2"
    if path.exists() and path.stat().st_size > 1024:
        return "kept"
    body = get(FONT_URL.format(page=page))
    if not body.startswith(WOFF2_MAGIC):
        raise FetchError(f"page {page}: not a woff2 ({body[:32]!r})")
    path.write_bytes(body)
    return "fetched"


def fetch_codes(page: int) -> str:
    """One page's glyph codes, kept as the API returned them.

    Nothing is reshaped here. `pipeline.glyphs` is what binds these to the
    corpus, and it is the place that gets to fail if they disagree with the
    layout the corpus was built on.
    """
    path = CODES / f"p{page}.json"
    if path.exists() and path.stat().st_size > 64:
        return "kept"
    body = get(CODE_URL.format(page=page))
    data = json.loads(body)
    verses = data.get("verses")
    if not verses:
        raise FetchError(f"page {page}: no verses in response")
    missing = [
        w["id"]
        for v in verses
        for w in v["words"]
        if not w.get("code_v1")
    ]
    if missing:
        raise FetchError(f"page {page}: {len(missing)} token(s) carry no code_v1")
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return "fetched"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_pages(spec: str | None) -> list[int]:
    if not spec:
        return list(range(1, PAGES + 1))
    out: list[int] = []
    for part in spec.split(","):
        lo, _, hi = part.partition("-")
        out.extend(range(int(lo), int(hi or lo) + 1))
    bad = [p for p in out if not 1 <= p <= PAGES]
    if bad:
        sys.exit(f"pages outside 1-{PAGES}: {bad}")
    return out


def run(what: str, pages: list[int], worker, workers: int) -> dict[str, int]:
    tally = {"fetched": 0, "kept": 0}
    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for page, result in zip(pages, pool.map(_safe(worker), pages)):
            if isinstance(result, Exception):
                failures.append(f"page {page}: {result}")
            else:
                tally[result] += 1
            done = tally["fetched"] + tally["kept"] + len(failures)
            if done % 50 == 0 or done == len(pages):
                print(f"  {what}: {done}/{len(pages)}", file=sys.stderr)
    if failures:
        for line in failures[:10]:
            print(f"  {line}", file=sys.stderr)
        sys.exit(f"{len(failures)} {what} failed; re-run to retry just those")
    return tally


def _safe(worker):
    def call(page: int):
        try:
            return worker(page)
        except Exception as exc:  # reported per page, never silently dropped
            return exc

    return call


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fonts", action="store_true", help="fonts only")
    parser.add_argument("--codes", action="store_true", help="glyph codes only")
    parser.add_argument("--pages", help="e.g. 1-10 or 1,89,604 (default: all 604)")
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    both = not (args.fonts or args.codes)
    pages = parse_pages(args.pages)
    FONTS.mkdir(parents=True, exist_ok=True)
    CODES.mkdir(parents=True, exist_ok=True)

    if args.fonts or both:
        tally = run("fonts", pages, fetch_font, args.workers)
        print(f"fonts: {tally['fetched']:,} fetched, {tally['kept']:,} already present")
    if args.codes or both:
        tally = run("codes", pages, fetch_codes, args.workers)
        print(f"codes: {tally['fetched']:,} fetched, {tally['kept']:,} already present")

    fonts = sorted(FONTS.glob("p*.woff2"))
    codes = sorted(CODES.glob("p*.json"))
    MANIFEST.write_text(
        json.dumps(
            {
                "fonts": {
                    "origin": FONT_URL,
                    "files": {p.name: sha256(p) for p in fonts},
                    "bytes": sum(p.stat().st_size for p in fonts),
                },
                "codes": {
                    "origin": CODE_URL,
                    "files": {p.name: sha256(p) for p in codes},
                    "bytes": sum(p.stat().st_size for p in codes),
                },
            },
            indent=1,
        ),
        encoding="utf-8",
    )
    total = sum(p.stat().st_size for p in fonts) + sum(p.stat().st_size for p in codes)
    print(f"{len(fonts)} fonts, {len(codes)} code files, {total / 1e6:.1f} MB")
    print(f"checksums: {MANIFEST.relative_to(ROOT)}")
    print("next: python -m pipeline.glyphs --rebuild")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
