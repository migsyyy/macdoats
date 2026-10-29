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
        // Dimmed = Dota not running · plain = running · red pill = cursor lock engaged right now.
        subs.append(engine.$dotaRunning.sink { [weak self] running in self?.item.button?.appearsDisabled = !running })
        subs.append(Publishers.CombineLatest3(engine.$dotaFrontmost, engine.$lockCursor, engine.$trusted)
            .map { $0 && $1 && $2 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in self?.item.button?.image = locked ? MenuIcon.active : MenuIcon.idle })
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            engine.refreshExternalSettings()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
