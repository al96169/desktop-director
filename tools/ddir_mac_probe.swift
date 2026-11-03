import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

// ddir-mac probe: reads /tmp/ddir_cmd.json, writes /tmp/ddir_result.json
// Ops: caps | list | move | move_abs | close | hide | show | activate
// Everything driven by config so the binary never needs rebuilding (TCC grants survive).

func out(_ obj: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: "/tmp/ddir_result.json"))
}

func fail(_ msg: String) -> [String: Any] { ["ok": false, "error": msg] }

func axWindows(_ app: NSRunningApplication) -> [AXUIElement] {
    let el = AXUIElementCreateApplication(app.processIdentifier)
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}

func attrString(_ el: AXUIElement, _ attr: String) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
    return (v as? String) ?? ""
}

func attrPoint(_ el: AXUIElement, _ attr: String) -> CGPoint {
    var v: CFTypeRef?
    var p = CGPoint.zero
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let vv = v else { return .zero }
    if CFGetTypeID(vv) == AXValueGetTypeID() { AXValueGetValue(vv as! AXValue, .cgPoint, &p) }
    return p
}

func attrSize(_ el: AXUIElement, _ attr: String) -> CGSize {
    var v: CFTypeRef?
    var s = CGSize.zero
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let vv = v else { return .zero }
    if CFGetTypeID(vv) == AXValueGetTypeID() { AXValueGetValue(vv as! AXValue, .cgSize, &s) }
    return s
}

func findApp(_ name: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first {
        ($0.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame || ($0.bundleIdentifier ?? "") == name
    }
}

func windowInfo(_ app: NSRunningApplication) -> [[String: Any]] {
    axWindows(app).enumerated().map { idx, w in
        let pt = attrPoint(w, kAXPositionAttribute as String)
        let sz = attrSize(w, kAXSizeAttribute as String)
        return [
            "index": idx,
            "title": attrString(w, kAXTitleAttribute as String),
            "role": attrString(w, kAXRoleAttribute as String),
            "subrole": attrString(w, kAXSubroleAttribute as String),
            "x": Int(pt.x), "y": Int(pt.y), "w": Int(sz.width), "h": Int(sz.height),
            "minimized": attrString(w, kAXMinimizedAttribute as String)
        ]
    }
}

func caps() -> [String: Any] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(count, 1)))
    CGGetActiveDisplayList(count, &ids, &count)
    var displays: [[String: Any]] = []
    for id in ids.prefix(Int(count)) {
        let b = CGDisplayBounds(id)
        displays.append(["id": id, "x": Int(b.origin.x), "y": Int(b.origin.y),
                         "w": Int(b.size.width), "h": Int(b.size.height),
                         "main": CGDisplayIsMain(id) != 0,
                         "scale": Double(CGDisplayPixelsWide(id)) / max(Double(b.size.width), 1)])
    }
    return [
        "ok": true,
        "platform": "macos",
        "accessibility": AXIsProcessTrusted(),
        "screen_recording": CGPreflightScreenCaptureAccess(),
        "idle_s": CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!),
        "displays": displays,
        "caps": [
            "window_move": AXIsProcessTrusted(),
            "window_hide": AXIsProcessTrusted() ? "app" : false,
            "window_close": AXIsProcessTrusted(),
            "focus_control": AXIsProcessTrusted(),
            "display_enumerate": true,
            "thumbnail": CGPreflightScreenCaptureAccess(),
            "idle_signal": "input"
        ]
    ]
}

let cmdPath = "/tmp/ddir_cmd.json"
guard let raw = try? String(contentsOfFile: cmdPath, encoding: .utf8),
      let data = raw.data(using: .utf8),
      let cmd = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    out(fail("cannot read \(cmdPath)"))
    exit(1)
}

let op = (cmd["op"] as? String) ?? "caps"
let appName = (cmd["app"] as? String) ?? ""

switch op {
case "caps":
    out(caps())

case "list":
    var result: [String: Any] = ["ok": true, "apps": []]
    var rows: [[String: Any]] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let wins = windowInfo(app)
        if wins.isEmpty { continue }
        rows.append(["app": app.localizedName ?? "?", "pid": Int(app.processIdentifier), "windows": wins])
    }
    result["apps"] = rows
    out(result)

case "move", "move_abs":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    let wins = axWindows(app)
    guard let w = wins.first else { out(fail("no window")); exit(3) }
    let before = attrPoint(w, kAXPositionAttribute as String)
    let size = attrSize(w, kAXSizeAttribute as String)
    var target = before
    if op == "move" {
        target.x += CGFloat((cmd["dx"] as? Int) ?? 40)
        target.y += CGFloat((cmd["dy"] as? Int) ?? 0)
    } else {
        target.x = CGFloat((cmd["x"] as? Int) ?? 100)
        target.y = CGFloat((cmd["y"] as? Int) ?? 100)
    }
    var t = target
    let posErr = AXValueCreate(.cgPoint, &t).map { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, $0).rawValue } ?? -999
    var after = attrPoint(w, kAXPositionAttribute as String)
    var restoreErr: Int32 = 0
    if (cmd["restore"] as? Bool) ?? false {
        var b = before
        restoreErr = AXValueCreate(.cgPoint, &b).map { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, $0).rawValue } ?? -999
        after = attrPoint(w, kAXPositionAttribute as String)
    }
    out(["ok": posErr == 0, "op": op, "app": appName,
         "before": ["x": Int(before.x), "y": Int(before.y), "w": Int(size.width), "h": Int(size.height)],
         "after": ["x": Int(after.x), "y": Int(after.y)],
         "set_err": posErr, "restore_err": restoreErr])

case "close":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    guard let w = axWindows(app).first else { out(fail("no window")); exit(3) }
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &v) == .success, let btn = v else {
        out(fail("no close button")); exit(4)
    }
    let err = AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString).rawValue
    out(["ok": err == 0, "op": "close", "app": appName, "press_err": err])

case "hide":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    out(["ok": true, "op": "hide", "app": appName, "hidden": app.hide()])

case "show":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    out(["ok": true, "op": "show", "app": appName, "unhidden": app.unhide()])

case "activate":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    out(["ok": true, "op": "activate", "app": appName, "activated": app.activate(options: [])])

case "hide_ax":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    let el = AXUIElementCreateApplication(app.processIdentifier)
    let err = AXUIElementSetAttributeValue(el, kAXHiddenAttribute as CFString, kCFBooleanTrue).rawValue
    out(["ok": err == 0, "op": "hide_ax", "app": appName, "set_err": err])

case "minimize":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    guard let w = axWindows(app).first else { out(fail("no window")); exit(3) }
    let err = AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanTrue).rawValue
    out(["ok": err == 0, "op": "minimize", "app": appName, "set_err": err])

case "app_quit":
    guard let app = findApp(appName) else { out(fail("app not running: \(appName)")); exit(2) }
    out(["ok": true, "op": "app_quit", "app": appName, "terminated": app.terminate()])

case "request_screen_recording":
    out(["ok": true, "op": "request_screen_recording", "granted": CGRequestScreenCaptureAccess()])

default:
    out(fail("unknown op: \(op)"))
}
