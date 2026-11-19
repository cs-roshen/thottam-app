"""Build the launcher icons and the logo lockup from the master mark.

Source: design/logo/thottam-logo.svg (the palm and sun on the primary tile).

Usage: python tool/build_icons.py
Needs fonttools (as tool/build_fonts.py) and Google Chrome or Microsoft Edge,
which draws the SVG at each size. Set CHROME to the browser's path if it is
not found.

Writes:
  design/logo/thottam-logo-lockup.svg  mark with the name, text as outlines
  android/app/src/main/res/mipmap-*/   legacy icon, adaptive foreground and
                                       monochrome layers (API 26+ XML is
                                       mipmap-anydpi-v26/ic_launcher.xml)
  ios/Runner/Assets.xcassets/AppIcon.appiconset/  every size in Contents.json
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "design" / "logo"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
FONT = ROOT / "assets" / "fonts" / "AnekMalayalam-700.ttf"

# Design tokens (docs/design-tokens.md).
PRIMARY_DARK = "#0F3D22"
PRIMARY = "#1B6B3A"
ACCENT = "#F2B01E"
GROUND = "#F4F6F1"
SURFACE = "#FFFFFF"

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# The mark's content box in the master's 96 grid is centred on (48, 49) and
# reaches 43.4 from it (the upper left frond tip). Android keeps a 66 dp
# circle of the 108 dp layer safe from every mask shape: 33 / 43.4 = 0.76.
ADAPTIVE = 'translate(54 54) scale(0.76) translate(-48 -49)'

# തോട്ടം after shaping: ോ splits into the ee-sign, moved before ta, and the
# aa-sign after it; tta + virama + tta is one ligature (GSUB lookup 47 in this
# font). Checked against Chrome drawing the same text in the same font.
MALAYALAM_GLYPHS = ["uni0D47", "uni0D24", "uni0D3E", "glyph00168", "uni0D02"]


def find_browser():
    if os.environ.get("CHROME"):
        return os.environ["CHROME"]
    for name in ("chrome", "google-chrome", "chromium", "msedge"):
        if shutil.which(name):
            return shutil.which(name)
    for path in (
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    ):
        if Path(path).exists():
            return path
    sys.exit("Chrome or Edge not found; set CHROME to its path.")


def master():
    svg = (LOGO / "thottam-logo.svg").read_text(encoding="utf-8")
    start = svg.index('<g id="mark">')
    return svg[start : svg.rindex("</g>") + 4]


def tile(mark, radius):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96">'
        f'<rect width="96" height="96" rx="{radius}" fill="{PRIMARY}"/>'
        f"{mark}</svg>"
    )


def layer(mark):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">'
        f'<g transform="{ADAPTIVE}">{mark}</g></svg>'
    )


def one_colour(mark):
    return mark.replace(ACCENT, SURFACE).replace(GROUND, SURFACE)


class Renderer:
    def __init__(self, tmp):
        self.browser = find_browser()
        self.tmp = Path(tmp)

    def png(self, svg, size, out, transparent):
        svg = svg.replace("<svg ", f'<svg width="{size}" height="{size}" ', 1)
        page = self.tmp / "icon.html"
        page.write_text(
            "<!doctype html><style>html,body{margin:0;background:transparent}"
            f"svg{{display:block}}</style>{svg}",
            encoding="utf-8",
        )
        args = [
            self.browser,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            f"--user-data-dir={self.tmp / 'profile'}",
            "--force-device-scale-factor=1",
            f"--window-size={size},{size}",
            f"--screenshot={out}",
            page.as_uri(),
        ]
        if transparent:
            # Without it the PNG has no alpha channel, which the App Store needs.
            args.insert(1, "--default-background-color=00000000")
        subprocess.run(args, check=True, capture_output=True)
        print(out.relative_to(ROOT))


def glyph_run(font, names, size, x, baseline, colour):
    """Outlines a shaped glyph run; returns (svg path, bounds)."""
    glyphs = font.getGlyphSet()
    scale = size / font["head"].unitsPerEm
    svg_pen = SVGPathPen(glyphs)
    bounds_pen = BoundsPen(glyphs)
    for name in names:
        matrix = (scale, 0, 0, -scale, x, baseline)
        glyphs[name].draw(TransformPen(svg_pen, matrix))
        glyphs[name].draw(TransformPen(bounds_pen, matrix))
        x += font["hmtx"][name][0] * scale
    return f'<path fill="{colour}" d="{svg_pen.getCommands()}"/>', bounds_pen.bounds


def lockup(mark):
    font = TTFont(FONT)
    cmap = font.getBestCmap()
    latin = [cmap[ord(c)] for c in "Thottam"]
    left = 96 + 22
    # Draw once at baseline 0 to measure, then stack the two lines and centre
    # the block on the tile.
    _, (_, ml_top, _, ml_bottom) = glyph_run(font, MALAYALAM_GLYPHS, 46, left, 0, "")
    _, (_, en_top, _, en_bottom) = glyph_run(font, latin, 22, left, 0, "")
    gap = 10
    height = (ml_bottom - ml_top) + gap + (en_bottom - en_top)
    top = (96 - height) / 2
    ml_base = top - ml_top
    en_base = ml_base + (ml_bottom - 0) + gap - en_top
    ml, (_, _, ml_right, _) = glyph_run(
        font, MALAYALAM_GLYPHS, 46, left, ml_base, PRIMARY_DARK
    )
    en, (_, _, en_right, _) = glyph_run(font, latin, 22, left, en_base, PRIMARY)
    width = round(max(ml_right, en_right) + 4)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} 96">\n'
        "  <title>Thottam തോട്ടം</title>\n"
        "  <!-- Built by tool/build_icons.py from thottam-logo.svg; the name is\n"
        "       Anek Malayalam 700 as outlines, so no font is needed. -->\n"
        f'  <rect width="96" height="96" rx="24" fill="{PRIMARY}"/>\n'
        f"  {mark}\n  {ml}\n  {en}\n</svg>\n"
    )
    (LOGO / "thottam-logo-lockup.svg").write_text(svg, encoding="utf-8", newline="\n")
    print("design/logo/thottam-logo-lockup.svg")


def main():
    mark = master()
    lockup(mark)
    with tempfile.TemporaryDirectory() as tmp:
        r = Renderer(tmp)
        for density, k in DENSITIES.items():
            folder = RES / f"mipmap-{density}"
            folder.mkdir(exist_ok=True)
            r.png(tile(mark, 24), round(48 * k), folder / "ic_launcher.png", True)
            r.png(layer(mark), round(108 * k), folder / "ic_launcher_foreground.png", True)
            r.png(
                layer(one_colour(mark)),
                round(108 * k),
                folder / "ic_launcher_monochrome.png",
                True,
            )
        contents = json.loads((IOS / "Contents.json").read_text(encoding="utf-8"))
        for image in contents["images"]:
            points = float(image["size"].split("x")[0])
            scale = int(image["scale"].rstrip("x"))
            # iOS rounds the corners itself and wants no transparency.
            r.png(tile(mark, 0), round(points * scale), IOS / image["filename"], False)


if __name__ == "__main__":
    main()
