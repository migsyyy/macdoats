import AppKit
import SwiftUI

/// Dota 2 client palette: slate panels, Dota red, gold trim, Radiant green.
enum Dota {
    static func hex(_ v: UInt32) -> Color {
        Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static let panelTop = hex(0x1F242A), panelBottom = hex(0x0B0D0F)
    static let red = hex(0xB8312A), gold = hex(0xE0C387), radiant = hex(0x6CB33F)
    static let text = hex(0xDCD6CB), muted = hex(0x8A939C), idle = hex(0x56606A)
    static let warn = hex(0xE0862F), away = hex(0xD9B44A)
    static let bright = hex(0xF2F0EA)
    // Settings-menu checkbox: near-black well, pale cyan fill, violet glow when on.
    static let checkWell = hex(0x08090B), checkBorder = hex(0x2E3238), checkGlow = hex(0x6E5CF6)
    static let checkFillTop = hex(0xE6F6F6), checkFillBottom = hex(0xA7CED2)
}

/// Dota 2 settings-menu checkbox, used for every toggle.
struct DotaCheckbox: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Dota.checkWell)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(on ? Dota.checkGlow : Dota.checkBorder, lineWidth: on ? 1.5 : 1)
                    if on {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(LinearGradient(colors: [Dota.checkFillTop, Dota.checkFillBottom],
                                                 startPoint: .top, endPoint: .bottom))
                            .padding(4)
                    }
                }
                .frame(width: 17, height: 17)
                .shadow(color: on ? Dota.checkGlow.opacity(0.85) : .clear, radius: 4)
                configuration.label
                    .tracking(0.4)
                    .foregroundStyle(on ? Dota.bright : Dota.muted)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: on)
        }
        .buttonStyle(.plain)
    }
}

/// Gray: Dota not running · yellow: running, not focused · green: focused, protections live ·
/// orange: no Accessibility access, nothing works.
private struct StatusDot: View {
    @ObservedObject var engine: Engine
    var showsLabel = false

    private var status: (Color, String) {
        if !engine.trusted { return (Dota.warn, "No Accessibility access") }
        if engine.dotaFrontmost { return (Dota.radiant, "Dota 2 focused · active") }
        if engine.dotaRunning { return (Dota.away, "Dota 2 running · not focused") }
        return (Dota.idle, "Dota 2 not running")
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(status.0).frame(width: 7, height: 7)
                .shadow(color: status.0.opacity(engine.dotaFrontmost ? 0.9 : 0), radius: 3)
            if showsLabel { Text(status.1).font(.caption).foregroundStyle(Dota.muted) }
        }
    }
}

struct Panel: View {
    @ObservedObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MACDOATS").font(.headline.weight(.heavy)).tracking(2).foregroundStyle(Dota.gold)
                Spacer()
                StatusDot(engine: engine, showsLabel: true)
            }

            if !engine.trusted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Dota.warn)
                    Text("Needs Accessibility access").font(.callout)
                    Spacer()
                    Button("Grant…") {
                        engine.requestAccess()
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }

            Toggle("Lock cursor to Dota window  (⌃⌥⌘L)", isOn: $engine.lockCursor)
            if engine.dotaLocksMouse {
                Text("Dota's own \"Lock Mouse to Window\" is on, so the cursor stays locked even with this off. "
                     + "Turn it off in Dota's settings (or console: in_lock_mouse_to_window 0).")
                    .font(.caption2).foregroundStyle(Dota.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Allow Alt-Tab / ⌘Tab to switch apps", isOn: $engine.allowAltTab)
            HStack {
                Toggle("Block macOS shortcuts", isOn: $engine.blockShortcuts)
                Spacer()
                Button("Customize…") { AdvancedWindow.show(engine: engine) }
                    .buttonStyle(.borderless).foregroundStyle(Dota.gold)
            }

            Rectangle().fill(Dota.gold.opacity(0.2)).frame(height: 1)

            ModifierRow(engine: engine)
            FnKeyRow(engine: engine)

            HStack {
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption2).foregroundStyle(Dota.idle)
                Spacer()
                Button("Quit MacDoats") { NSApp.terminate(nil) }.buttonStyle(.borderless).foregroundStyle(Dota.muted)
            }
        }
        .toggleStyle(DotaCheckbox())
        .tint(Dota.red)
        .foregroundStyle(Dota.text)
        .controlSize(.small)
        .padding(18)
        .frame(width: 400)
        .background(LinearGradient(colors: [Dota.panelTop, Dota.panelBottom], startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
    }
}

