"""Draw the launcher icon.

The mark is the one thing this app adds to a printed page: the hairline under
the wording an ayah shares with another. So the icon is a page, and the rule
under one of its lines -- in the same green and gold the app sets itself in.

Writes both an adaptive icon (foreground + background colour, which is what
modern launchers mask) and the legacy square PNG for older ones.
"""
import pathlib
import sys

from PIL import Image, ImageDraw

GREEN = (22, 88, 74, 255)      # --accent
CREAM = (252, 252, 250, 255)   # --ground
INK = (32, 46, 42, 255)
GOLD = (216, 169, 60, 255)     # --vary-edge

# Adaptive foregrounds are 108dp with only the middle 72dp guaranteed visible,
# so everything is drawn well inside that.
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

SS = 4  # supersample, then downscale, so the small sizes stay clean


def draw_page(size, inset):
    """The page and its lines, drawn on a transparent square of `size`."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # The page, upright like a mushaf leaf.
    pw, ph = s * inset, s * inset * 1.24
    x0, y0 = (s - pw) / 2, (s - ph) / 2
    d.rounded_rectangle([x0, y0, x0 + pw, y0 + ph], radius=s * 0.035, fill=CREAM)

    # Four lines of text. Right-aligned: the page reads right to left.
    pad = pw * 0.14
    line_h = ph * 0.072
    gap = ph * 0.155
    top = y0 + ph * 0.17
    widths = (0.86, 1.0, 0.78, 0.92)

    for i, w in enumerate(widths):
        ly = top + i * gap
        lx1 = x0 + pw - pad
        lx0 = lx1 - (pw - 2 * pad) * w
        d.rounded_rectangle([lx0, ly, lx1, ly + line_h],
                            radius=line_h / 2, fill=INK)
        # The rule under the shared wording -- the whole point of the app.
        if i == 1:
            uy = ly + line_h + ph * 0.028
            uh = ph * 0.030
            ux0 = lx1 - (pw - 2 * pad) * 0.62
            d.rounded_rectangle([ux0, uy, lx1, uy + uh],
                                radius=uh / 2, fill=GOLD)

    return img.resize((size, size), Image.LANCZOS)


def main(res: pathlib.Path):
    for name, size in FOREGROUND.items():
        out = res / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)
        # 0.46 keeps the page inside the 72dp safe circle of a 108dp canvas.
        draw_page(size, 0.46).save(out / "ic_launcher_foreground.png")

    for name, size in LEGACY.items():
        out = res / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)
        img = Image.new("RGBA", (size, size), GREEN)
        img.alpha_composite(draw_page(size, 0.60))
        img.save(out / "ic_launcher.png")

    # A big one to look at before shipping it.
    big = Image.new("RGBA", (512, 512), GREEN)
    big.alpha_composite(draw_page(512, 0.60))
    big.save(res.parent.parent.parent.parent.parent / "icon_preview.png")

    print("wrote adaptive foregrounds and legacy icons")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]))
