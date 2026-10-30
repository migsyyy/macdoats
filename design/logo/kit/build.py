"""MacDoats symbol masters, drawn with true arcs. Unrotated book space, then rotate(-15)."""
def cmd(cx, cy, h, r, sw):
    """⌘ as fill paths: outer contour, then the 4 loop holes and the centre square (islands)."""
    w, R = sw / 2, r + sw / 2
    rot = lambda p, k: [(p[0], p[1]), (-p[1], p[0]), (-p[0], -p[1]), (p[1], -p[0])][k]
    d = []
    for k in range(4):
        P = [rot(p, k) for p in [(h + w, h - w), (h + r, h - w), (h - w, h + r), (h - w, h + w)]]
        P = [(cx + x, cy + y) for x, y in P]
        d.append(f"{'M' if k == 0 else 'L'}{P[0][0]:g},{P[0][1]:g} L{P[1][0]:g},{P[1][1]:g} "
                 f"A{R:g},{R:g} 0 1 1 {P[2][0]:g},{P[2][1]:g} L{P[3][0]:g},{P[3][1]:g}")
    d.append("Z")
    ri = r - w
    for sx, sy in [(1, 1), (-1, 1), (-1, -1), (1, -1)]:
        x, y = cx + sx * (h + r), cy + sy * (h + r)
        d.append(f"M{x - ri:g},{y:g} a{ri:g},{ri:g} 0 1 0 {2 * ri:g},0 a{ri:g},{ri:g} 0 1 0 {-2 * ri:g},0Z")
    s = h - w
    d.append(f"M{cx - s:g},{cy - s:g} H{cx + s:g} V{cy + s:g} H{cx - s:g}Z")
    return " ".join(d)

def book(small=False):
    """Spine strip, cover+ribbon outline, page-edge strips. Cover 58..198 × 32..206, r16."""
    g = 14 if small else 12          # spine groove
    sp = 80 if small else 80
    cx0 = sp + g
    parts = [f"M{sp},32 H74 A16,16 0 0 0 58,48 V190 A16,16 0 0 0 74,206 H{sp}Z"]
    if small:  # no page edge: cover runs to the bottom, ribbon hangs from it
        parts.append(f"M{cx0},32 H182 A16,16 0 0 1 198,48 V190 A16,16 0 0 1 182,206 H164 V246 L151,233 L138,246 V206 H{cx0}Z")
    else:
        parts.append(f"M{cx0},32 H182 A16,16 0 0 1 198,48 V188 H164 V246 L153,235 L142,246 V188 H{cx0}Z")
        parts.append(f"M{cx0},197 H142 V206 H{cx0}Z")
        parts.append("M164,197 H196.39 A16,16 0 0 1 182,206 H164Z")
    return " ".join(parts)

CMD = dict(cx=145, cy=110, h=10, r=9, sw=8)        # 64 wide on a 106 cover: 21 margins
CMD_SMALL = dict(cx=146, cy=119, h=9, r=10, sw=11)  # 69 wide on a 104 cover, bolder for 16 px
CMD_REV = dict(CMD, sw=7)   # reversed: thinner holes' frame reads equal on dark (irradiation)
T = 'transform="translate(2 -2) rotate(-15 128 128)"'  # optically centred (bbox centre at 128,126)
H = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><title>MacDoats</title>'

def mono(fill="#000", small=False, c=CMD):
    return H + f'<path {T} fill="{fill}" fill-rule="evenodd" d="{book(small)} {cmd(**c)}"/></svg>'

RED, GOLD, INK = "#B8312A", "#E0C387", "#15181C"
def colour(small=False):
    c = CMD_SMALL if small else CMD
    return (H + f'<g {T}><path fill="{RED}" fill-rule="evenodd" d="{book(small)} {cmd(**c)}"/>'
            f'<path fill="{GOLD}" fill-rule="evenodd" d="{cmd(**c)}"/></g></svg>')

if __name__ == "__main__":
    files = {
        "macdoats-symbol.svg": mono(),
        "macdoats-symbol-small.svg": mono(small=True, c=CMD_SMALL),
        "macdoats-symbol-reversed.svg": mono("#fff", c=CMD_REV),
        "macdoats-symbol-color.svg": colour(),
        "macdoats-symbol-color-small.svg": colour(small=True),
    }
    for n, s in files.items(): open(n, "w").write(s)
    print("\n".join(files))
