// ddir macOS backend — persistent state, same TSV layout as the Windows build:
//   ~/.ddir/mode.txt, leases.tsv, apps.tsv, audit.tsv, config.ini, ddir.log, queue/*.op
// DDIR_HOME overrides the directory (used by tests to isolate from the user's state).

import Foundation

func nowUnix() -> UInt64 {
    UInt64(Date().timeIntervalSince1970)
}

func nowMillis() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
}

func nowString() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.string(from: Date())
}

final class Store {
    static let shared = Store()

    func home() -> URL {
        if let v = ProcessInfo.processInfo.environment["DDIR_HOME"], !v.isEmpty {
            return URL(fileURLWithPath: v, isDirectory: true)
        }
        let base = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(".ddir", isDirectory: true)
    }

    func ensureHome() {
        try? FileManager.default.createDirectory(at: home(), withIntermediateDirectories: true)
    }

    func path(_ name: String) -> String {
        home().appendingPathComponent(name).path
    }

    // MARK: - mode

    func mode() -> String {
        guard let s = try? String(contentsOfFile: path("mode.txt"), encoding: .utf8) else { return "off" }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "off" : t
    }

    @discardableResult
    func setMode(_ m: String) -> String? {
        guard ["off", "semi", "auto"].contains(m) else { return "mode must be off|semi|auto" }
        ensureHome()
        do {
            try m.write(toFile: path("mode.txt"), atomically: true, encoding: .utf8)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - atomic write + cross-process lock

    func atomicWrite(_ target: String, _ data: String) {
        let tmp = target + ".tmp"
        try? data.write(toFile: tmp, atomically: false, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: target)
        try? FileManager.default.moveItem(atPath: tmp, toPath: target)
    }

    final class Guard {
        let p: String
        init(_ p: String) { self.p = p }
        deinit { try? FileManager.default.removeItem(atPath: p) }
    }

    /// Same contract as store::lock(): create_new + retry, steal a lock older than 3s.
    func lock() -> Guard {
        ensureHome()
        let p = path("state.lock")
        var waited = 0
        while true {
            let fd = open(p, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                close(fd)
                return Guard(p)
            }
            usleep(15_000)
            waited += 15
            if waited > 3000 {
                try? FileManager.default.removeItem(atPath: p)
            }
        }
    }

    // MARK: - leases

    struct Lease {
        var window: String
        var agent: String
        var action: String
        var from: [Int]
        var to: [Int]
        var expires: UInt64
        var lease: String
        var priority: String
        var since: UInt64
    }

    func leases() -> [Lease] {
        guard let txt = try? String(contentsOfFile: path("leases.tsv"), encoding: .utf8) else { return [] }
        var out: [Lease] = []
        for line in txt.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: "\t")
            if f.count < 8 { continue }
            out.append(Lease(
                window: f[0],
                agent: f[1],
                action: f[2],
                from: parseRect(f[3]) ?? [0, 0, 0, 0],
                to: parseRect(f[4]) ?? [0, 0, 0, 0],
                expires: UInt64(f[5]) ?? 0,
                lease: f[6],
                priority: f.count > 7 ? f[7] : "normal",
                since: f.count > 8 ? (UInt64(f[8]) ?? 0) : 0
            ))
        }
        return out
    }

    func saveLeases(_ items: [Lease]) {
        ensureHome()
        var s = ""
        for l in items {
            s += "\(l.window)\t\(l.agent)\t\(l.action)\t\(formatRect(l.from))\t\(formatRect(l.to))\t\(l.expires)\t\(l.lease)\t\(l.priority)\t\(l.since)\n"
        }
        atomicWrite(path("leases.tsv"), s)
    }

    // MARK: - app owners

    struct AppOwner {
        var app: String
        var owner: String
        var since: UInt64
        var ttl: UInt64
    }

    func apps() -> [AppOwner] {
        guard let txt = try? String(contentsOfFile: path("apps.tsv"), encoding: .utf8) else { return [] }
        var out: [AppOwner] = []
        for line in txt.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.components(separatedBy: "\t")
            if f.count < 4 { continue }
            out.append(AppOwner(app: f[0], owner: f[1], since: UInt64(f[2]) ?? 0, ttl: UInt64(f[3]) ?? 1800))
        }
        return out
    }

    func saveApps(_ v: [AppOwner]) {
        ensureHome()
        var s = ""
        for a in v { s += "\(a.app)\t\(a.owner)\t\(a.since)\t\(a.ttl)\n" }
        atomicWrite(path("apps.tsv"), s)
    }

    // MARK: - audit / log

    func audit(_ op: String, _ detail: String) {
        ensureHome()
        let clean = detail.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        append(path("audit.tsv"), "\(nowUnix())\t\(op)\t\(clean)\n")
    }

    func log(_ msg: String) {
        ensureHome()
        let p = path("ddir.log")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
           let size = attrs[.size] as? Int, size > 2 * 1024 * 1024 {
            try? FileManager.default.removeItem(atPath: path("ddir.log.1"))
            try? FileManager.default.moveItem(atPath: p, toPath: path("ddir.log.1"))
        }
        append(p, "\(nowString())  \(msg.replacingOccurrences(of: "\n", with: " "))\n")
    }

    func append(_ p: String, _ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: p) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: p))
        }
    }

    func logTail(_ n: Int) -> [String] {
        guard let txt = try? String(contentsOfFile: path("ddir.log"), encoding: .utf8) else { return [] }
        let lines = txt.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(n))
    }

    // MARK: - config

    func configPath() -> String { path("config.ini") }

    func configAll() -> [(String, String)] {
        guard let txt = try? String(contentsOfFile: configPath(), encoding: .utf8) else { return [] }
        var out: [(String, String)] = []
        for raw in txt.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            out.append((k, v))
        }
        return out
    }

    func configGet(_ key: String) -> String? {
        configAll().first { $0.0 == key }?.1
    }

    @discardableResult
    func configSet(_ key: String, _ value: String) -> String? {
        switch key {
        case "auto_close":
            guard ["off", "minimize", "close"].contains(value) else { return "auto_close must be off|minimize|close" }
        case "presentation":
            guard ["instant", "paced"].contains(value) else { return "presentation must be instant|paced" }
        case "managed_displays":
            break
        case "downgrade_on_unmanaged_kill":
            guard ["true", "false"].contains(value) else { return "downgrade_on_unmanaged_kill must be true|false" }
        case "step_ms":
            guard let n = UInt64(value), (50...5000).contains(n) else { return "step_ms must be 50..5000" }
        case "countdown_seconds":
            guard let n = UInt64(value), n <= 300 else { return "countdown_seconds must be 0..300" }
        default:
            return "unknown key: \(key)"
        }
        var map = configAll()
        if let i = map.firstIndex(where: { $0.0 == key }) {
            map[i].1 = value
        } else {
            map.append((key, value))
        }
        ensureHome()
        var s = "# ddir config (edited by `ddir config`)\n"
        s += "# auto_close: off = never auto-close / minimize = minimize instead / close = AX close button\n"
        for (k, v) in map { s += "\(k)=\(v)\n" }
        atomicWrite(configPath(), s)
        return nil
    }
}
