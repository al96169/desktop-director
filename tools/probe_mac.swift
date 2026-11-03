import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

func p(_ k: String, _ v: Any) { print("\(k): \(v)") }

p("AX_TRUSTED", AXIsProcessTrusted())

// screens
var dcount: UInt32 = 0
CGGetActiveDisplayList(0, nil, &dcount)
p("DISPLAY_COUNT", dcount)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(dcount, 1)))
CGGetActiveDisplayList(dcount, &ids, &dcount)
for id in ids.prefix(Int(dcount)) {
    let b = CGDisplayBounds(id)
    let mm = CGDisplayScreenSize(id)
    p("DISPLAY", "\(id) bounds=\(Int(b.origin.x)),\(Int(b.origin.y)) \(Int(b.size.width))x\(Int(b.size.height)) mm=\(Int(mm.width))x\(Int(mm.height)) main=\(CGDisplayIsMain(id) != 0)")
}

// windows (CGWindowList; names need Screen Recording)
var entries: [[String: Any]] = []
if let arr = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
    entries = arr
}
p("CGWINDOW_TOTAL", entries.count)
var layer0 = 0
var shown = 0
for w in entries {
    let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
    guard layer == 0 else { continue }
    layer0 += 1
    if shown >= 15 { continue }
    shown += 1
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
    let title = (w[kCGWindowName as String] as? String) ?? "<no-title>"
    let pid = (w[kCGWindowOwnerPID as String] as? Int) ?? -1
    let wid = (w[kCGWindowNumber as String] as? Int) ?? -1
    let b = (w[kCGWindowBounds as String] as? [String: Any]) ?? [:]
    let x = b["X"] ?? 0, y = b["Y"] ?? 0, ww = b["Width"] ?? 0, hh = b["Height"] ?? 0
    p("WIN", "id=\(wid) pid=\(pid) owner=\(owner) title=\(title) rect=\(x),\(y),\(ww),\(hh)")
}
p("CGWINDOW_LAYER0", layer0)

// AX probe: try to read windows of Finder (needs Accessibility)
if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
    let appEl = AXUIElementCreateApplication(finder.processIdentifier)
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
    var n = -1
    if err == .success, let arr = value as? [AXUIElement] { n = arr.count }
    p("AX_FINDER_WINDOWS", "err=\(err.rawValue) count=\(n)")
    if err == .success, let arr = value as? [AXUIElement], let first = arr.first {
        var pos: CFTypeRef?
        var size: CFTypeRef?
        let e1 = AXUIElementCopyAttributeValue(first, kAXPositionAttribute as CFString, &pos)
        let e2 = AXUIElementCopyAttributeValue(first, kAXSizeAttribute as CFString, &size)
        var pt = CGPoint.zero
        var sz = CGSize.zero
        if let pos = pos, CFGetTypeID(pos) == AXValueGetTypeID() { AXValueGetValue(pos as! AXValue, .cgPoint, &pt) }
        if let size = size, CFGetTypeID(size) == AXValueGetTypeID() { AXValueGetValue(size as! AXValue, .cgSize, &sz) }
        p("AX_FINDER_FIRST_WINDOW", "posErr=\(e1.rawValue) sizeErr=\(e2.rawValue) pos=\(Int(pt.x)),\(Int(pt.y)) size=\(Int(sz.width))x\(Int(sz.height))")
    }
} else {
    p("AX_FINDER", "not running")
}

// idle seconds
p("IDLE_SECONDS", CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))