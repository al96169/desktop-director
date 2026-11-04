// ddir macOS backend — window/display/input layer on top of the Accessibility API.
//
// Verified platform facts (see docs/macos-findings.md, don't re-litigate):
//   * windows are enumerated and moved with AXUIElement + kAXPositionAttribute/kAXSizeAttribute
//   * hide is *app level* (kAXHiddenAttribute on the application element); NSRunningApplication.hide()
//     is unreliable on background apps, so it is only used as a fallback
//   * close = press kAXCloseButtonAttribute; the window goes away, the process stays alive
//   * all coordinates are points, origin at the top-left of the main display (same space as CG)
//   * macOS has no HWND: window identity is "pid:CGWindowNumber", falling back to "pid:index"
//   * a signed binary inside ~/Applications/Ddir.app keeps its TCC (accessibility) grant across rebuilds

import AppKit
import ApplicationServices
import CoreGraphics

struct Display {
    var uid: String
    var gdi: String
    var label: String
    var primary: Bool
    var monitor: [Int]
    var work: [Int]
    var managed: Bool
    var scale: Double
}

struct WinInfo {
    var pid: pid_t
    var cgwin: UInt32?
    var ref: String          // "pid:cgwin" or "pid:index"
    var index: Int
    var app: String
    var title: String
    var subrole: String
    var frame: [Int]         // AX position/size (what we also use as `win`)
    var win: [Int]
    var dpi: Int
    var scale: Double
    var maximized: Bool
    var minimized: Bool
    var hidden: Bool
    var display: String
    var foreground: Bool
}

final class MacWin {
    static let shared = MacWin()

    // MARK: - permissions

    var axTrusted: Bool { AXIsProcessTrusted() }
    var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    func requestAX() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - app elements

