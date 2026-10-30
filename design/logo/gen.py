import math, sys
from shapely.geometry import box, Polygon, LineString, Point
from shapely.ops import unary_union
from shapely import affinity
R = 24  # arc resolution
def rbox(x0, y0, x1, y1, r): return box(x0+r, y0+r, x1-r, y1-r).buffer(r, quad_segs=R)
def arc(cx, cy, r, a0, a1, n=48):
    return [(cx + r*math.cos(math.radians(a0 + (a1-a0)*i/n)), cy + r*math.sin(math.radians(a0 + (a1-a0)*i/n))) for i in range(n+1)]
def command(cx, cy, h, r, sw, inner="square"):
    lines = []
    for sx, sy in [(1,1),(1,-1),(-1,-1),(-1,1)]:
        ccx, ccy = cx+sx*(h+r), cy+sy*(h+r)
        a0 = 180 if sx > 0 else 0
        # 3/4 loop from the vertical tangent point round the outside to the horizontal one
        start = math.degrees(math.atan2((cy+sy*(h+r))-ccy, (cx+sx*h)-ccx))
        end = math.degrees(math.atan2((cy+sy*h)-ccy, (cx+sx*(h+r))-ccx))
        if sx*sy > 0: end = end - 360 if end > start else end
        else: end = end + 360 if end < start else end
        pad = 3 if end > start else -3
        lines.append(LineString(arc(ccx, ccy, r, start - pad, end + pad)))
    for sx in (1, -1): lines.append(LineString([(cx+sx*h, cy-h-r), (cx+sx*h, cy+h+r)]))
    if inner == "square":
        for sy in (1, -1): lines.append(LineString([(cx-h-r, cy+sy*h), (cx+h+r, cy+sy*h)]))
    else:  # rune: horizontals only as stubs, an X (Dagaz) across the square
        for sx in (1, -1):
            for sy in (1, -1): lines.append(LineString([(cx+sx*(h+r), cy+sy*h), (cx+sx*h, cy+sy*h)]))
        lines += [LineString([(cx-h, cy-h), (cx+h, cy+h)]), LineString([(cx+h, cy-h), (cx-h, cy+h)])]
    return unary_union([l.buffer(sw/2, cap_style="flat", join_style="mitre", quad_segs=R) for l in lines])
def path(g):
    polys = [g] if g.geom_type == "Polygon" else list(g.geoms)
    d = []
    for p in polys:
        for ring in [p.exterior, *p.interiors]:
            c = list(ring.coords)[:-1]
            d.append("M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in c) + "Z")
    return " ".join(d)
def svg(g, name):
    g = g.simplify(0.15)
    open(name, "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path fill="#000" fill-rule="evenodd" d="{path(g)}"/></svg>')

# A — Tome of Command
book = rbox(58, 32, 198, 206, 16)
book = book.difference(box(80, 20, 92, 220)).difference(box(92, 188, 210, 197))
book = book.difference(command(145, 110, 16, 14, 11))
ribbon = Polygon([(158, 186), (184, 186), (184, 244), (171, 231), (158, 244)])
a = affinity.rotate(unary_union([book, ribbon]), -15, origin=(128, 128))
svg(affinity.translate(a, 6, 4), "a-tome-v2.svg")

# B — MD bind-rune ⌘: the inner square becomes Dagaz ᛞ (D), whose upper half is Mannaz ᛗ (M)
svg(command(128, 128, 48, 24, 18, inner="rune"), "b-rune-v2.svg")

# C — Item-slot key: Mac keycap with a WC3 chamfered slot, ⌘ inside
outer = rbox(20, 20, 236, 236, 52)
c0, c1, ch = 50, 206, 22
slot = Polygon([(c0+ch, c0), (c1-ch, c0), (c1, c0+ch), (c1, c1-ch), (c1-ch, c1), (c0+ch, c1), (c0, c1-ch), (c0, c0+ch)])
c = outer.difference(slot).union(command(128, 128, 19, 16, 13))
svg(c, "c-slot-v2.svg")
