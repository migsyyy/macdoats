import Foundation

/// What MacDoats reads from Dota's `console.log` (written when Steam launches Dota with `-condebug`).
/// Dota logs every Game Coordinator message by name; see docs/plans/auto-accept.md for the traces.
enum LogEvent: Equatable {
    case queueStarted, queueStopped
    case lobbyJoined(String), lobbyLeft(String)
    case readyUpStatus      // the accept popup's counter: the popup is live
    case answered           // this client sent Accept or Decline
    case matchRunning(String)
}

/// Parses one log line. Matches only right after the `MM/DD HH:MM:SS ` prefix, so chat text or a
/// Steam name containing a message name can't produce an event.
func parseLogLine(_ raw: String) -> LogEvent? {
    var line = Substring(raw)
    if line.first == "\u{FEFF}" { line = line.dropFirst() }
    let u = Array(line.utf8.prefix(15))
    guard u.count == 15, u[2] == UInt8(ascii: "/"), u[5] == UInt8(ascii: " "), u[8] == UInt8(ascii: ":"),
          u[11] == UInt8(ascii: ":"), u[14] == UInt8(ascii: " "),
          [0, 1, 3, 4, 6, 7, 9, 10, 12, 13].allSatisfy({ (48...57).contains(u[$0]) })
    else { return nil }
    let s = line.dropFirst(15)
    func id(after p: String) -> String? {
        guard s.hasPrefix(p) else { return nil }
        let rest = s.dropFirst(p.count)
        let digits = rest.prefix(while: \.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }
    if s.hasPrefix("[GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus)") { return .readyUpStatus }
    if s.hasPrefix("[GCClient] Send msg 7070 (k_EMsgGCReadyUp)") { return .answered }
    if s.hasPrefix("[GCClient] Send msg 7033 (k_EMsgGCStartFindingMatch)") { return .queueStarted }
    if s.hasPrefix("[GCClient] Send msg 7036 (k_EMsgGCStopFindingMatch)") { return .queueStopped }
    if let i = id(after: "[SOCache] CGCSOCacheSubscribedJob(owner=<Lobby:") { return .lobbyJoined(i) }
    if let i = id(after: "[SOCache] CGCSOCacheUnsubscribedJob(owner=<Lobby:") { return .lobbyLeft(i) }
    if let i = id(after: "LOBBY STATE RUN: lobby ") { return .matchRunning(i) }
    return nil
}

/// Splits raw bytes into lines, keeping a partial last line for the next read. Decodes lossily,
/// so a split or invalid UTF-8 byte never drops a line.
struct LineBuffer {
    private var pending = Data()
    mutating func append(_ d: Data) -> [String] {
        pending.append(d)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            var l = pending[pending.startIndex..<nl]
            if l.last == 0x0D { l = l.dropLast() }
            lines.append(String(decoding: l, as: UTF8.self))
            pending = Data(pending[(nl + 1)...])
        }
        return lines
    }
    mutating func reset() { pending = Data() }
}

/// Auto-accept decisions, kept free of side effects so `--selftest` can replay real traces.
struct AcceptState {
    var inQueue = false
    var popup: String?                // lobby of the accept popup on screen
    var answered: Set<String> = []    // lobbies this client answered (you or MacDoats)
    var pressed: Set<String> = []     // lobbies MacDoats pressed Return for (max one each)
    var warned: Set<String> = []      // lobbies we already played the "not in front" sound for
    var pending: String?              // a press waiting out the 0.4 s settle
    var generation = 0                // bumped on any change that must cancel a pending press

    enum Action: Equatable { case none, schedule(String, Int), warn, matchStarted }

    mutating func apply(_ e: LogEvent, armed: Bool, gatesOK: Bool) -> Action {
        switch e {
        case .queueStarted: inQueue = true
        case .queueStopped: inQueue = false
        case .lobbyJoined(let id): inQueue = false; popup = id; generation += 1
        case .lobbyLeft(let id): if popup == id { popup = nil }; generation += 1
        case .answered: if let p = popup { answered.insert(p) }; generation += 1
        case .matchRunning: return .matchStarted
        case .readyUpStatus:
            // Every status while the popup lasts is a fresh chance, so a slow Space switch still gets one press.
            guard armed, let id = popup, !answered.contains(id), !pressed.contains(id), pending == nil else { return .none }
            guard gatesOK else { return warned.insert(id).inserted ? .warn : .none }
            pending = id
            return .schedule(id, generation)
        }
        return .none
    }

    /// Checked again after the settle delay: same popup, still unanswered, nothing changed since.
    func canPost(_ id: String, generation g: Int) -> Bool {
        popup == id && !answered.contains(id) && !pressed.contains(id) && generation == g
    }

    mutating func reset() { self = AcceptState(generation: generation + 1) }
}

/// Follows `console.log` from its end with a kqueue source on the main queue. Never replays old
/// lines; Dota rewrites the file each launch, which shows up as delete/rename, then `poll()` reopens.
final class DotaLog {
    static let path: String? = {
        let steam = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
        let vdf = (try? String(contentsOf: steam.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8)) ?? ""
        // Each library block starts with its "path"; take the one whose "apps" lists 570 (Dota 2).
        let lib = vdf.components(separatedBy: "\"path\"").dropFirst().first { $0.contains("\"570\"") }
            .flatMap { $0.components(separatedBy: "\"").dropFirst().first } ?? steam.path  // [tabs, path, …]
        return lib + "/steamapps/common/dota 2 beta/game/dota/console.log"
    }()

    var onEvent: (LogEvent) -> Void = { _ in }
    var onReset: () -> Void = {}
    private var source: DispatchSourceFileSystemObject?
    private var offset: off_t = 0
    private var buffer = LineBuffer()

    /// Called from Engine's 0.5 s tick: reopens the log once it exists again.
    func poll() {
        guard source == nil, let path = Self.path else { return }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return }
        offset = lseek(fd, 0, SEEK_END)
        buffer.reset()
        onReset()
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.extend, .write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self, unowned src] in
            guard let self else { return }
            if !src.data.isDisjoint(with: [.delete, .rename]) { src.cancel(); self.source = nil; return }
            self.read(fd)
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func read(_ fd: Int32) {
        var st = stat()
        guard fstat(fd, &st) == 0 else { return }
        if st.st_size < offset { offset = 0; buffer.reset(); onReset() } // rewritten in place
        guard st.st_size > offset else { return }
        var data = Data(count: Int(st.st_size - offset))
        let n = data.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, offset) }
        guard n > 0 else { return }
        offset += off_t(n)
        for line in buffer.append(data.prefix(n)) { if let e = parseLogLine(line) { onEvent(e) } }
    }
}

/// A Dota setting from `machine_convars.vcfg` (`"key"		"true"`); nil if the key isn't there.
func vcfgFlag(_ text: String, _ key: String) -> Bool? {
    guard let r = text.range(of: "\"\(key)\"\\s+\"(true|false|1|0)\"", options: .regularExpression) else { return nil }
    let v = text[r].split(separator: "\"").last ?? ""
    return v == "true" || v == "1"
}

/// The log belongs to the running Dota only if it was created at or after Dota started; an older
/// file means Dota runs without `-condebug` (the log is from an earlier session).
func logIsLive(created: Date?, dotaStarted: Date?) -> Bool {
    guard let created, let dotaStarted else { return false }
    return created >= dotaStarted.addingTimeInterval(-2)
}

func processStartDate(_ pid: pid_t) -> Date? {
    var kp = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
    let t = kp.kp_proc.p_starttime
    return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1e6)
}
