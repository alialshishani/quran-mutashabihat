"""Build everything the app ships, from what the pipeline already produced.

    python -m mobile.tools.stage_assets          # from the repository root

Four things, none of which belong in git:

  assets/app.db        data/quran.db plus the read-path indexes
  assets/fonts/*.ttf   the 604 KFGQPC page fonts, decompressed from WOFF2
  assets/ui/           Amiri, for the lines the page fonts cannot set
  web/sqlite3.wasm     SQLite for the web build only

The muṣḥaf fonts are the ones `data/raw/PROVENANCE.md` leaves an open licence
question over. This script moves them into an app bundle; it does not settle
anything. Nothing here may ship to anyone else until that is answered.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import sqlite3
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "mobile" / "app"
INDEXES = pathlib.Path(__file__).resolve().parent / "read_path_indexes.sql"

# Amiri is OFL, so unlike the KFGQPC page fonts it may simply be redistributed.
AMIRI = (
    "https://github.com/google/fonts/raw/main/ofl/amiri/Amiri-Regular.ttf",
    "assets/ui/Amiri-Regular.ttf",
)
# The WASM build of SQLite, from the release of the `sqlite3` package the app
# depends on. Web only; iOS and Android use the native library.
WASM = (
    "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm",
    "web/sqlite3.wasm",
)


def fetch(url: str, dest: pathlib.Path) -> None:
    if dest.exists():
        print(f"  {dest.relative_to(APP)} present")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"  fetching {url}")
    with urllib.request.urlopen(url, timeout=120) as r:
        dest.write_bytes(r.read())
    digest = hashlib.sha256(dest.read_bytes()).hexdigest()
    print(f"  {dest.relative_to(APP)}  {dest.stat().st_size/1e6:.1f} MB  sha256 {digest[:16]}…")


def stage_db(force: bool) -> None:
    src = ROOT / "data" / "quran.db"
    if not src.exists():
        sys.exit("data/quran.db is not built; run: python -m pipeline.ingest --rebuild")
    dst = APP / "assets" / "app.db"
    if dst.exists() and not force:
        print("  assets/app.db present (--force to rebuild)")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(src.read_bytes())

    con = sqlite3.connect(dst)
    con.executescript(INDEXES.read_text(encoding="utf-8"))
    con.execute("ANALYZE")
    con.commit()
    con.execute("VACUUM")
    con.close()
    print(f"  assets/app.db  {dst.stat().st_size/1e6:.1f} MB  (+ read-path indexes)")


def stage_fonts(force: bool) -> None:
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        sys.exit("needs fonttools and brotli: pip install fonttools brotli")

    src = ROOT / "data" / "raw" / "fonts" / "qcf-v1"
    if not src.exists():
        sys.exit("page fonts not fetched; run: python -m scripts.fetch_qcf")
    out = APP / "assets" / "fonts"
    out.mkdir(parents=True, exist_ok=True)

    files = sorted(src.glob("p*.woff2"), key=lambda p: int(p.stem[1:]))
    made = 0
    for p in files:
        ttf = out / f"{p.stem}.ttf"
        if ttf.exists() and not force:
            continue
        # Flutter's engine cannot load WOFF2; this only removes the container,
        # the glyph data is untouched.
        f = TTFont(p)
        f.flavor = None
        f.save(ttf)
        made += 1
    total = sum(f.stat().st_size for f in out.glob("*.ttf"))
    print(f"  assets/fonts  {len(files)} fonts, {made} converted, {total/1e6:.1f} MB")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true", help="rebuild what is already there")
    args = ap.parse_args()

    print("staging app assets")
    stage_db(args.force)
    stage_fonts(args.force)
    fetch(AMIRI[0], APP / AMIRI[1])
    fetch(WASM[0], APP / WASM[1])
    print("done")


if __name__ == "__main__":
    main()