/// Four squares = the four physical keys, left to right as on the keyboard. Each shows what the
/// key produces in Dota; drop one square on another to swap them.
private struct ModifierRow: View {
    @ObservedObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MODIFIER KEYS").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Dota.gold)
                Spacer()
                preset("Mac", Mod.mac)
                preset("Windows", Mod.windows)
            }
            HStack(spacing: 10) {
                ForEach(Mod.keys) { slot in square(slot) }
            }
            .frame(maxWidth: .infinity)
            Text("Click a key to choose what it does, or drag onto another to swap. Dota only.")
                .font(.caption2).foregroundStyle(Dota.muted)
        }
    }

    private func preset(_ title: String, _ layout: [Mod]) -> some View {
        let active = engine.modLayout == layout
        return Button(title) { engine.modLayout = layout }
            .buttonStyle(.borderless)
            .font(.caption.weight(active ? .bold : .regular))
            .foregroundStyle(active ? Dota.gold : Dota.muted)
    }

    private func square(_ slot: Mod) -> some View {
        let out = engine.modLayout[slot.rawValue]
        let changed = out != slot
        return VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text(out.symbol).font(.system(size: 22, weight: .semibold))
                Text(engine.modLayout == Mod.windows ? out.windowsName : out.name).font(.caption2)
            }
            .frame(width: 76, height: 66)
            .background(RoundedRectangle(cornerRadius: 8).fill(Dota.panelTop))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(changed ? Dota.red : Dota.gold.opacity(0.25), lineWidth: changed ? 1.5 : 1))
            .foregroundStyle(changed ? Dota.gold : Dota.text)
            .draggable(String(slot.rawValue)) {
                Text(out.symbol).font(.system(size: 22, weight: .semibold)).padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Dota.panelTop))
            }
            .onTapGesture { chooseOutput(for: slot) }
            .dropDestination(for: String.self) { items, _ in
                guard let from = items.first.flatMap(Int.init), from != slot.rawValue else { return false }
                withAnimation(.spring(duration: 0.25)) { engine.swapSlots(from, slot.rawValue) }
                return true
            }
            Text("\(slot.name) key").font(.system(size: 9)).foregroundStyle(Dota.muted)
        }
    }

    /// Native pop-up menu at the cursor; runs modally, so the item closures live long enough.
    private func chooseOutput(for slot: Mod) {
        let menu = NSMenu()
        for out in Mod.allCases {
            let action = MenuAction { engine.setOutput(slot.rawValue, out) }
            let item = NSMenuItem(title: "\(out.symbol)   \(out == .none ? "Off" : out.name.capitalized)",
                                  action: #selector(MenuAction.fire), keyEquivalent: "")
            item.target = action
            item.representedObject = action // NSMenuItem.target is weak
            item.state = engine.modLayout[slot.rawValue] == out ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire(_ sender: Any?) { run() }
}

/// fn opening the emoji picker is a system setting MacDoats can't change live, so show its
/// state and jump straight to it.
private struct FnKeyRow: View {
    @ObservedObject var engine: Engine

    var body: some View {
        let off = engine.fnKeyOff
        return HStack(spacing: 8) {
            Image(systemName: off ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(off ? Dota.radiant : Dota.warn)
            Text(off ? "🌐 fn key does nothing" : "🌐 fn key opens emoji / dictation")
                .font(.caption).foregroundStyle(off ? Dota.muted : Dota.text)
            Spacer()
            if !off {
                Button("Turn off…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
                .buttonStyle(.borderless).foregroundStyle(Dota.gold)
                .help("Keyboard → Press 🌐 key to → Do Nothing (may need a log out to apply)")
            }
        }
    }
}

/// Regular window (activates MacDoats) for fine-tuning the blocked shortcut list.
enum AdvancedWindow {
    private static var window: NSWindow?

    static func show(engine: Engine) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "MacDoats — Blocked Shortcuts"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AdvancedView(engine: engine))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AdvancedView: View {
    @ObservedObject var engine: Engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Block these shortcuts while Dota is focused", isOn: $engine.blockShortcuts)
            HStack {
                Group {
                    Text("SHORTCUT").frame(width: 150, alignment: .leading)
                    Text("WHAT IT DOES")
                }
                .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Dota.gold)
                Spacer()
                Button("Reset") { engine.resetShortcuts() }.buttonStyle(.borderless).foregroundStyle(Dota.muted)
                Button(engine.recording ? "Press keys… (Esc cancels)" : "Record…") { engine.recording.toggle() }
                    .buttonStyle(.borderedProminent).tint(Dota.red)
            }
            ScrollView {
                VStack(spacing: 8) {
                    HStack {
                        Toggle(isOn: $engine.blockScreenshots) { KeyCaps(label: "⌘⇧0–9") }
                            .frame(width: 150, alignment: .leading)
                        Text("Screenshots & screen recording").foregroundStyle(Dota.muted)
                        Spacer()
                    }
                    ForEach($engine.shortcuts) { $s in
                        HStack {
                            Toggle(isOn: $s.enabled) { KeyCaps(label: s.label) }
                                .frame(width: 150, alignment: .leading)
                            Text(s.purpose).foregroundStyle(Dota.muted)
                            Spacer()
                            Button {
                                engine.shortcuts.removeAll { $0.id == s.id }
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(Dota.muted)
                        }
                    }
                }
            }
            .disabled(!engine.blockShortcuts)
            .opacity(engine.blockShortcuts ? 1 : 0.5)
            Text("⌘Tab, ⌘Space and ⌃-arrows are system hotkeys and may not be blockable.")
                .font(.caption2).foregroundStyle(Dota.muted)
        }
        .toggleStyle(DotaCheckbox())
        .tint(Dota.red)
        .foregroundStyle(Dota.text)
        .padding(20)
        .frame(minWidth: 340, minHeight: 360)
        .background(LinearGradient(colors: [Dota.panelTop, Dota.panelBottom], startPoint: .top, endPoint: .bottom))
        .preferredColorScheme(.dark)
    }
}

/// A shortcut label ("⌃⌘Q") drawn as MacBook keycaps: one cap per modifier, one for the key.
private struct KeyCaps: View {
    let label: String

    var body: some View {
        let mods = label.prefix { "⌃⌥⇧⌘".contains($0) }
        HStack(spacing: 3) {
            ForEach(Array(mods.enumerated()), id: \.offset) { cap(String($0.element)) }
            if mods.count < label.count { cap(String(label.dropFirst(mods.count))) }
        }
    }

    private func cap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(white: 0.88))
            .frame(minWidth: 22, minHeight: 20)
            .padding(.horizontal, s.count > 1 ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.7), radius: 0, y: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(white: 0.28), lineWidth: 0.5))
    }
}
