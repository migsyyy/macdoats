import AppKit

/// Menu bar icon: the MacDoats mark — the DotA 1 Necronomicon with ⌘ as its cover sigil.
enum MenuIcon {
    static let size = NSSize(width: 18, height: 18)

    /// Idle: template glyph, so macOS draws it white on a dark menu bar (black on a light one).
    static let idle: NSImage = {
        let img = NSImage(size: size, flipped: false) { _ in drawGlyph(); return true }
        img.isTemplate = true
        return img
    }()

    /// Cursor lock engaged: white book on a filled Dota-red pill, like the mic-in-use indicator.
    static let active: NSImage = {
        let pillSize = NSSize(width: 24, height: 18)
        return NSImage(size: pillSize, flipped: false) { r in
            NSColor(red: 0.72, green: 0.19, blue: 0.16, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            let white = NSImage(size: size, flipped: false) { g in
                drawGlyph()
                NSColor.white.set()
                g.fill(using: .sourceAtop)
                return true
            }
            white.draw(in: NSRect(x: (pillSize.width - size.width) / 2, y: 0, width: size.width, height: size.height))
            return true
        }
    }()

    /// The MacDoats mark (small cut, see design/logo/kit/build.py): tilted tome, spine groove,
    /// ribbon, ⌘ cut out of the cover. Drawn in the logo's 256-unit y-down space, scaled to 18 pt.
    private static func drawGlyph() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let t = NSAffineTransform()
        t.translateX(by: 0, yBy: size.height)
        t.scale(by: size.width / 256)
        t.scaleX(by: 1, yBy: -1)            // y-down, like the SVG
        t.translateX(by: 130, yBy: 126)     // translate(2 -2) rotate(-15 128 128)
        t.rotate(byDegrees: -15)
        t.translateX(by: -128, yBy: -128)
        t.concat()

        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 58, y: 32, width: 140, height: 174), xRadius: 16, yRadius: 16).fill()
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 138, y: 200))
        for p in [(164, 200), (164, 246), (151, 233), (138, 246)] { ribbon.line(to: NSPoint(x: p.0, y: p.1)) }
        ribbon.close()
        ribbon.fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(rect: NSRect(x: 80, y: 32, width: 14, height: 174)).fill()  // spine groove
        command(cx: 146, cy: 119, h: 9, r: 10, sw: 11).fill()
    }

    /// ⌘ as one even-odd path: outer contour (four 270° loops joined by straight sides), plus
    /// the loop holes and centre square as islands so they stay filled.
    private static func command(cx: CGFloat, cy: CGFloat, h: CGFloat, r: CGFloat, sw: CGFloat) -> NSBezierPath {
        let w = sw / 2, big = r + w
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        func rot(_ p: CGPoint, _ k: Int) -> CGPoint {
            var q = p
            for _ in 0..<k { q = CGPoint(x: -q.y, y: q.x) }
            return CGPoint(x: cx + q.x, y: cy + q.y)
        }
        func deg(_ p: CGPoint, _ c: CGPoint) -> CGFloat { atan2(p.y - c.y, p.x - c.x) * 180 / .pi }
        for k in 0..<4 {
            let p = [CGPoint(x: h + w, y: h - w), CGPoint(x: h + r, y: h - w),
                     CGPoint(x: h - w, y: h + r), CGPoint(x: h - w, y: h + w)].map { rot($0, k) }
            let c = rot(CGPoint(x: h + r, y: h + r), k)
            if k == 0 { path.move(to: p[0]) } else { path.line(to: p[0]) }
            path.line(to: p[1])
            var end = deg(p[2], c)
            let start = deg(p[1], c)
            if end < start { end += 360 }
            path.appendArc(withCenter: c, radius: big, startAngle: start, endAngle: end, clockwise: false)
            path.line(to: p[3])
        }
        path.close()
        let inner = r - w
        for k in 0..<4 {
            let c = rot(CGPoint(x: h + r, y: h + r), k)
            path.appendOval(in: NSRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner))
        }
        let s = h - w
        path.appendRect(NSRect(x: cx - s, y: cy - s, width: 2 * s, height: 2 * s))
        return path
    }
}
