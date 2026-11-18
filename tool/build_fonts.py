"""Cut the bundled fonts to the weights docs/design-tokens.md lists.

Sources are the variable fonts from https://github.com/google/fonts (ofl/,
commit 7af0d90b4d53, 2026-11-17):
AnekMalayalam[wdth,wght].ttf, Inter[opsz,wght].ttf and
NotoSansMalayalam[wdth,wght].ttf, downloaded into one folder as
AnekMalayalam.ttf, Inter.ttf and NotoSansMalayalam.ttf.

Usage: python tool/build_fonts.py <source folder>
Needs fonttools. Writes static .ttf files to assets/fonts/.
"""

import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts")

# family file -> (output name, weights, pinned axes, unicode ranges or None for all)
LATIN = (
    list(range(0x20, 0x7F))  # Basic Latin
    + list(range(0xA0, 0x100))  # Latin-1 (×, °, ½ ...)
    + list(range(0x2010, 0x2028))  # dashes, quotes, bullet, ellipsis
    + list(range(0x2030, 0x205F))
    + [0x20B9, 0x2212, 0x2192, 0x2190]  # ₹, minus, arrows
)
FAMILIES = {
    "AnekMalayalam.ttf": ("AnekMalayalam", [600, 700], {"wdth": 100}, None),
    "Inter.ttf": ("Inter", [400, 500, 600, 700], {"opsz": 14}, LATIN),
    "NotoSansMalayalam.ttf": ("NotoSansMalayalam", [400, 500, 600, 700], {"wdth": 100}, None),
}


def main(src: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    for file, (name, weights, pinned, unicodes) in FAMILIES.items():
        for weight in weights:
            font = TTFont(os.path.join(src, file))
            font = instancer.instantiateVariableFont(font, {**pinned, "wght": weight})
            options = subset.Options()
            options.layout_features = ["*"]  # keep tnum and Malayalam shaping
            options.name_IDs = ["*"]  # keep copyright and licence fields
            options.notdef_outline = True
            sub = subset.Subsetter(options)
            sub.populate(unicodes=unicodes or font.getBestCmap().keys())
            sub.subset(font)
            out = os.path.join(OUT, f"{name}-{weight}.ttf")
            font.save(out)
            print(f"{out}: {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main(sys.argv[1])
