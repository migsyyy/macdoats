import AppKit

if CommandLine.arguments.contains("--selftest") { runSelfTest() }

if let i = CommandLine.arguments.firstIndex(of: "--screenshots"), i + 1 < CommandLine.arguments.count {
    renderScreenshots(to: CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let engine = Engine()
let statusItem = StatusItemController(engine: engine)
app.run()
