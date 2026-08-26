"""Unpack the archives in data/raw/ into data/raw/extracted/.

Dispatches on magic bytes, not on filename: QUL serves at least one resource
with a .json.bz2 name that is actually a ZIP container, and trusting the
extension silently loses that resource.

Originals are left untouched so PROVENANCE checksums stay meaningful.
"""
from __future__ import annotations

import bz2
import gzip
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
DEST = RAW / "extracted"

ZIP_MAGIC = b"PK\x03\x04"
BZ2_MAGIC = b"BZh"
GZ_MAGIC = b"\x1f\x8b"


def sniff(path: Path) -> str:
    head = path.open("rb").read(4)
    if head.startswith(ZIP_MAGIC):
        return "zip"
    if head.startswith(BZ2_MAGIC):
        return "bz2"
    if head.startswith(GZ_MAGIC):
        return "gz"
    return "raw"


def base_name(arc: Path) -> str:
    stem = arc.name
    for suf in (".zip", ".bz2", ".gz"):
        if stem.endswith(suf):
            stem = stem[: -len(suf)]
    return Path(stem).stem or stem


def main() -> int:
    DEST.mkdir(parents=True, exist_ok=True)
    archives = sorted(
        p
        for p in RAW.iterdir()
        if p.is_file() and p.suffix.lower() in {".zip", ".bz2", ".gz"}
    )
    if not archives:
        print("no archives found in data/raw/", file=sys.stderr)
        return 1

    problems = 0
    for arc in archives:
        kind = sniff(arc)
        base = base_name(arc)
        declared = arc.suffix.lstrip(".").lower()
        if kind != declared:
            print(f"  note: {arc.name} is declared .{declared} but is actually {kind}")

        try:
            if kind == "zip":
                with zipfile.ZipFile(arc) as zf:
                    members = [m for m in zf.namelist() if not m.endswith("/")]
                    for m in members:
                        ext = Path(m).suffix or ".bin"
                        out = DEST / (
                            base + ext
                            if len(members) == 1
                            else f"{base}__{Path(m).name}"
                        )
                        with zf.open(m) as src, out.open("wb") as dst:
                            shutil.copyfileobj(src, dst)
                        print(f"{arc.name}: {m} -> {out.name} ({out.stat().st_size:,} B)")
            elif kind in {"bz2", "gz"}:
                opener = bz2.open if kind == "bz2" else gzip.open
                inner = Path(arc.name[: -len(arc.suffix)])
                out = DEST / (inner.stem + (inner.suffix or ".bin"))
                with opener(arc, "rb") as src, out.open("wb") as dst:
                    shutil.copyfileobj(src, dst)
                print(f"{arc.name}: -> {out.name} ({out.stat().st_size:,} B)")
            else:
                print(f"  !! {arc.name}: unrecognised container (magic not zip/bz2/gz)")
                problems += 1
        except (zipfile.BadZipFile, OSError) as exc:
            print(f"  !! {arc.name}: {exc}")
            problems += 1

    if problems:
        print(f"\n{problems} archive(s) failed to extract.", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
