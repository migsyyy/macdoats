"""Outline 'MacDoats' in Inter SemiBold (OFL) and build the lockups. Run with the venv python."""
import sys
import uharfbuzz as hb
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import build

FONT, TEXT, WGHT, OPSZ, TRACK = sys.argv[1], "MacDoats", 600, 32, -12  # tracking in font units (-1.2 % of 1000? see upm)
blob = hb.Blob.from_file_path(FONT); face = hb.Face(blob); font = hb.Font(face)
font.set_variations({"wght": WGHT, "opsz": OPSZ})
buf = hb.Buffer(); buf.add_str(TEXT); buf.guess_segment_properties(); hb.shape(font, buf, {"kern": True, "liga": True})
tt = instantiateVariableFont(TTFont(FONT), {"wght": WGHT, "opsz": OPSZ})
gs = tt.getGlyphSet(); upm = tt["head"].unitsPerEm; cap = tt["OS/2"].sCapHeight
order = tt.getGlyphOrder()

def wordmark_path(scale, x0, baseline):
    pen = SVGPathPen(gs); x = 0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        tp = TransformPen(pen, (scale, 0, 0, -scale, x0 + (x + pos.x_offset) * scale, baseline))
        gs[order[info.codepoint]].draw(tp)
        x += pos.x_advance + TRACK * upm / 1000
    return pen.getCommands(), (x - TRACK * upm / 1000) * scale

def svg(w, h, body): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}"><title>MacDoats</title>{body}</svg>'
sym = lambda fill: f'<path {build.T} fill="{fill}" fill-rule="evenodd" d="{build.book()} {build.cmd(**build.CMD)}"/>'
sym_c = f'<g {build.T}><path fill="{build.RED}" fill-rule="evenodd" d="{build.book()} {build.cmd(**build.CMD)}"/><path fill="{build.GOLD}" fill-rule="evenodd" d="{build.cmd(**build.CMD)}"/></g>'

# Wordmark alone: cap height 120 on a 256-tall artboard? keep tight: cap 100, padding 0.
s = 100 / cap
d, w = wordmark_path(s, 0, 100)
open("macdoats-wordmark.svg", "w").write(svg(w, 100 + 0.25 * cap * s, f'<path fill="#15181C" d="{d}"/>'))

# Horizontal lockup: symbol 256, wordmark cap = 0.40 × symbol height, optically centred, gap = ⌘ loop diameter ×2.
for name, symbody, ink in [("horizontal", sym("#15181C"), "#15181C"), ("horizontal-color", sym_c, "#15181C"),
                           ("horizontal-reversed", sym("#fff"), "#fff"), ("horizontal-color-dark", sym_c, "#fff")]:
    s = 82 / cap; base = 128 + 41
    d, w = wordmark_path(s, 256 + 6, base)
    open(f"macdoats-{name}.svg", "w").write(svg(256 + 6 + w + 8, 256, symbody + f'<path fill="{ink}" d="{d}"/>'))

# Stacked: symbol centred above, wordmark below.
s = 46 / cap
d, w = wordmark_path(s, 0, 0)
W = max(256, w) + 16
open("macdoats-stacked.svg", "w").write(svg(W, 256 + 18 + 46 + 14, f'<g transform="translate({(W - 256) / 2:.1f} 0)">{sym("#15181C")}</g>'
     + f'<path fill="#15181C" transform="translate({(W - w) / 2:.1f} {256 + 18 + 46})" d="{d}"/>'))
print("ok", upm, cap)
