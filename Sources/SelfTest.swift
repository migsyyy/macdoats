import Foundation

/// `MacDoats --selftest`. Uses explicit checks, not `assert`, so it also runs in release builds.
func runSelfTest() -> Never {
    var failures = 0
    func check(_ ok: Bool, _ what: String, line: Int = #line) {
        if !ok { failures += 1; print("FAIL line \(line): \(what)") }
    }

    // Modifier remapping. Windows row: fn→Ctrl, ⌃→off, ⌥→off, ⌘→Alt(⌥)
    func r(_ f: UInt64, _ c: Int64 = 12, fc: Bool = false, _ layout: [Mod] = Mod.windows, fnDown: Bool = false) -> (UInt64, Int64) {
        remapped(f, c, flagsChanged: fc, layout: layout, fnDown: fnDown)
    }
    let (fn, ctrl, opt, cmd) = (Mod.fn, Mod.ctrl, Mod.opt, Mod.cmd)
    check(r(fn.flag, 63, fc: true, fnDown: true) == (ctrl.flag | ctrl.devL, 59), "fn press → ⌃")
    check(r(0, 63, fc: true) == (0, 59), "fn release → ⌃ release")
    check(r(ctrl.flag | ctrl.devL, 59, fc: true) == (0, -1), "⌃ press → dropped")
    check(r(ctrl.flag | ctrl.devL) == (0, 12), "⌃Q → plain Q, no fn")
    check(r(cmd.flag | cmd.devL) == (opt.flag | opt.devL, 12), "⌘Q → ⌥Q, can't quit")
    check(r(opt.flag | opt.devL) == (0, 12), "⌥Q → plain Q")
    check(r(cmd.flag | cmd.devR, 54, fc: true) == (opt.flag | opt.devR, 61), "right side stays right")
    check(r(fn.flag, 123) == (fn.flag, 123), "arrow keeps system fn")
    check(r(cmd.flag | cmd.devL, 12, Mod.mac) == (cmd.flag | cmd.devL, 12), "identity")
    // Duplicates: fn and ⌃ both act as ⌃; releasing ⌃ while fn is held keeps ⌃ down.
    let dup: [Mod] = [.ctrl, .ctrl, .cmd, .cmd]
    check(r(fn.flag | ctrl.flag | ctrl.devL, 12, dup, fnDown: true) == (ctrl.flag | ctrl.devL, 12), "dup hold")
    check(r(fn.flag, 59, fc: true, dup, fnDown: true) == (ctrl.flag | ctrl.devL, 59), "dup release")

    // Log parser, on real lines (IDs rewritten).
    let popup = """
    11/01 00:33:31 [SOCache] CGCSOCacheSubscribedJob(owner=<Lobby:222>) [in cache]
    11/01 00:33:33 [GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus), 21 bytes
    11/01 00:33:33 [GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus), 23 bytes
    11/01 00:33:34 [GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus), 37 bytes
    11/01 00:33:35 [GCClient] Send msg 7070 (k_EMsgGCReadyUp), 44 bytes
    11/01 00:33:35 [GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus), 39 bytes
    11/01 00:33:36 LOBBY STATE RUN: lobby 222: Player AccountID 1 connecting to MatchID 3 at ServerID [A:1:2:3]
    """.components(separatedBy: "\n")
    check(parseLogLine("11/01 00:21:32 [GCClient] Send msg 7033 (k_EMsgGCStartFindingMatch), 64 bytes") == .queueStarted, "7033")
    check(parseLogLine("11/01 00:21:25 [GCClient] Send msg 7036 (k_EMsgGCStopFindingMatch), 10 bytes") == .queueStopped, "7036")
    check(parseLogLine(popup[0]) == .lobbyJoined("222"), "lobby join with [in cache]")
    check(parseLogLine("11/01 00:22:19 [SOCache] CGCSOCacheUnsubscribedJob(owner=<Lobby:111>)") == .lobbyLeft("111"), "lobby left")
    check(parseLogLine(popup[1]) == .readyUpStatus, "7170")
    check(parseLogLine(popup[4]) == .answered, "7070")
    check(parseLogLine(popup[6]) == .matchRunning("222"), "lobby run")
    check(parseLogLine("\u{FEFF}11/01 00:21:32 [GCClient] Send msg 7033 (k_EMsgGCStartFindingMatch), 64 bytes") == .queueStarted, "BOM")
    check(parseLogLine("11/01 00:13:48 [SOCache] CGCSOCacheSubscribedJob(owner=<Party:333>) [in cache]") == nil, "party isn't a lobby")
    check(parseLogLine("11/01 00:13:48 [GCClient] Recv msg 7681 (k_EMsgGCToClientRequestMMInfo), 8 bytes") == nil, "7681 ignored")
    check(parseLogLine("11/01 00:20:00 [Chat] x: [GCClient] Send msg 7070 (k_EMsgGCReadyUp)") == nil, "chat can't match")
    check(parseLogLine("[GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus)") == nil, "no timestamp, no match")

    var lb = LineBuffer()
    check(lb.append(Data("ab\nc".utf8)) == ["ab"] && lb.append(Data([0xFF, 0x0A])) == ["c\u{FFFD}"], "partial + invalid UTF-8")

    // Accept decisions: replay a trace, count presses when every press lands.
    func replay(_ lines: [String], armed: Bool = true, gatesOK: Bool = true, answerAfterSchedule: Bool = false)
        -> (posts: Int, warns: Int, started: Bool) {
        var st = AcceptState(), posts = 0, warns = 0, started = false
        for l in lines {
            guard let e = parseLogLine(l) else { continue }
            switch st.apply(e, armed: armed, gatesOK: gatesOK) {
            case .schedule(let id, let gen):
                if answerAfterSchedule { _ = st.apply(.answered, armed: armed, gatesOK: gatesOK) }
                st.pending = nil
                if st.canPost(id, generation: gen) { st.pressed.insert(id); posts += 1 }
            case .warn: warns += 1
            case .matchStarted: started = true
            case .none: break
            }
        }
        return (posts, warns, started)
    }
    let unanswered = Array(popup[0...3]) + ["11/01 00:33:50 [SOCache] CGCSOCacheUnsubscribedJob(owner=<Lobby:222>)"]
    check(replay(popup).posts == 1, "one press per popup")
    check(replay(popup).started, "match start seen")
    check(replay(unanswered).posts == 1, "fires when you don't respond")
    check(replay(popup, armed: false).posts == 0, "not armed → nothing")
    check(replay(popup, gatesOK: false) == (0, 1, true), "Dota not in front → one warning, no press")
    check(replay(popup, answerAfterSchedule: true).posts == 0, "answered during the 0.4 s wait → no press")
    check(replay([popup[4]] + popup).posts == 1, "stray earlier answer doesn't block a new lobby")
    let spectate = ["10/31 22:59:29 [SOCache] CGCSOCacheSubscribedJob(owner=<Lobby:444>) [in cache]",
                    "10/31 22:59:29 LOBBY STATE RUN: lobby 444: Player AccountID 1 connecting to MatchID 5 at ServerID x"]
    check(replay(spectate).posts == 0, "spectate / bot lobby has no ready-up → nothing")
    var st = AcceptState()
    _ = st.apply(.lobbyJoined("1"), armed: true, gatesOK: true)
    _ = st.apply(.lobbyLeft("2"), armed: true, gatesOK: true)
    check(st.popup == "1", "leaving another lobby keeps the popup")
    _ = st.apply(.queueStarted, armed: true, gatesOK: true)
    check(st.inQueue, "queue start")
    _ = st.apply(.lobbyJoined("3"), armed: true, gatesOK: true)
    check(!st.inQueue, "match found ends the queue")
    (st.pressed, st.answered, st.pending, st.inQueue) = (["3"], ["3"], "3", true)
    let g = st.generation
    st.reset()
    check(st.popup == nil && st.pressed.isEmpty && st.answered.isEmpty && st.pending == nil && !st.inQueue
          && st.generation > g, "reset clears and cancels pending presses")
    // The 0.4 s settle: a second status can't schedule a second press, and a lobby change cancels the first.
    var w = AcceptState()
    _ = w.apply(.lobbyJoined("5"), armed: true, gatesOK: true)
    let first = w.apply(.readyUpStatus, armed: true, gatesOK: true)
    check(w.apply(.readyUpStatus, armed: true, gatesOK: true) == .none, "no second schedule while pending")
    if case .schedule(let id, let gen) = first {
        _ = w.apply(.lobbyLeft("5"), armed: true, gatesOK: true)
        check(!w.canPost(id, generation: gen), "lobby closed during the wait → no press")
    } else { check(false, "first status schedules") }

    // Settings and log checks.
    let vcfg = "\t\t\"dota_mouse_window_lock\"\t\t\"true\"\n\t\t\"dota_activate_window_on_match_found\"\t\t\"false\""
    check(vcfgFlag(vcfg, "dota_mouse_window_lock") == true, "vcfg true")
    check(vcfgFlag(vcfg, "dota_activate_window_on_match_found") == false, "vcfg false")
    check(vcfgFlag(vcfg, "missing") == nil, "vcfg missing")
    let t = Date()
    check(logIsLive(created: t, dotaStarted: t.addingTimeInterval(-2)), "log made after launch → live")
    check(!logIsLive(created: t.addingTimeInterval(-3600), dotaStarted: t), "old log → not live (no -condebug)")
    check(!logIsLive(created: nil, dotaStarted: t), "no log → not live")

    print(failures == 0 ? "selftest ok" : "selftest FAILED: \(failures)")
    exit(failures == 0 ? 0 : 1)
}
