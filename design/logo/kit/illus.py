"""Detailed app-icon art (run with a Python that has shapely).: the Necronomicon seen from below at an angle (front cover, page block
on the bottom and fore-edge, back cover, ribbon). Oblique projection; each face is an SVG matrix."""
import math, build
from shapely.geometry import Polygon
from shapely.ops import unary_union
W, HB, D, R = 130, 164, 42, 10          # cover width/height, thickness, corner radius (book units)
th = math.radians(-15); FS = 0.95       # tilt; vertical foreshortening from below
ex = (math.cos(th), math.sin(th)); ey = (-math.sin(th) * FS, math.cos(th) * FS); ez = (-0.30, 0.52)
RED, RED_D, RED_DD, GOLD, GOLD_D, PAGE, PAGE_L, INK = "#B8312A", "#8E2520", "#6A1814", "#E0C387", "#B98E45", "#EAD9B2", "#BFA676", "#15181C"
O = (0, 0)
def P(u, v, z=0): return (O[0] + u * ex[0] + v * ey[0] + z * ez[0], O[1] + u * ex[1] + v * ey[1] + z * ez[1])
# centre the book's middle on (126, 116)
c = P(W / 2, HB / 2, D / 2); O = (128 - c[0], 112 - c[1])
def M(z): o = P(0, 0, z); return f'matrix({ex[0]:.4f} {ex[1]:.4f} {ey[0]:.4f} {ey[1]:.4f} {o[0]:.2f} {o[1]:.2f})'
def pts(*ps): return " ".join(f"{x:.2f},{y:.2f}" for x, y in ps)
# square corners at the spine, rounded on the fore-edge (how real covers are cut)
COVER_D = (f'M0,0 H10 L13,2.4 L16,0 H{W - R} A{R},{R} 0 0 1 {W},{R} V{HB - R} A{R},{R} 0 0 1 {W - R},{HB} '
           f'H16 L13,{HB - 2.4} L10,{HB} H0Z')  # V dips: the joint groove meeting top/bottom edges
cover = f'<path d="{COVER_D}"/>'

