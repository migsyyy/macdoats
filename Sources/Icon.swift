import AppKit

/// Menu bar icon: the DotA 1 Necronomicon — a closed book with a crease, page edge, a sigil on
/// the cover and a bookmark ribbon hanging out the bottom.
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

    /// Draws in an 18×18 y-up space with black; cut-outs use .clear. Tilted like the
    /// three-quarter DotA 1 item art, scaled down so the corners stay inside the box.
    private static func drawGlyph() {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let tilt = NSAffineTransform()
        tilt.translateX(by: 9, yBy: 9)
        tilt.rotate(byDegrees: -14)
        tilt.scale(by: 0.88)
        tilt.translateX(by: -9.25, yBy: -8.55) // centre of the untilted art
        tilt.concat()

        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 3.5, y: 4, width: 11.5, height: 12.5), xRadius: 1.6, yRadius: 1.6).fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(rect: NSRect(x: 5.4, y: 4, width: 1, height: 12.5)).fill()      // spine crease
        NSBezierPath(rect: NSRect(x: 6.4, y: 5.0, width: 8.6, height: 0.8)).fill()   // page edge
        let sigil = NSBezierPath()                                                    // diamond on the cover
        sigil.move(to: NSPoint(x: 10.4, y: 13.6))
        sigil.line(to: NSPoint(x: 12.6, y: 11.2))
        sigil.line(to: NSPoint(x: 10.4, y: 8.8))
        sigil.line(to: NSPoint(x: 8.2, y: 11.2))
        sigil.close()
        sigil.fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        let ribbon = NSBezierPath()                                                   // bookmark, V-notched
        ribbon.move(to: NSPoint(x: 11.2, y: 5.8))
        ribbon.line(to: NSPoint(x: 13.4, y: 5.8))
        ribbon.line(to: NSPoint(x: 13.4, y: 0.6))
        ribbon.line(to: NSPoint(x: 12.3, y: 1.8))
        ribbon.line(to: NSPoint(x: 11.2, y: 0.6))
        ribbon.close()
        ribbon.fill()
    }
}
