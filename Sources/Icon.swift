import AppKit

/// Menu bar icon: the MacDoats mark — the DotA 1 Necronomicon with ⌘ as its cover sigil.
enum MenuIcon {
    static let size = NSSize(width: 18, height: 18)

    static let pillSize = NSSize(width: 24, height: 18)
    static let red = NSColor(red: 0.72, green: 0.19, blue: 0.16, alpha: 1)
    static let green = NSColor(red: 0x6C / 255.0, green: 0xB3 / 255.0, blue: 0x3F / 255.0, alpha: 1) // Radiant
    static let gold = NSColor(red: 0xE0 / 255.0, green: 0xC3 / 255.0, blue: 0x87 / 255.0, alpha: 1)

    /// Idle: template glyph, so macOS draws it white on a dark menu bar (black on a light one).
    static let idle: NSImage = {
        let img = NSImage(size: size, flipped: false) { _ in drawGlyph(.command); return true }
        img.isTemplate = true
        return img
    }()

    /// Idle with the gold "auto-accept armed" dot. A template image can't carry colour, so the glyph
    /// is drawn in the menu bar's text colour (the handler runs with the bar's appearance).
    static let idleArmed = NSImage(size: size, flipped: false) { r in
        tinted(.command, .controlTextColor).draw(in: r)
        armedDot(in: r)
        return true
    }

    /// Cursor lock engaged: white book on a filled Dota-red pill, like the mic-in-use indicator.
    static let active = pill(red, .command, armed: false)
    static let activeArmed = pill(red, .command, armed: true)

    /// In the queue: the ⌘ becomes a 4-point star on a Radiant-green pill. 12 frames cover 0–90°;
    /// the star's 4-fold symmetry repeats beyond that.
    static let queueFrames = (0..<12).map { pill(green, .star(CGFloat($0) * 7.5), armed: false) }
    static let queueFramesArmed = (0..<12).map { pill(green, .star(CGFloat($0) * 7.5), armed: true) }

    enum Sigil { case command, star(CGFloat) } // star angle in degrees, clockwise

    private static func pill(_ color: NSColor, _ sigil: Sigil, armed: Bool) -> NSImage {
        NSImage(size: pillSize, flipped: false) { r in
            color.setFill()
            NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            tinted(sigil, .white).draw(in: NSRect(x: (pillSize.width - size.width) / 2, y: 0, width: size.width, height: size.height))
            if armed { armedDot(in: r) }
            return true
        }
    }

    private static func tinted(_ sigil: Sigil, _ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { g in
            drawGlyph(sigil)
            color.set()
            g.fill(using: .sourceAtop)
            return true
        }
    }

    private static func armedDot(in r: NSRect) {
        let d: CGFloat = 6
        let dot = NSRect(x: r.maxX - d, y: r.maxY - d, width: d, height: d)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
        gold.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    /// The MacDoats mark (small cut, see design/logo/kit/build.py): tilted tome, spine groove,
    /// ribbon, ⌘ cut out of the cover. Drawn in the logo's 256-unit y-down space, scaled to 18 pt.
    private static func drawGlyph(_ sigil: Sigil) {
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
        switch sigil {
        case .command: command(cx: 146, cy: 119, h: 9, r: 10, sw: 11).fill()
        case .star(let angle): star(cx: 146, cy: 119, outer: 34.5, inner: 10, angle: angle).fill()
        }
    }

    /// Four-point star the size of the ⌘: tips reach its box (h + r + r + sw/2 = 34.5 from centre).
    /// y-down space, so a positive angle turns it clockwise on screen.
    private static func star(cx: CGFloat, cy: CGFloat, outer: CGFloat, inner: CGFloat, angle: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<8 {
            let a = (angle - 90 + CGFloat(i) * 45) * .pi / 180
            let rad = i.isMultiple(of: 2) ? outer : inner
            let p = NSPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close()
        return path
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