def art():
    """Back to front: shadow, back cover, spine (full height, rounded), page block underneath,
    ribbon between the pages, front cover. Camera below and slightly left, so the spine shows."""
    s = []
    B = 7                                                       # spine bulge (book units)
    JU, JZ = 0, 3                                             # joint: the pinch where spine meets each board
    def spine_curve(v): return P(JU, v, JZ), P(-16, v, D / 2), P(JU, v, D - JZ)
    def spine_edge(v):  # cover edge -> joint -> rounded spine -> joint -> back cover edge
        j0, c, j1 = spine_curve(v)
        return f"{pts(P(0, v, 0))} L{pts(P(0, v, 3))} L{pts(j0)} Q{pts(c)} {pts(j1)} L{pts(P(0, v, D - 3))} L{pts(P(0, v, D))}"
    def spine_edge_rev(v):
        j0, c, j1 = spine_curve(v)
        return f"{pts(P(0, v, D))} L{pts(P(0, v, D - 3))} L{pts(j1)} Q{pts(c)} {pts(j0)} L{pts(P(0, v, 3))} L{pts(P(0, v, 0))}"
    s.append(f'<ellipse cx="{P(W/2, HB, D/2)[0]:.1f}" cy="{P(W/2, HB, D/2)[1] + 20:.1f}" rx="84" ry="12" fill="#000" opacity=".35"/>')
    s.append(f'<g transform="{M(D)}" fill="{RED_DD}">{cover}</g>')                        # back cover
    s.append(f'<g transform="{M(D - 3)}" fill="{RED_D}">{cover}</g>')
    # spine: the cross-section (board edge -> joint pinch -> rounded back -> joint -> board edge)
    # swept down the book's height. Outline = union of the swept segments, so the crown silhouette
    # runs the full height. Bands and the crown highlight stop at the silhouette (the visible half).
    def section(v, n=28):
        j0, c, j1 = spine_curve(v)
        q = [((1 - t) ** 2 * j0[0] + 2 * (1 - t) * t * c[0] + t * t * j1[0],
              (1 - t) ** 2 * j0[1] + 2 * (1 - t) * t * c[1] + t * t * j1[1]) for t in (i / n for i in range(n + 1))]
        return [P(0, v, 0), P(0, v, 3)] + q + [P(0, v, D - 3), P(0, v, D)], q
    top, qt = section(0); bot, qb = section(HB)
    body = unary_union([Polygon([top[k], top[k + 1], bot[k + 1], bot[k]]).buffer(0.05) for k in range(len(top) - 1)])
    s.append(f'<path fill="{RED_D}" d="M' + " L".join(pts(p) for p in body.exterior.coords) + 'Z"/>')
    nrm = (-ey[1], ey[0])                                                                 # points away from the book, to the left
    k_sil = max(range(len(qt)), key=lambda k: nrm[0] * qt[k][0] + nrm[1] * qt[k][1])
    def visible(v):
        _, q = section(v); return q[:k_sil + 1]
    hl = [p for p in (visible(8)[-7], visible(HB - 8)[-7])]                                # crown highlight, just inside the silhouette
    s.append(f'<line stroke="{RED}" stroke-opacity=".55" stroke-width="2.5" stroke-linecap="round" x1="{hl[0][0]:.2f}" y1="{hl[0][1]:.2f}" x2="{hl[1][0]:.2f}" y2="{hl[1][1]:.2f}"/>')
    for v in (22, 34, HB - 34, HB - 22):                                                  # raised gold bands, visible half only
        s.append(f'<polyline fill="none" stroke="{GOLD_D}" stroke-width="4.5" stroke-linecap="round" points="{pts(*visible(v))}"/>')
    s.append(f'<path fill="{RED_DD}" d="M{spine_edge(HB)} L{pts(P(6, HB, D))} L{pts(P(6, HB, 0))}Z"/>')  # spine foot
    b, cc = (W - 3, HB - 3), (6, HB - 3)                                                   # page block, underside only
    s.append(f'<polygon fill="{PAGE}" points="{pts(P(*b, 3), P(*b, D - 3), P(*cc, D - 3), P(*cc, 3))}"/>')
    for i in range(1, 7):
        z = 3 + i / 7 * (D - 6)
        s.append(f'<line stroke="{PAGE_L}" stroke-width=".8" x1="{P(*b, z)[0]:.2f}" y1="{P(*b, z)[1]:.2f}" x2="{P(*cc, z)[0]:.2f}" y2="{P(*cc, z)[1]:.2f}"/>')
    # ribbon: a flat silk strip in the book's own projection. Its top edge lies exactly on the page
    # block's underside along the mid-depth page line; it leaves the pages along +v, swings toward the
    # viewer (z falls) and bends against the tilt so the tail hangs straight down.
    rw, L, n = 22, 60, 24
    u0, zm, v0 = (cc[0] + b[0]) / 2 - rw / 2, D * 0.5, HB - 3
    def edge(du, dz=0):
        out = []
        for i in range(n + 1):
            t = i / n
            v = v0 + L * t
            u = u0 + du - math.tan(-th) * FS * L * 0.55 * t * t   # bend toward gravity
            z = zm - 12 * t * t + dz                               # swing toward the viewer
            out.append(P(u, v, z))
        return out
    def strip(dz=0):
        lft, rgt = edge(0, dz), edge(rw, dz)
        tip = P(u0 + rw / 2 - math.tan(-th) * FS * L * 0.55, v0 + L - rw * 0.45, zm - 12 + dz)  # V notch
        return "M" + " L".join(pts(p) for p in lft) + f" L{pts(tip)} L" + " L".join(pts(p) for p in reversed(rgt)) + "Z"
    top, bot = P(u0, v0, zm), P(u0, v0 + L, zm - 12)
    s.append('<defs><linearGradient id="silk" gradientUnits="userSpaceOnUse" '
             f'x1="{top[0]:.1f}" y1="{top[1]:.1f}" x2="{bot[0]:.1f}" y2="{bot[1]:.1f}">'
             '<stop offset="0" stop-color="#8A6425"/><stop offset=".3" stop-color="#C99A48"/>'
             '<stop offset=".62" stop-color="#E9C77D"/><stop offset="1" stop-color="#B4863A"/></linearGradient></defs>')
    s.append(f'<path fill="#6E4D18" d="{strip(dz=1.6)}"/>')            # silk edge (thickness)
    s.append(f'<path fill="url(#silk)" d="{strip()}"/>')
    s.append(f'<g transform="{M(3)}" fill="{RED_D}">{cover}</g>')                          # front cover edge
    k = dict(cx=(26 + W - 10) / 2, cy=HB / 2, h=9.5, r=8.5, sw=7.5)                                    # 60 wide, centred in the frame
    shadow = dict(k, cx=k["cx"] + 0.6, cy=k["cy"] + 1.0)
    face = (f'<path d="{COVER_D}" fill="{RED}"/>'
            '<defs><linearGradient id="shoulder" x1="0" x2="1"><stop offset="0" stop-color="#8E2520"/>'
            '<stop offset=".5" stop-color="#C7443B"/><stop offset="1" stop-color="#9C2A24"/></linearGradient>'
            '<linearGradient id="groove" x1="0" x2="1"><stop offset="0" stop-color="#5A130F"/>'
            '<stop offset=".45" stop-color="#6E1914"/><stop offset="1" stop-color="#B0352E"/></linearGradient></defs>'
            f'<path fill="url(#shoulder)" d="M0,0 H10 V{HB} H0Z"/>'
            f'<path fill="url(#groove)" d="M10,0 L13,2.4 L16,0 V{HB} L13,{HB - 2.4} L10,{HB}Z"/>'
            f'<rect x="26" y="12" width="{W - 36}" height="{HB - 24}" rx="4" fill="none" stroke="{GOLD}" stroke-width="2.5"/>'
            f'<path fill="{GOLD}" d="M{W - 24},0 H{W - R} A{R},{R} 0 0 1 {W},{R} V24Z"/>'
            f'<path fill="{GOLD}" d="M{W - 24},{HB} H{W - R} A{R},{R} 0 0 0 {W},{HB - R} V{HB - 24}Z"/>'
            f'<path fill="{RED_DD}" fill-rule="evenodd" d="{build.cmd(**shadow)}"/>'
            f'<path fill="{GOLD}" fill-rule="evenodd" d="{build.cmd(**k)}"/>')
    s.append(f'<g transform="{M(0)}">{face}</g>')
    return "".join(s)

def appicon():
    k = 824 * 0.86 / 256; off = 100 + (824 - 256 * k) / 2
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><title>MacDoats</title>'
            '<defs><radialGradient id="bg" cx=".5" cy=".38" r=".7"><stop offset="0" stop-color="#2A3036"/>'
            f'<stop offset="1" stop-color="{INK}"/></radialGradient></defs>'
            '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>'
            f'<g transform="translate({off:.1f} {off:.1f}) scale({k:.4f})">{art()}</g></svg>')

open("macdoats-appicon.svg", "w").write(appicon())
open("macdoats-illustration.svg", "w").write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>MacDoats</title>{art()}</svg>')

def appicon_small():  # flat mark on the same tile, for 16–64 px slots
    sym = build.colour(True).split('<title>MacDoats</title>')[1].rsplit('</svg>', 1)[0]
    k = 824 * 0.74 / 256; off = 100 + (824 - 256 * k) / 2
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><title>MacDoats</title>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="{INK}"/>'
            f'<g transform="translate({off:.1f} {off - 12:.1f}) scale({k:.4f})">{sym}</g></svg>')
open("macdoats-appicon-small.svg", "w").write(appicon_small())
