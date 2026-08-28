"""Decompress the vendored KFGQPC WOFF2 fonts to TTF.

Flutter's engine cannot load WOFF2 -- it takes TTF/OTF only -- so any Flutter
build needs this step between scripts.fetch_qcf and the app bundle. The glyph
data is untouched: this only removes the WOFF2 container.

    python qcf_to_ttf.py data/raw/fonts/qcf-v1 build/fonts/qcf-v1
"""
import pathlib, sys
from fontTools.ttLib import TTFont

src = pathlib.Path(sys.argv[1])
dst = pathlib.Path(sys.argv[2]); dst.mkdir(parents=True, exist_ok=True)

total_in = total_out = 0
files = sorted(src.glob("p*.woff2"), key=lambda p: int(p.stem[1:]))
for p in files:
    out = dst / f"{p.stem}.ttf"
    f = TTFont(p); f.flavor = None; f.save(out)
    total_in += p.stat().st_size
    total_out += out.stat().st_size

print(f"{len(files)} fonts: {total_in/1e6:.1f} MB woff2 -> {total_out/1e6:.1f} MB ttf")
