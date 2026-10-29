import AppKit

if CommandLine.arguments.contains("--selftest") {
    func r(_ f: UInt64, _ c: Int64 = 12, fc: Bool = false, _ layout: [Mod] = Mod.windows, fnDown: Bool = false) -> (UInt64, Int64) {
        remapped(f, c, flagsChanged: fc, layout: layout, fnDown: fnDown)
    }
    let (fn, ctrl, opt, cmd) = (Mod.fn, Mod.ctrl, Mod.opt, Mod.cmd)
    // Windows row: fn→Ctrl, ⌃→off, ⌥→off, ⌘→Alt(⌥)
    assert(r(fn.flag, 63, fc: true, fnDown: true) == (ctrl.flag | ctrl.devL, 59))     // fn press → ⌃
    assert(r(0, 63, fc: true) == (0, 59))                                              // fn release → ⌃ release
    assert(r(ctrl.flag | ctrl.devL, 59, fc: true) == (0, -1))                          // ⌃ press → dropped
    assert(r(ctrl.flag | ctrl.devL) == (0, 12))                                        // ⌃Q → plain Q, no fn
    assert(r(cmd.flag | cmd.devL) == (opt.flag | opt.devL, 12))                        // ⌘Q → ⌥Q, can't quit
    assert(r(opt.flag | opt.devL) == (0, 12))                                          // ⌥Q → plain Q
    assert(r(cmd.flag | cmd.devR, 54, fc: true) == (opt.flag | opt.devR, 61))          // right side stays right
    assert(r(fn.flag, 123) == (fn.flag, 123))                                          // arrow keeps system fn
    assert(r(cmd.flag | cmd.devL, 12, Mod.mac) == (cmd.flag | cmd.devL, 12))           // identity
    // Duplicates: fn and ⌃ both act as ⌃; releasing ⌃ while fn is held keeps ⌃ down.
    let dup: [Mod] = [.ctrl, .ctrl, .cmd, .cmd]
    assert(r(fn.flag | ctrl.flag | ctrl.devL, 12, dup, fnDown: true) == (ctrl.flag | ctrl.devL, 12))
    assert(r(fn.flag, 59, fc: true, dup, fnDown: true) == (ctrl.flag | ctrl.devL, 59))
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let engine = Engine()
let statusItem = StatusItemController(engine: engine)
app.run()
