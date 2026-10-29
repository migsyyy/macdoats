import AppKit
import ApplicationServices

/// A key combo to swallow while Dota is frontmost.
struct Shortcut: Codable, Hashable, Identifiable {
    var keyCode: Int64
    var mods: UInt64 // subset of modMask
    var label: String
    var enabled = true
    var id: String { "\(keyCode)-\(mods)" }
    /// What macOS does with this combo, for the Customize window.
    var purpose: String { Self.purposes[label] ?? "Custom" }
    static let purposes = [
        "⌘Q": "Quit app (closes Dota)", "⌘W": "Close window", "⌘H": "Hide app", "⌘M": "Minimize window",
        "⌘Tab": "Switch apps", "⌘Space": "Spotlight search", "⌃↑": "Mission Control",
        "⌃↓": "App windows", "⌃←": "Previous Space", "⌃→": "Next Space", "⌥⌘Esc": "Force Quit dialog",
        "⌘,": "App settings", "⌘F": "Find / fullscreen", "⌃⌘F": "Toggle fullscreen",
    ]
}

let modMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

/// The four bottom-left modifier keys, in physical Mac order, plus `none` (key does nothing).
/// layout[physical.rawValue] = the modifier that key produces while Dota is focused. Outputs may
/// repeat (two keys as ⌃); remapped() is stateless, so releasing one keeps the other held.
enum Mod: Int, CaseIterable, Identifiable {
    case fn, ctrl, opt, cmd, none
    var id: Int { rawValue }
    static let keys: [Mod] = [.fn, .ctrl, .opt, .cmd] // physical slots
    static let mac: [Mod] = [.fn, .ctrl, .opt, .cmd]
    /// Windows-style gaming row: corner key is Ctrl, the key next to space is Alt, the rest off.
    /// No key produces fn (fires macOS hotkeys) or ⌘ (can't quit/hide the game).
    static let windows: [Mod] = [.ctrl, .none, .none, .opt]

    var flag: UInt64 { [0x800000, 0x40000, 0x80000, 0x100000, 0][rawValue] }
    // Device-dependent bits (NX_DEVICE*KEYMASK); games read these for left/right. fn has none.
    var devL: UInt64 { [0, 0x01, 0x20, 0x08, 0][rawValue] }
    var devR: UInt64 { [0, 0x2000, 0x40, 0x10, 0][rawValue] }
    var codeL: Int64 { [63, 59, 58, 55, -1][rawValue] } // -1: drop the key's own event
    var codeR: Int64 { [63, 62, 61, 54, -1][rawValue] }
    var symbol: String { ["fn", "⌃", "⌥", "⌘", "—"][rawValue] }
    var name: String { ["fn", "control", "option", "command", "none"][rawValue] }
    var windowsName: String { ["Fn", "Ctrl", "Alt", "Win", "Off"][rawValue] }
}

enum Key {
    static let q: Int64 = 12, w: Int64 = 13, h: Int64 = 4, m: Int64 = 46, l: Int64 = 37
    static let tab: Int64 = 48, space: Int64 = 49, esc: Int64 = 53
    static let left: Int64 = 123, right: Int64 = 124, up: Int64 = 126
    static let fn: Int64 = 63
    static let digits: Set<Int64> = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] // 1…9, 0
}

private let defaultShortcuts: [Shortcut] = [
    Shortcut(keyCode: Key.q, mods: CGEventFlags.maskCommand.rawValue, label: "⌘Q"),
    Shortcut(keyCode: Key.w, mods: CGEventFlags.maskCommand.rawValue, label: "⌘W"),
    Shortcut(keyCode: Key.h, mods: CGEventFlags.maskCommand.rawValue, label: "⌘H"),
    Shortcut(keyCode: Key.m, mods: CGEventFlags.maskCommand.rawValue, label: "⌘M"),
    Shortcut(keyCode: Key.tab, mods: CGEventFlags.maskCommand.rawValue, label: "⌘Tab"),
    Shortcut(keyCode: Key.space, mods: CGEventFlags.maskCommand.rawValue, label: "⌘Space"),
    Shortcut(keyCode: Key.up, mods: CGEventFlags.maskControl.rawValue, label: "⌃↑"),
    Shortcut(keyCode: Key.left, mods: CGEventFlags.maskControl.rawValue, label: "⌃←"),
    Shortcut(keyCode: Key.right, mods: CGEventFlags.maskControl.rawValue, label: "⌃→"),
]

