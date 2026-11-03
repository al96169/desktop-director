import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

func p(_ k: String, _ v: Any) { print("\(k): \(v)") }
freopen("/tmp/ddir_probe.out", "w", stdout)
setvbuf(stdout, nil, _IOLBF, 0)

// 1) ask for Accessibility (shows the system dialog the first time)
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(opts)
p("AX_TRUSTED", trusted)

// 2) windows via CG (titles need Screen Recording)
var entries: [[String: Any]] = []
if let arr = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
    entries = arr
}
var layer0 = 0
var withTitle = 0
for w in entries {
    let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
    if layer != 0 { continue }
    layer0 += 1
    if let t = w[kCGWindowName as String] as? String, !t.isEmpty { withTitle += 1 }
}
p("CGWINDOW_LAYER0", layer0)
p("CGWINDOW_WITH_TITLE", withTitle)

// 3) if trusted: move Finder's front window by 40pt, then read it back
if trusted, let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
    let app = AXUIElementCreateApplication(finder.processIdentifier)
    var val: CFTypeRef?
    let e = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &val)
    if e == .success, let wins = val as? [AXUIElement], let w0 = wins.first {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var pt = CGPoint.zero
        var sz = CGSize.zero
        _ = AXUIElementCopyAttributeValue(w0, kAXPositionAttribute as CFString, &posRef)
        _ = AXUIElementCopyAttributeValue(w0, kAXSizeAttribute as CFString, &sizeRef)
        if let pr = posRef { AXValueGetValue(pr as! AXValue, .cgPoint, &pt) }
        if let sr = sizeRef { AXValueGetValue(sr as! AXValue, .cgSize, &sz) }
        p("FINDER_BEFORE", "pos=\(Int(pt.x)),\(Int(pt.y)) size=\(Int(sz.width))x\(Int(sz.height))")
        var np = CGPoint(x: pt.x + 40, y: pt.y)
        if let nv = AXValueCreate(.cgPoint, &np) {
            let setErr = AXUIElementSetAttributeValue(w0, kAXPositionAttribute as CFString, nv)
            p("AX_SET_POSITION", "err=\(setErr.rawValue)")
        }
        var pt2 = CGPoint.zero
        var posRef2: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(w0, kAXPositionAttribute as CFString, &posRef2)
        if let pr2 = posRef2 { AXValueGetValue(pr2 as! AXValue, .cgPoint, &pt2) }
        p("FINDER_AFTER", "pos=\(Int(pt2.x)),\(Int(pt2.y))")
        // put it back so the probe leaves no trace
        var orig = pt
        if let back = AXValueCreate(.cgPoint, &orig) {
            let e3 = AXUIElementSetAttributeValue(w0, kAXPositionAttribute as CFString, back)
            p("AX_RESTORE", "err=\(e3.rawValue)")
        }
    } else {
        p("AX_FINDER_WINDOWS", "err=\(e.rawValue)")
    }
} else if !trusted {
    p("NOTE", "not trusted: grant Accessibility to this app, then re-run")
}

p("DISPLAYS", (CGGetActiveDisplayList(0, nil, nil) == .success ? "ok" : "fail"))
p("IDLE_SECONDS", CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
