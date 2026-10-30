import AppKit
import SwiftUI

/// `MacDoats --screenshots <dir>`: renders the real settings views (factory settings, Dota focused)
/// to @2x PNGs for the README. Views are hosted in an offscreen window so AppKit-backed parts
/// (scroll bars, menus) draw too.
func renderScreenshots(to dir: String) {
    _ = NSApplication.shared
    let engine = Engine(preview: true)
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    func snap<V: View>(_ view: V, _ name: String, width: CGFloat? = nil, height: CGFloat? = nil) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let fit = host.fittingSize
        let size = NSSize(width: width ?? fit.width, height: height ?? fit.height)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))  // let scrollers swap in and layout settle
        host.layoutSubtreeIfNeeded()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }

    snap(Panel(engine: engine).clipShape(RoundedRectangle(cornerRadius: 10)), "panel", width: 400)
    snap(AdvancedView(engine: engine).clipShape(RoundedRectangle(cornerRadius: 10)), "customize", width: 460, height: 420)
    snap(HStack(spacing: 18) {
        ForEach([(MenuIcon.idle, "Dota running"), (MenuIcon.active, "Cursor locked")], id: \.1) { icon, label in
            VStack(spacing: 6) {
                Image(nsImage: icon).renderingMode(icon.isTemplate ? .template : .original).foregroundStyle(.white)
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6)).fixedSize()
            }
        }
    }
    .padding(.horizontal, 18).padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.13))), "menubar")
}
