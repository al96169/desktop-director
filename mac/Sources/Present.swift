// Presentation queue — same contract as src/present.rs:
//   instant -> apply immediately (machine speed)
//   paced   -> enqueue ops, applied at step_ms cadence by flush / demo
// Ops are tiny files in ~/.ddir/queue so producer and consumer never share a mutable file.

import Foundation

enum Present {
    static func queueDir() -> String { Store.shared.path("queue") }

    static func stepMs() -> UInt64 {
        guard let v = Store.shared.configGet("step_ms"), let n = UInt64(v) else { return 400 }
        return min(max(n, 50), 5000)
    }

    static func presentation() -> String {
        Store.shared.configGet("presentation") ?? "instant"
    }

    @discardableResult
    static func enqueue(_ ops: [(ref: String, rect: [Int])], raise: Bool) -> Int {
        let dir = queueDir()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let base = nowMillis()
        let step = stepMs()
        let pid = getpid()
        for (i, op) in ops.enumerated() {
            let due = base + UInt64(i + 1) * step
            let name = "\(due)-\(pid)-\(i).op"
            let body = "\(op.ref)\t\(op.rect[0])\t\(op.rect[1])\t\(op.rect[2])\t\(op.rect[3])\t\(raise ? 1 : 0)\n"
            try? body.write(toFile: "\(dir)/\(name)", atomically: false, encoding: .utf8)
        }
        Store.shared.log("present: queued \(ops.count) ops (step=\(step)ms)")
        return ops.count
    }

    private static func applyOne(_ path: String) -> Bool {
        let txt = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let f = txt.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard f.count >= 5, let x = Int(f[1]), let y = Int(f[2]), let w = Int(f[3]), let h = Int(f[4]) else { return false }
        let ok = MacWin.shared.setRect(f[0], [x, y, w, h]).0
        if f.count > 5, f[5] == "1" { MacWin.shared.raiseNoActivate(f[0]) }
        return ok
    }

    static func pending() -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: queueDir()) else { return 0 }
        return items.count
    }

    /// Apply everything due; keep going until the queue drains or the deadline passes.
    @discardableResult
    static func drain(_ maxWaitMs: UInt64) -> Int {
        let deadline = nowMillis() + maxWaitMs
        var applied = 0
        while true {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: queueDir()) else { break }
            if items.isEmpty { break }
            let now = nowMillis()
            var did = false
            for name in items.sorted() {
                guard let due = UInt64(name.split(separator: "-").first ?? ""), due <= now else { continue }
                if applyOne("\(queueDir())/\(name)") {
                    applied += 1
                    did = true
                }
            }
            if now >= deadline { break }
            if !did { usleep(40_000) }
        }
        if applied > 0 { Store.shared.log("present: applied \(applied) ops") }
        return applied
    }

    static func tick() {
        if FileManager.default.fileExists(atPath: queueDir()) {
            _ = drain(0)
        }
    }
}