/// Owns the event tap. Everything runs on the main run loop, so no locking.
final class Engine: ObservableObject {
    /// Override for testing without Dota: `defaults write dev.macdoats.app targetBundleIDs -array com.apple.TextEdit`
    let targets = UserDefaults.standard.stringArray(forKey: "targetBundleIDs") ?? ["com.valvesoftware.dota2"]

    @Published var trusted = AXIsProcessTrusted()
    @Published var dotaRunning = false
    @Published var dotaFrontmost = false
    @Published var recording = false
    /// Dota's main window in CG global coordinates (top-left origin), nil when not frontmost.
    private var bounds: CGRect?
    @Published var lockCursor: Bool { didSet { defaults.set(lockCursor, forKey: "lockCursor") } }
    @Published var blockShortcuts: Bool {
        didSet { defaults.set(blockShortcuts, forKey: "blockShortcuts"); applySystemHotkeys() }
    }
    @Published var allowAltTab: Bool { didSet { defaults.set(allowAltTab, forKey: "allowAltTab") } }
    @Published var blockScreenshots: Bool {
        didSet { defaults.set(blockScreenshots, forKey: "blockScreenshots"); applySystemHotkeys() }
    }
    @Published var modLayout: [Mod] { didSet { defaults.set(modLayout.map(\.rawValue), forKey: "modLayout") } }
    @Published var shortcuts: [Shortcut] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
    }

    private let defaults = UserDefaults.standard
    private var tap: CFMachPort?
    private var dotaPID: pid_t?
    private var fnDown = false
    private var altTabbing = false // holding a synthetic ⌘ for the app switcher
    private let syntheticTag: Int64 = 0x4D63446F // marks our own posted events

    init() {
        defaults.register(defaults: ["lockCursor": true, "blockShortcuts": true, "allowAltTab": true,
                                     "blockScreenshots": true])
        blockScreenshots = defaults.bool(forKey: "blockScreenshots")
        allowAltTab = defaults.bool(forKey: "allowAltTab")
        lockCursor = defaults.bool(forKey: "lockCursor")
        blockShortcuts = defaults.bool(forKey: "blockShortcuts")
        let saved = (defaults.array(forKey: "modLayout") as? [Int] ?? []).compactMap(Mod.init(rawValue:))
        modLayout = saved.count == 4 ? saved : Mod.mac
        shortcuts = defaults.data(forKey: "shortcuts")
            .flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) } ?? defaultShortcuts

        // Warping the cursor otherwise freezes local mouse input for ~0.25s.
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.frontmostChanged(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        frontmostChanged(NSWorkspace.shared.frontmostApplication)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshRunning()
            }
        }
        refreshRunning()

        // Re-enable first: undoes a crash that happened mid-game with the hotkeys off.
        setSystemHotkeys(enabled: true)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.setSystemHotkeys(enabled: true) }

        if trusted { startTap() } else { requestAccess() }
        // ponytail: 0.5s poll for window moves/resizes and the permission grant; AX observers if it lags.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    func resetShortcuts() { shortcuts = defaultShortcuts }

    /// Drag-and-drop: the key at slot `a` and the key at slot `b` trade outputs.
    func swapSlots(_ a: Int, _ b: Int) { modLayout.swapAt(a, b) }

    func setOutput(_ slot: Int, _ out: Mod) { modLayout[slot] = out }

    private func tick() {
        if !trusted, AXIsProcessTrusted() { trusted = true; startTap() }
        if dotaFrontmost { refreshBounds() }
    }

    private func refreshRunning() {
        dotaRunning = NSWorkspace.shared.runningApplications.contains { targets.contains($0.bundleIdentifier ?? "") }
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        dotaPID = app.flatMap { targets.contains($0.bundleIdentifier ?? "") ? $0.processIdentifier : nil }
        dotaFrontmost = dotaPID != nil
        refreshBounds()
        applySystemHotkeys()
    }

    // MARK: - System screenshot hotkeys

    /// Symbolic hotkey IDs: ⌘⇧3, ⌃⌘⇧3, ⌘⇧4, ⌃⌘⇧4, ⌘⇧6 (Touch Bar, both), ⌘⇧5.
    private static let screenshotHotkeys: [Int32] = [28, 29, 30, 31, 181, 182, 184]
    /// Private SkyLight call (what AltTab uses for ⌘Tab). WindowServer handles these before our
    /// tap sees them, so swallowing keys alone may not be enough. nil if Apple removes it.
    private let cgsSetHotKeyEnabled: (@convention(c) (Int32, Bool) -> Int32)? =
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") // RTLD_DEFAULT
            .map { unsafeBitCast($0, to: (@convention(c) (Int32, Bool) -> Int32).self) }

    private func applySystemHotkeys() {
        setSystemHotkeys(enabled: !(dotaFrontmost && blockShortcuts && blockScreenshots))
    }

    private func setSystemHotkeys(enabled: Bool) {
        for id in Self.screenshotHotkeys { _ = cgsSetHotKeyEnabled?(id, enabled) }
    }

    // MARK: - 🌐 fn key system action

    /// "Press 🌐 key to" in Keyboard settings is Do Nothing. macOS only reads it at login, so MacDoats
    /// can't flip it per game; the panel shows it and links there. Refreshed each time the panel opens.
    @Published private(set) var fnKeyOff = false
    /// Dota's own "Lock Mouse to Window" (in_lock_mouse_to_window). When on, Dota confines the
    /// cursor itself and MacDoats' toggle can't release it.
    @Published private(set) var dotaLocksMouse = false

    /// Re-reads settings owned by macOS and Dota. Called each time the panel opens.
    func refreshExternalSettings() {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        fnKeyOff = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int == 0

        let userdata = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/userdata")
        let accounts = (try? FileManager.default.contentsOfDirectory(atPath: userdata.path)) ?? []
        dotaLocksMouse = accounts.contains { id in
            let cfg = userdata.appendingPathComponent("\(id)/570/remote/cfg/config.cfg")
            return (try? String(contentsOf: cfg, encoding: .utf8))?.contains("in_lock_mouse_to_window \"1\"") == true
        }
    }

    /// Largest on-screen normal-layer window of the Dota process, in global top-left coordinates
    /// (same space as CGEvent.location). Owner PID and bounds don't need Screen Recording.
    private func refreshBounds() {
        guard let pid = dotaPID,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { if bounds != nil { bounds = nil }; return }
        let new = list
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .max { $0.width * $0.height < $1.width * $1.height }
        if new != bounds { bounds = new } // polled every 0.5s; only publish real changes
    }

    // MARK: - Event tap

    private func startTap() {
        guard tap == nil else { return }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                Unmanaged<Engine>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        // macOS silently disables slow taps; a dead tap means ⌘Q quits the game.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticTag { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, code == Key.fn { fnDown = event.flags.contains(.maskSecondaryFn) }

        // Alt-Tab in progress: Dota may already have lost focus, so this runs before the guard.
        if altTabbing {
            if code == Key.tab, type == .keyDown || type == .keyUp {
                postKey(Key.tab, down: type == .keyDown, flags: event.flags.intersection(.maskShift).union(.maskCommand))
                return nil
            }
            if type == .flagsChanged, outputFlags(type, code, event) & Mod.opt.flag == 0 {
                altTabbing = false // Alt released → release ⌘, the switcher commits
                postKey(Mod.cmd.codeL, down: false, flags: [])
            }
        }

        if type == .keyDown {
            if recording { record(code, event); return nil }
            // Panic switch, works everywhere: ⌃⌥⌘L toggles cursor lock.
            if code == Key.l, event.flags.intersection(modMask) == [.maskControl, .maskAlternate, .maskCommand] {
                lockCursor.toggle()
                return nil
            }
        }
        guard dotaFrontmost else { return pass }

        if !remap(type, code, event) { return nil }
        switch type {
        case .keyDown where allowAltTab && code == Key.tab:
            if event.flags.contains(.maskAlternate) {
                // Windows-style Alt+Tab: hold a real ⌘ while Alt is held and feed it the Tabs, so the
                // native switcher opens, cycles and commits on release.
                altTabbing = true
                postKey(Mod.cmd.codeL, down: true, flags: .maskCommand)
                postKey(Key.tab, down: true, flags: event.flags.intersection(.maskShift).union(.maskCommand))
                return nil
            }
            if event.flags.contains(.maskCommand) { return pass } // ⌘Tab always allowed
        case .keyDown:
            // Checked after remap: if a key now produces ⌘, ⌘Q from it must still be blocked.
            let mods = event.flags.intersection(modMask).rawValue
            if blockShortcuts, shortcuts.contains(where: { $0.enabled && $0.keyCode == code && $0.mods == mods }) { return nil }
            if blockShortcuts, blockScreenshots, event.flags.contains([.maskCommand, .maskShift]), Key.digits.contains(code) { return nil }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if lockCursor { clamp(event) }
        default: break
        }
        return pass
    }

    /// Returns false when the event should be dropped (an unbound modifier's own press/release).
    private func remap(_ type: CGEventType, _ code: Int64, _ event: CGEvent) -> Bool {
        guard modLayout != Mod.mac else { return true }
        let (f, newCode) = remapped(event.flags.rawValue, code, flagsChanged: type == .flagsChanged,
                                    layout: modLayout, fnDown: fnDown)
        if newCode < 0 { return false }
        event.flags = CGEventFlags(rawValue: f)
        if newCode != code { event.setIntegerValueField(.keyboardEventKeycode, value: newCode) }
        return true
    }

    private func outputFlags(_ type: CGEventType, _ code: Int64, _ event: CGEvent) -> UInt64 {
        guard modLayout != Mod.mac else { return event.flags.rawValue }
        return remapped(event.flags.rawValue, code, flagsChanged: type == .flagsChanged,
                        layout: modLayout, fnDown: fnDown).0
    }

    private func postKey(_ code: Int64, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        e.post(tap: .cghidEventTap)
    }

    private func clamp(_ event: CGEvent) {
        guard let b = bounds else { return }
        let p = event.location
        // Stay 1px inside so edges (menu bar, Dock, other displays) never trigger.
        let c = CGPoint(x: min(max(p.x, b.minX + 1), b.maxX - 2), y: min(max(p.y, b.minY + 1), b.maxY - 2))
        guard c != p else { return }
        event.location = c
        CGWarpMouseCursorPosition(c)
    }

    private func record(_ code: Int64, _ event: CGEvent) {
        recording = false
        guard code != Key.esc else { return }
        let mods = event.flags.intersection(modMask)
        let s = Shortcut(keyCode: code, mods: mods.rawValue, label: Self.label(code, mods, event))
        if !shortcuts.contains(where: { $0.id == s.id }) { shortcuts.append(s) }
    }

    static func label(_ code: Int64, _ mods: CGEventFlags, _ event: CGEvent) -> String {
        var s = ""
        if mods.contains(.maskControl) { s += "⌃" }
        if mods.contains(.maskAlternate) { s += "⌥" }
        if mods.contains(.maskShift) { s += "⇧" }
        if mods.contains(.maskCommand) { s += "⌘" }
        let named: [Int64: String] = [
            Key.tab: "Tab", Key.space: "Space", 36: "Return", 51: "Delete", Key.esc: "Esc",
            Key.left: "←", Key.right: "→", Key.up: "↑", 125: "↓",
        ]
        return s + (named[code] ?? NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased() ?? "#\(code)")
    }
}

/// Pure modifier rewrite so it can be self-tested. Returns new flags and (for flagsChanged) keycode.
func remapped(_ flags: UInt64, _ code: Int64, flagsChanged: Bool, layout: [Mod], fnDown: Bool) -> (UInt64, Int64) {
    // macOS also sets the fn flag on arrows/F-keys/Home/End with no fn key held, so the
    // physical fn state comes from fnDown and that "system fn" is passed through untouched.
    let systemFn = flags & Mod.fn.flag != 0 && !fnDown
    var f = flags
    for m in Mod.keys { f &= ~(m.flag | m.devL | m.devR) }
    for m in Mod.keys where m == .fn ? fnDown : flags & m.flag != 0 {
        let out = layout[m.rawValue]
        f |= out.flag
        if flags & m.devR != 0 { f |= out.devR }
        if flags & m.devL != 0 || m == .fn { f |= out.devL }
    }
    if systemFn { f |= Mod.fn.flag }
    guard flagsChanged, let m = Mod.keys.first(where: { $0.codeL == code || $0.codeR == code }) else {
        return (f, code)
    }
    let out = layout[m.rawValue]
    return (f, m != .fn && code == m.codeR ? out.codeR : out.codeL)
}