    func appElement(_ pid: pid_t) -> AXUIElement {
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 1.0)
        return el
    }

    func axWindows(_ pid: pid_t) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement(pid), kAXWindowsAttribute as CFString, &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    func str(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let vv = v else { return "" }
        return (vv as? String) ?? ""
    }

    func bool(_ el: AXUIElement, _ attr: String) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let n = v as? NSNumber else { return false }
        return n.boolValue
    }

    func point(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let vv = v, CFGetTypeID(vv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        guard AXValueGetValue(vv as! AXValue, .cgPoint, &p) else { return nil }
        return p
    }

    func size(_ el: AXUIElement, _ attr: String) -> CGSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let vv = v, CFGetTypeID(vv) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        guard AXValueGetValue(vv as! AXValue, .cgSize, &s) else { return nil }
        return s
    }

    func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement(pid), kAXFocusedWindowAttribute as CFString, &v) == .success,
              let vv = v else { return nil }
        return (vv as! AXUIElement)
    }

    // MARK: - displays

    /// NSScreen uses bottom-left global coordinates; AX/CG use top-left of the main display.
    private func cgRect(_ r: NSRect) -> [Int] {
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        return [Int((r.origin.x).rounded()), Int((mainH - r.origin.y - r.height).rounded()),
                Int(r.width.rounded()), Int(r.height.rounded())]
    }

    func displays() -> [Display] {
        var out: [Display] = []
        for (i, screen) in NSScreen.screens.enumerated() {
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let cgid = CGDirectDisplayID(num?.uint32Value ?? 0)
            let mon = cgRect(screen.frame)
            let work = cgRect(screen.visibleFrame)
            let scale = Double(screen.backingScaleFactor)
            let uid = cgid == 0 ? "screen-\(i)" : "cg-\(cgid)"
            out.append(Display(
                uid: uid,
                gdi: "DISPLAY\(i + 1)",
                label: "\(mon[2])x\(mon[3]) @ \(mon[0]),\(mon[1])" + (scale > 1 ? " @\(Int(scale))x" : ""),
                primary: CGDisplayIsMain(cgid) != 0 || i == 0,
                monitor: mon,
                work: work,
                managed: false,
                scale: scale
            ))
        }
        // Managed set comes from config: "all" | "all_except_primary" | comma separated uids/gdi.
        // Same rules (and the same single-display fallback) as the Windows backend.
        let cfg = Store.shared.configGet("managed_displays") ?? "all_except_primary"
        let single = out.count <= 1
        let list = cfg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for i in out.indices {
            if cfg == "all" {
                out[i].managed = true
            } else if cfg == "all_except_primary" {
                out[i].managed = single || !out[i].primary
            } else {
                out[i].managed = list.contains { $0 == out[i].uid || $0 == out[i].gdi || ($0 == "primary" && out[i].primary) }
            }
        }
        if cfg == "none" {
            for i in out.indices { out[i].managed = false }
            return out
        }
        if !out.contains(where: { $0.managed }) {
            for i in out.indices { out[i].managed = single || !out[i].primary }
        }
        return out
    }

    func managedDisplays() -> [Display] {
        displays().filter { $0.managed }
    }

    func display(containing center: CGPoint) -> String? {
        for d in displays() {
            if center.x >= CGFloat(d.monitor[0]), center.x < CGFloat(d.monitor[0] + d.monitor[2]),
               center.y >= CGFloat(d.monitor[1]), center.y < CGFloat(d.monitor[1] + d.monitor[3]) {
                return d.uid
            }
        }
        return nil
    }

    // MARK: - CG window numbers

    private var cgCache: [pid_t: [(num: UInt32, bounds: CGRect, title: String)]] = [:]

    private func cgWindows() -> [pid_t: [(num: UInt32, bounds: CGRect, title: String)]] {
        if !cgCache.isEmpty { return cgCache }
        var map: [pid_t: [(num: UInt32, bounds: CGRect, title: String)]] = [:]
        let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return map }
        for info in arr {
            guard let pidNum = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let num = info[kCGWindowNumber as String] as? NSNumber,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let x = b["X"] as? NSNumber, let y = b["Y"] as? NSNumber,
                  let w = b["Width"] as? NSNumber, let h = b["Height"] as? NSNumber else { continue }
            let pid = pid_t(pidNum.int32Value)
            let title = (info[kCGWindowName as String] as? String) ?? ""
            map[pid, default: []].append((UInt32(num.uint32Value), CGRect(x: x.doubleValue, y: y.doubleValue,
                                                                         width: w.doubleValue, height: h.doubleValue), title))
        }
        cgCache = map
        return map
    }

    func invalidateCG() { cgCache = [:] }

    /// Pair an AX window with its CGWindowNumber using pid + geometry (+ title when readable).
    private func cgNumber(pid: pid_t, frame: [Int], title: String, used: Set<UInt32> = []) -> UInt32? {
        let candidates = cgWindows()[pid] ?? []
        let target = CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
        var best: (UInt32, Double)?
        for c in candidates where !used.contains(c.num) {
            let dx = abs(c.bounds.origin.x - target.origin.x)
            let dy = abs(c.bounds.origin.y - target.origin.y)
            let dw = abs(c.bounds.width - target.width)
            let dh = abs(c.bounds.height - target.height)
            let dist = Double(dx + dy + dw + dh)
            guard dist <= 8 else { continue }
            if !c.title.isEmpty, !title.isEmpty, c.title != title { continue }
            if best == nil || dist < best!.1 { best = (c.num, dist) }
        }
        return best?.0
    }

    // MARK: - window list

    private var frontPid: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    /// Alt-Tab level windows: regular apps, real AX windows, non-empty titles.
    func listWindows() -> [WinInfo] {
        invalidateCG()
        let front = frontPid
        let ds = displays()
        // regular apps, plus accessory apps that actually own titled windows (e.g. `ddir play`).
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier > 0 && $0.processIdentifier != getpid() }
            .filter { app in
                if app.activationPolicy == .regular { return true }
                guard app.activationPolicy == .accessory else { return false }
                return axWindows(app.processIdentifier).contains { el in
                    str(el, kAXRoleAttribute as String) == "AXWindow"
                        && !str(el, kAXTitleAttribute as String).trimmingCharacters(in: .whitespaces).isEmpty
                }
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        let scale = Double(NSScreen.main?.backingScaleFactor ?? 1)
        var out: [WinInfo] = []
        for app in apps {
            if app.isHidden { continue }
            let pid = app.processIdentifier
            let appName = app.executableURL?.lastPathComponent ?? app.localizedName ?? app.bundleIdentifier ?? "?"
            let els = windowsForPid(pid)
            if els.isEmpty { continue }
            let focused = (pid == front) ? focusedWindow(pid) : nil
            let isHidden = app.isHidden
            for w in els {
                let el = w.el
                if str(el, kAXRoleAttribute as String) != "AXWindow" { continue }
                let subrole = str(el, kAXSubroleAttribute as String)
                if subrole == "AXSheet" { continue }
                if w.title.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if w.frame[2] <= 0 || w.frame[3] <= 0 { continue }
                let minimized = bool(el, kAXMinimizedAttribute as String)
                let fullscreen = bool(el, "AXFullScreen")
                let center = CGPoint(x: CGFloat(w.frame[0]) + CGFloat(w.frame[2]) / 2,
                                     y: CGFloat(w.frame[1]) + CGFloat(w.frame[3]) / 2)
                let disp = ds.first(where: { d in
                    center.x >= CGFloat(d.monitor[0]) && center.x < CGFloat(d.monitor[0] + d.monitor[2])
                        && center.y >= CGFloat(d.monitor[1]) && center.y < CGFloat(d.monitor[1] + d.monitor[3])
                })?.uid ?? "?"
                var nearlyFull = false
                if let d = ds.first(where: { $0.uid == disp }) {
                    nearlyFull = abs(w.frame[0] - d.work[0]) <= 2 && abs(w.frame[1] - d.work[1]) <= 2
                        && abs(w.frame[2] - d.work[2]) <= 2 && abs(w.frame[3] - d.work[3]) <= 2
                }
                out.append(WinInfo(
                    pid: pid, cgwin: w.cgwin, ref: w.ref, index: w.index, app: appName, title: w.title,
                    subrole: subrole, frame: w.frame, win: w.frame,
                    dpi: Int(72.0 * scale), scale: scale,
                    maximized: fullscreen || nearlyFull, minimized: minimized, hidden: isHidden,
                    display: disp,
                    foreground: (pid == front && focused != nil && CFEqual(el, focused!))
                ))
            }
        }
        return out
    }

    /// One pass over an app's AX windows, assigning every window a unique ref.
    /// CGWindowNumber is unique per window, so the mapping must never hand the same
    /// number to two AX elements (two documents can share title and geometry).
    func windowsForPid(_ pid: pid_t) -> [(el: AXUIElement, index: Int, ref: String, frame: [Int], title: String, cgwin: UInt32?)] {
        let els = axWindows(pid)
        var used = Set<UInt32>()
        var out: [(el: AXUIElement, index: Int, ref: String, frame: [Int], title: String, cgwin: UInt32?)] = []
        for (idx, el) in els.enumerated() {
            guard let pos = point(el, kAXPositionAttribute as String),
                  let sz = size(el, kAXSizeAttribute as String) else {
                out.append((el, idx, "\(pid):\(idx)", [0, 0, 0, 0], "", nil))
                continue
            }
            let title = str(el, kAXTitleAttribute as String)
            let frame = [Int(pos.x.rounded()), Int(pos.y.rounded()), Int(sz.width.rounded()), Int(sz.height.rounded())]
            if let n = cgNumber(pid: pid, frame: frame, title: title, used: used) {
                used.insert(n)
                out.append((el, idx, "\(pid):\(n)", frame, title, n))
            } else {
                out.append((el, idx, "\(pid):\(idx)", frame, title, nil))
            }
        }
        return out
    }

    // MARK: - refs

    /// Accepts "pid:cgwin", "pid:index" and (for hand typed input) "pid".
    func parseRef(_ s: String) -> (pid: pid_t, key: String)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let colon = t.firstIndex(of: ":") else {
            guard let p = pid_t(t) else { return nil }
            return (p, "0")
        }
        let pidPart = String(t[t.startIndex..<colon])
        let key = String(t[t.index(after: colon)...])
        guard let p = pid_t(pidPart) else { return nil }
        return (p, key)
    }

    func resolve(_ ref: String) -> AXUIElement? {
        guard let r = parseRef(ref) else { return nil }
        invalidateCG()
        let els = windowsForPid(r.pid)
        if let hit = els.first(where: { $0.ref == ref }) { return hit.el }
        if let n = Int(r.key), n >= 0, n < els.count { return els[n].el }
        return nil
    }

    func isWindow(_ ref: String) -> Bool {
        guard let r = parseRef(ref) else { return false }
        invalidateCG()
        let els = windowsForPid(r.pid)
        if els.contains(where: { $0.ref == ref }) { return true }
        if let n = Int(r.key), n >= 0, n < els.count { return true }
        return false
    }

    func appName(_ pid: pid_t) -> String {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return "?" }
        if let exe = app.executableURL?.lastPathComponent, !exe.isEmpty { return exe }
        return app.localizedName ?? app.bundleIdentifier ?? "?"
    }

    func appAliases(_ pid: pid_t) -> [String] {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
        var out: [String] = []
        if let exe = app.executableURL?.lastPathComponent, !exe.isEmpty { out.append(exe) }
        if let n = app.localizedName, !n.isEmpty { out.append(n) }
        if let b = app.bundleIdentifier, !b.isEmpty { out.append(b) }
        return out
    }

    func bundlePath(_ pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.bundleURL?.path ?? ""
    }

    func bundleId(_ pid: pid_t) -> String {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    }

    func appPids(named name: String) -> [pid_t] {
        NSWorkspace.shared.runningApplications
            .filter { ($0.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame
                      || ($0.bundleIdentifier ?? "").caseInsensitiveCompare(name) == .orderedSame }
            .map { $0.processIdentifier }
    }

    func runningApps() -> [(pid: pid_t, name: String, bundle: String, hidden: Bool)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { ($0.processIdentifier, $0.localizedName ?? $0.bundleIdentifier ?? "?", $0.bundleIdentifier ?? "", $0.isHidden) }
    }

    // MARK: - geometry

    /// Move + resize one window. Returns (applied, actual rect).
    @discardableResult
    func setRect(_ ref: String, _ rect: [Int]) -> (Bool, [Int]) {
        guard let el = resolve(ref) else { return (false, [0, 0, 0, 0]) }
        if bool(el, "AXFullScreen") {
            AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanFalse)
            usleep(350_000)
        }
        var target = CGPoint(x: CGFloat(rect[0]), y: CGFloat(rect[1]))
        var sz = CGSize(width: CGFloat(rect[2]), height: CGFloat(rect[3]))
        let posErr = AXValueCreate(.cgPoint, &target).map {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, $0).rawValue
        } ?? -999
        let sizeErr = AXValueCreate(.cgSize, &sz).map {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, $0).rawValue
        } ?? -999
        var actual = readRect(el)
        // Some apps clamp a resize until they have been moved; retry size-first once.
        if sizeErr != 0 || abs(actual[2] - rect[2]) > 2 || abs(actual[3] - rect[3]) > 2 {
            let e2 = AXValueCreate(.cgSize, &sz).map {
                AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, $0).rawValue
            } ?? -999
            var t2 = target
            let p2 = AXValueCreate(.cgPoint, &t2).map {
                AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, $0).rawValue
            } ?? -999
            actual = readRect(el)
            return (posErr == 0 && (sizeErr == 0 || e2 == 0) && p2 == 0, actual)
        }
        return (posErr == 0, actual)
    }

    func readRect(_ el: AXUIElement) -> [Int] {
        guard let p = point(el, kAXPositionAttribute as String),
              let s = size(el, kAXSizeAttribute as String) else { return [0, 0, 0, 0] }
        return [Int(p.x.rounded()), Int(p.y.rounded()), Int(s.width.rounded()), Int(s.height.rounded())]
    }

    // MARK: - visibility

    @discardableResult
    func hideApp(_ pid: pid_t) -> Bool {
        let el = appElement(pid)
        let err = AXUIElementSetAttributeValue(el, kAXHiddenAttribute as CFString, kCFBooleanTrue)
        if err == .success { return true }
        return NSRunningApplication(processIdentifier: pid)?.hide() ?? false
    }

    /// Close the window of `pid` whose AX title equals `title`. Used when a ref may have been
    /// remapped since it was recorded (two windows can share geometry and index fallbacks).
    @discardableResult
    func closeWindow(pid: pid_t, title: String) -> Bool {
        for el in axWindows(pid) where str(el, kAXTitleAttribute as String) == title {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXCloseButtonAttribute as CFString, &v) == .success,
                  let btn = v else { continue }
            let err = AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
            // -25204 (cannotComplete) is normal when the app quits while handling the close;
            // confirm by looking for the title afterwards instead of trusting the return code.
            if err == .success || err == .cannotComplete {
                usleep(200_000)
                let still = axWindows(pid).contains { str($0, kAXTitleAttribute as String) == title }
                return !still
            }
        }
        return false
    }

    func showApp(_ pid: pid_t) -> Bool {
        let el = appElement(pid)
        let err = AXUIElementSetAttributeValue(el, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        if err == .success { return true }
        return NSRunningApplication(processIdentifier: pid)?.unhide() ?? false
    }

    @discardableResult
    func minimize(_ ref: String) -> Bool {
        guard let el = resolve(ref) else { return false }
        return AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    @discardableResult
    func restore(_ ref: String) -> Bool {
        guard let el = resolve(ref) else { return false }
        return AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }

    /// Press the close button. The window disappears, the process stays alive (unlike WM_CLOSE).
    @discardableResult
    func closeWindow(_ ref: String) -> Bool {
        guard let el = resolve(ref) else { return false }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXCloseButtonAttribute as CFString, &v) == .success,
              let btn = v else { return false }
        return AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString) == .success
    }

    func raiseNoActivate(_ ref: String) {
        // macOS has no z-order API for other apps' windows; activating would steal focus (D2/D4).
        // Nothing to do — kept so callers stay platform-neutral.
    }

    // MARK: - input / identity

    func idleSeconds() -> Int {
        for raw in [UInt32.max, 0] {
            if let t = CGEventType(rawValue: raw) {
                let s = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: t)
                if s > 0 { return Int(s) }
            }
        }
        return -1
    }

    func cursor() -> (Int, Int) {
        guard let e = CGEvent(source: nil) else { return (-1, -1) }
        return (Int(e.location.x.rounded()), Int(e.location.y.rounded()))
    }

    func foregroundRef() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "none" }
        let pid = front.processIdentifier
        guard let el = focusedWindow(pid) else { return "pid:\(pid)" }
        let r = readRect(el)
        let cgn = cgNumber(pid: pid, frame: r, title: str(el, kAXTitleAttribute as String))
        return cgn != nil ? "\(pid):\(cgn!)" : "pid:\(pid)"
    }

    func parentPid(_ pid: pid_t) -> pid_t? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let r = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if r != 0 { return nil }
        return info.kp_eproc.e_ppid
    }

    func procName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : "?"
    }

    /// Agent identity = host process up the parent chain (D18): several CLI calls from the same
    /// agent (terminal / IDE / harness) share one identity, so ownership survives across calls.
    func agentId() -> String {
        if let v = ProcessInfo.processInfo.environment["DDIR_AGENT"], !v.isEmpty { return v }
        var cur = getpid()
        var name = "ddir"
        for _ in 0..<12 {
            guard let ppid = parentPid(cur), ppid > 1 else { break }
            let pname = procName(ppid)
            let lower = pname.lowercased()
            if ["launchd", "kernel_task", "loginwindow"].contains(lower) { break }
            cur = ppid
            name = pname
        }
        return "\(name)-\(cur)".replacingOccurrences(of: " ", with: "_")
    }

    func workSize() -> (Int, Int) {
        guard let d = displays().first else { return (0, 0) }
        return (d.work[2], d.work[3])
    }

    // MARK: - activity (D19: cursor moved > 25pt or foreground changed)

    func activity() -> (idle: Int, moved: Int, fgChanged: Bool, active: Bool) {
        let cur = cursor()
        let fg = foregroundRef()
        let p = Store.shared.path("activity.tsv")
        let prev = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        var moved = 0
        var fgChanged = false
        let t = prev.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            let f = t.components(separatedBy: "\t")
            if f.count >= 3 {
                let px = Int(f[0]) ?? cur.0
                let py = Int(f[1]) ?? cur.1
                moved = abs(cur.0 - px) + abs(cur.1 - py)
                fgChanged = f[2] != fg
            }
        }
        try? "\(cur.0)\t\(cur.1)\t\(fg)".write(toFile: p, atomically: false, encoding: .utf8)
        let idle = idleSeconds()
        return (idle, moved, fgChanged, moved > 25 || fgChanged)
    }
}
