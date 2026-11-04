import AppKit
import Combine
import SwiftUI

/// Menu bar icon next to the battery; click opens the settings popover.
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var subs: [AnyCancellable] = []
    private let engine: Engine

    init(engine: Engine) {
        self.engine = engine
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: Panel(engine: engine))

        item.button?.image = MenuIcon.idle
        item.button?.toolTip = "MacDoats"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Dimmed = Dota not running · plain = running · red pill = cursor lock engaged right now ·
        // green pill with a ticking star = in the queue. A gold dot on any of them = auto-accept armed.
        subs.append(engine.$dotaRunning.sink { [weak self] running in self?.item.button?.appearsDisabled = !running })
        subs.append(Publishers.CombineLatest4(engine.$dotaFrontmost, engine.$lockCursor, engine.$trusted, engine.$inQueue)
            .combineLatest(engine.$autoAccept)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                let ((front, lock, trusted, queued), armed) = $0
                self?.state = (queued, front && lock && trusted, armed)
            })
    }

    private var state = (queued: false, locked: false, armed: false) { didSet { updateIcon() } }
    private var frame = 0
    private var tick: Timer?, turn: Timer?

    /// Queue > locked > idle. While queued the star turns 180° clockwise once a second: an eased
    /// 0.35 s turn, then a hold. The frame timer runs only during the turn.
    private func updateIcon() {
        if state.queued, tick == nil {
            tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.spin() }
        } else if !state.queued {
            tick?.invalidate(); turn?.invalidate(); tick = nil; turn = nil; frame = 0
        }
        let a = state.armed
        item.button?.image = state.queued ? (a ? MenuIcon.queueFramesArmed : MenuIcon.queueFrames)[frame % 12]
            : state.locked ? (a ? MenuIcon.activeArmed : MenuIcon.active)
            : (a ? MenuIcon.idleArmed : MenuIcon.idle)
    }

    private func spin() {
        let start = Date(), from = frame
        turn?.invalidate()
        turn = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let p = min(Date().timeIntervalSince(start) / 0.35, 1)
            let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2   // ease in-out
            self.frame = from + Int((eased * 24).rounded())                 // 180° = 24 steps of 7.5°
            self.updateIcon()
            if p >= 1 { t.invalidate(); self.frame %= 12 }
        }
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            engine.refreshExternalSettings()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private lazy var menu: NSMenu = {
        let m = NSMenu()
        m.addItem(withTitle: "About MacDoats", action: #selector(about), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit MacDoats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }()

    /// Standard panel: name, icon, "Version 0.1.0 (build)" straight from Info.plist.
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
