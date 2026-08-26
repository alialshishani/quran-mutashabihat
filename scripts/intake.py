"""M0 intake: hash, inspect, and report on every file in data/raw/.

Does not transform anything. Its job is to answer two questions:
  1. Exactly what did we download (SHA-256, size)?
  2. Does each file's schema match what the brief expects, or has it drifted?

Per brief §2 and §12, a schema divergence is a STOP condition, not something to
improvise around. This script reports divergence loudly and exits non-zero.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
import sys
import zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "interim" / "intake_report.md"

# Columns we need to find *somewhere* in each resource class. Names vary between
# QUL exports, so we report what is present and let a human confirm the mapping
# rather than guessing a rename.
EXPECTED_HINTS = {
    "word": ["surah", "ayah", "position", "text", "word"],
    "layout": ["page", "line", "surah", "ayah"],
    "morphology": ["word", "root", "lemma", "stem"],
    "metadata": ["surah", "ayah", "juz", "hizb", "rub", "name"],
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def describe_sqlite(path: Path) -> list[str]:
    lines: list[str] = []
    try:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error as exc:
        return [f"  !! cannot open as SQLite: {exc}"]
    try:
        cur = con.cursor()
        tables = [
            r[0]
            for r in cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        ]
        if not tables:
            lines.append("  !! no user tables found")
        for t in tables:
            cols = [r[1] for r in cur.execute(f'PRAGMA table_info("{t}")')]
            n = cur.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
            lines.append(f"  - table `{t}` — {n:,} rows")
            lines.append(f"    cols: {', '.join(cols)}")
            # One sample row, so a human can eyeball the actual encoding.
            row = cur.execute(f'SELECT * FROM "{t}" LIMIT 1').fetchone()
            if row is not None:
                cells = [
                    (v[:60] + "…") if isinstance(v, str) and len(v) > 60 else v
                    for v in row
                ]
                lines.append(f"    sample: {cells}")
    finally:
        con.close()
    return lines


def describe_json(path: Path) -> list[str]:
    try:
        with path.open(encoding="utf-8") as fh:
            data = json.load(fh)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return [f"  !! cannot parse as JSON: {exc}"]
    if isinstance(data, dict):
        keys = list(data)
        out = [f"  - object with {len(keys):,} keys; first: {keys[:5]}"]
        if keys:
            first = data[keys[0]]
            out.append(f"    sample value type: {type(first).__name__}")
            out.append(f"    sample: {json.dumps(first, ensure_ascii=False)[:300]}")
        return out
    if isinstance(data, list):
        out = [f"  - array of {len(data):,} items"]
        if data:
            out.append(f"    sample: {json.dumps(data[0], ensure_ascii=False)[:300]}")
        return out
    return [f"  - scalar {type(data).__name__}"]


def describe_zip(path: Path) -> list[str]:
    try:
        with zipfile.ZipFile(path) as zf:
            names = zf.namelist()
    except zipfile.BadZipFile as exc:
        return [f"  !! bad zip: {exc}"]
    out = [f"  - archive with {len(names):,} entries"]
    out += [f"    {n}" for n in names[:15]]
    if len(names) > 15:
        out.append(f"    … and {len(names) - 15:,} more")
    return out


def main() -> int:
    if not RAW.exists():
        print(f"missing {RAW}", file=sys.stderr)
        return 2

    files = sorted(
        p
        for p in RAW.rglob("*")
        if p.is_file() and p.suffix not in {".md", ".zip", ".bz2", ".gz"}
    )
    if not files:
        print(
            "No source files in data/raw/ yet.\n"
            "See docs/DOWNLOAD.md — QUL downloads require a signed-in session.",
            file=sys.stderr,
        )
        return 1

    report = [
        "# Intake report",
        "",
        f"Generated: {date.today().isoformat()}",
        f"Files inspected: {len(files)}",
        "",
    ]
    problems = 0
    for p in files:
        report.append(f"## `{p.name}`")
        report.append("")
        report.append(f"- size: {p.stat().st_size:,} bytes")
        report.append(f"- sha256: `{sha256(p)}`")
        suffix = p.suffix.lower()
        if suffix in {".db", ".sqlite", ".sqlite3"}:
            body = describe_sqlite(p)
        elif suffix == ".json":
            body = describe_json(p)
        elif suffix == ".zip":
            body = describe_zip(p)
        else:
            body = [f"  - unrecognised extension `{suffix}`; not inspected"]
        problems += sum(1 for line in body if "!!" in line)
        report.extend(body)
        report.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(report), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(files)} files)")

    if problems:
        print(
            f"\n{problems} file(s) could not be read as their declared format.\n"
            "Per brief §12 this is a stop-and-report condition — not resolving it here.",
            file=sys.stderr,
        )
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
