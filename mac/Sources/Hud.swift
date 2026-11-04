// ddir macOS backend — HUD layer (kept deliberately lightweight).
//
// Two styles, one of them cheap enough to use by default:
//   toast (default)  small corner card, app icons + titles, no screen capture, ~0 CPU, static snapshot
//   wall             full-screen dim + live thumbnail wall (ScreenCaptureKit, needs Screen Recording)
//
//   ddir hud                  toast on the managed display, 3s
//   ddir hud --wall           full-screen thumbnail wall, 6s
//   ddir hud --seconds N      custom duration
//   ddir hud --check          print what would be shown (JSON), open nothing
//
// macOS 15 removed CGWindowListCreateImage, so live thumbnails are ScreenCaptureKit only
// (SCScreenshotManager, macOS 14+). The default toast style does not depend on it at all.

import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

enum HudStyle: String {
    case toast
    case wall
}

final class HudTile {
    var ref: String
    var app: String
    var title: String
    var rect: [Int]
    var icon: NSImage?
    var thumb: NSImage?
    var agent: String = ""

    init(ref: String, app: String, title: String, rect: [Int]) {
        self.ref = ref
        self.app = app
        self.title = title
        self.rect = rect
    }
}

private func accentColor(_ mode: String) -> NSColor {
    switch mode {
    case "auto": return NSColor(calibratedRed: 0.36, green: 0.95, blue: 0.52, alpha: 1)
    case "semi": return NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.25, alpha: 1)
    default: return NSColor(white: 0.62, alpha: 1)
    }
}

private func drawTruncated(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
    let p = NSMutableParagraphStyle()
    p.lineBreakMode = .byTruncatingTail
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
    (text as NSString).draw(in: rect, withAttributes: attrs)
}

// MARK: - toast (default, no capture)

final class HudToastView: NSView {
    var tiles: [HudTile] = []
    var mode: String = "semi"

    static let width: CGFloat = 360
    static func height(rows: Int) -> CGFloat { 10 + 26 + CGFloat(max(rows, 1)) * 26 + 8 }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.82).setFill()
        card.fill()
        accentColor(mode).withAlphaComponent(0.45).setStroke()
        card.lineWidth = 1
        card.stroke()

        let accent = accentColor(mode)
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: bounds.height - 20, width: 8, height: 8)).fill()
        let head = "DDIR  ·  \(mode)  ·  \(tiles.count) 窗口"
        drawTruncated(head, in: NSRect(x: 30, y: bounds.height - 26, width: bounds.width - 44, height: 16),
                      font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
                      color: NSColor.white.withAlphaComponent(0.92))

        if tiles.isEmpty {
            drawTruncated("（暂无租约）", in: NSRect(x: 16, y: 12, width: bounds.width - 32, height: 16),
                          font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.5))
            return
        }

        for (i, t) in tiles.prefix(4).enumerated() {
            let y = bounds.height - 26 - 26 - CGFloat(i) * 26
            if let icon = t.icon {
                icon.draw(in: NSRect(x: 14, y: y + 5, width: 16, height: 16), from: .zero,
                          operation: .sourceOver, fraction: 0.95)
            }
            var text = "\(t.app)  —  \(t.title)"
            if !t.agent.isEmpty, t.agent != win.agentId() { text += "  (\(t.agent))" }
            drawTruncated(text, in: NSRect(x: 38, y: y + 4, width: bounds.width - 52, height: 18),
                          font: .systemFont(ofSize: 11, weight: .regular),
                          color: NSColor.white.withAlphaComponent(0.78))
        }
    }
}

// MARK: - wall (full screen + live thumbnails)

final class HudWallView: NSView {
    var mode: String = "semi"
    var tiles: [HudTile] = []
    var note: String = ""

    private func tileRects(in bounds: NSRect) -> [NSRect] {
        let n = max(tiles.count, 1)
        let pad: CGFloat = 28
        let top: CGFloat = 64
        let avail = NSRect(x: bounds.minX + pad, y: bounds.minY + pad,
                           width: bounds.width - 2 * pad, height: bounds.height - 2 * pad - top)
        let cols = n <= 1 ? 1 : (n == 2 ? 2 : (n == 3 ? 3 : 3))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let gap: CGFloat = 18
        let cw = (avail.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let ch = (avail.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
        return (0..<n).map { i in
            let c = i % cols, r = i / cols
            return NSRect(x: avail.minX + CGFloat(c) * (cw + gap),
                          y: avail.maxY - CGFloat(r + 1) * ch - CGFloat(r) * gap,
                          width: cw, height: ch)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.78).setFill()
        bounds.fill()

        let head = "DDIR  ·  \(mode)  ·  \(tiles.count) 窗口"
        drawTruncated(head, in: NSRect(x: 30, y: bounds.height - 48, width: bounds.width - 60, height: 28),
                      font: .monospacedSystemFont(ofSize: 20, weight: .semibold),
                      color: NSColor.white.withAlphaComponent(0.92))
        if !note.isEmpty {
            drawTruncated(note, in: NSRect(x: 32, y: bounds.height - 68, width: bounds.width - 64, height: 16),
                          font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                          color: NSColor.white.withAlphaComponent(0.55))
        }

        let rects = tileRects(in: bounds)
        for (i, tile) in tiles.enumerated() {
            let r = rects[i]
            let card = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
            NSColor.white.withAlphaComponent(0.06).setFill()
            card.fill()
            NSColor.white.withAlphaComponent(0.18).setStroke()
            card.lineWidth = 1
            card.stroke()

            let inner = r.insetBy(dx: 14, dy: 12)
            let captionH: CGFloat = 34
            let imageRect = NSRect(x: inner.minX, y: inner.minY + captionH,
                                   width: inner.width, height: inner.height - captionH)

            if let thumb = tile.thumb {
                let size = thumb.size
                if size.width > 0, size.height > 0 {
                    let scale = min(imageRect.width / size.width, imageRect.height / size.height)
                    let w = size.width * scale, h = size.height * scale
                    thumb.draw(in: NSRect(x: imageRect.midX - w / 2, y: imageRect.midY - h / 2, width: w, height: h),
                               from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            } else if let icon = tile.icon {
                let s = min(min(imageRect.width, imageRect.height), 128)
                icon.draw(in: NSRect(x: imageRect.midX - s / 2, y: imageRect.midY - s / 2, width: s, height: s),
                          from: .zero, operation: .sourceOver, fraction: 0.9)
            }

            var name = "\(tile.app)  ·  \(tile.title)"
            if !tile.agent.isEmpty, tile.agent != win.agentId() { name += "  ·  \(tile.agent)" }
            drawTruncated(name, in: NSRect(x: inner.minX + 2, y: r.minY + 20, width: inner.width - 4, height: 16),
                          font: .systemFont(ofSize: 12, weight: .medium),
                          color: NSColor.white.withAlphaComponent(0.9))
            let geo = "\(tile.rect[0]),\(tile.rect[1])  \(tile.rect[2])×\(tile.rect[3])   \(tile.ref)"
            drawTruncated(geo, in: NSRect(x: inner.minX + 2, y: r.minY + 6, width: inner.width - 4, height: 14),
                          font: .monospacedSystemFont(ofSize: 10, weight: .regular),
                          color: NSColor.white.withAlphaComponent(0.45))
        }
    }
}

// MARK: - controller

final class HudController {
    static let shared = HudController()

    private var windows: [NSWindow] = []
    private var views: [NSView] = []
    private var timer: Timer?
    private var deadline: Date = .distantFuture
    private var thumbs: [String: NSImage] = [:]
    private var terminateWhenDone = false
    private var style: HudStyle = .toast

    /// Tiles come from live leases (mine first, then other agents'), or — when nothing is
    /// leased — from the windows sitting on the managed display, so the HUD is never blank.
    func tiles(limit: Int = 6) -> [HudTile] {
        let now = nowUnix()
        let me = win.agentId()
        let live = store.leases().filter { $0.expires > now }
        let ordered = live.filter { $0.agent == me } + live.filter { $0.agent != me }
        let wins = win.listWindows()
        var out: [HudTile] = []
        for l in ordered {
            guard let w = wins.first(where: { $0.ref == l.window }) else { continue }
            let t = HudTile(ref: w.ref, app: w.app, title: w.title, rect: w.win)
            t.icon = NSWorkspace.shared.icon(forFile: win.bundlePath(w.pid))
            t.agent = l.agent
            out.append(t)
        }
        if out.isEmpty {
            let managed = win.managedDisplays().map { $0.uid }
            for w in wins where managed.contains(w.display) && !w.minimized {
                let t = HudTile(ref: w.ref, app: w.app, title: w.title, rect: w.win)
                t.icon = NSWorkspace.shared.icon(forFile: win.bundlePath(w.pid))
                out.append(t)
            }
        }
        return Array(out.prefix(limit))
    }

    @discardableResult
    func present(style: HudStyle = .toast, seconds: Double = 3, terminateWhenDone: Bool = false) -> Int {
        self.style = style
        self.terminateWhenDone = terminateWhenDone
        NSApplication.shared.setActivationPolicy(.accessory)

        let tiles = tiles(limit: style == .wall ? 6 : 4)
        if style == .toast {
            for screen in toastScreens() {
                let h = HudToastView.height(rows: min(tiles.count, 4))
                let vf = screen.visibleFrame
                // bottom-right: notification banners own the top-right corner
                let rect = NSRect(x: vf.maxX - HudToastView.width - 16, y: vf.minY + 16,
                                  width: HudToastView.width, height: h)
                let w = makeWindow(rect: rect, level: .floating)
                let v = HudToastView(frame: NSRect(origin: .zero, size: rect.size))
                v.tiles = tiles
                v.mode = store.mode()
                w.contentView = v
                windows.append(w)
                views.append(v)
                show(w)
            }
            store.log("hud: toast \(tiles.count) tiles on \(windows.count) display(s), \(seconds)s")
            scheduleClose(after: seconds)
        } else {
            let note = CGPreflightScreenCaptureAccess()
                ? "ScreenCaptureKit 缩略图 · \(VERSION)"
                : "仅应用图标：需要「屏幕录制」授权才能出缩略图 · \(VERSION)"
            for screen in NSScreen.screens where isManaged(screen) {
                let w = makeWindow(rect: screen.frame, level: .floating)
                let v = HudWallView(frame: NSRect(origin: .zero, size: screen.frame.size))
                v.mode = store.mode()
                v.tiles = tiles
                v.note = note
                w.contentView = v
                windows.append(w)
                views.append(v)
                show(w)
            }
            store.log("hud: wall \(tiles.count) tiles on \(windows.count) display(s), screen_recording=\(CGPreflightScreenCaptureAccess())")
            loadThumbnails()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            if let t = timer { RunLoop.main.add(t, forMode: .common) }
            deadline = Date().addingTimeInterval(seconds)
        }
        return tiles.count
    }

    private func makeWindow(rect: NSRect, level: NSWindow.Level) -> NSWindow {
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = level
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return w
    }

    private func show(_ w: NSWindow) {
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            w.animator().alphaValue = 1
        }
    }

    private func scheduleClose(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.close(fade: 0.3)
        }
    }

    private func close(fade: Double) {
        timer?.invalidate()
        timer = nil
        let closing = windows
        windows.removeAll()
        views.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fade
            for w in closing { w.animator().alphaValue = 0 }
        }, completionHandler: {
            for w in closing { w.orderOut(nil) }
            if self.terminateWhenDone { NSApp.terminate(nil) }
        })
    }

    /// wall style: keep tiles in sync while the overlay is up; thumbnails are cached by ref.
    private func tick() {
        let fresh = tiles(limit: style == .wall ? 6 : 4)
        for t in fresh where t.thumb == nil { t.thumb = thumbs[t.ref] }
        for v in views {
            guard let w = v as? HudWallView else { continue }
            w.tiles = fresh
            w.mode = store.mode()
            w.needsDisplay = true
        }
        if Date() >= deadline { close(fade: 0.3) }
    }

    private func isManaged(_ screen: NSScreen) -> Bool {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let id = CGDirectDisplayID(num?.uint32Value ?? 0)
        let uid = id == 0 ? "screen-0" : "cg-\(id)"
        return win.managedDisplays().contains { $0.uid == uid }
    }

    private func toastScreens() -> [NSScreen] {
        let managed = NSScreen.screens.filter { isManaged($0) }
        if !managed.isEmpty { return managed }
        return [NSScreen.main].compactMap { $0 }
    }

    // MARK: - ScreenCaptureKit thumbnails (wall only, macOS 14+)

    private func loadThumbnails() {
        guard CGPreflightScreenCaptureAccess() else { return }
        guard #available(macOS 14.0, *) else { return }
        let snapshot = views.compactMap { $0 as? HudWallView }
            .flatMap { $0.tiles }
            .filter { $0.thumb == nil && thumbs[$0.ref] == nil }
        guard !snapshot.isEmpty else { return }
        Task { @MainActor in
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            } catch {
                store.log("hud: SCShareableContent failed: \(error.localizedDescription)")
                return
            }
            var byID: [CGWindowID: SCWindow] = [:]
            for sw in content.windows { byID[sw.windowID] = sw }
            for tile in snapshot {
                guard let colon = tile.ref.firstIndex(of: ":"),
                      let cgid = UInt32(tile.ref[tile.ref.index(after: colon)...]),
                      let sc = byID[cgid] else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: sc)
                let cfg = SCStreamConfiguration()
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                cfg.width = Int(max(64, sc.frame.width) * scale)
                cfg.height = Int(max(64, sc.frame.height) * scale)
                cfg.showsCursor = false
                if let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    tile.thumb = img
                    self.thumbs[tile.ref] = img
                }
            }
            for v in self.views {
                guard let wv = v as? HudWallView else { continue }
                for t in wv.tiles where t.thumb == nil { t.thumb = self.thumbs[t.ref] }
                wv.needsDisplay = true
            }
            store.log("hud: thumbnails captured \(self.thumbs.count) (this round \(snapshot.count))")
        }
    }

    func checkJSON(style: HudStyle) -> String {
        let t = tiles(limit: style == .wall ? 6 : 4)
        let refs = t.map { "\"\(es($0.ref))\"" }.joined(separator: ",")
        return "{\"ok\":true,\"platform\":\"macos\",\"style\":\"\(style.rawValue)\",\"mode\":\"\(es(store.mode()))\","
            + "\"tiles\":\(t.count),\"screen_recording\":\(CGPreflightScreenCaptureAccess()),"
            + "\"accessibility\":\(win.axTrusted),\"displays\":\(win.managedDisplays().count),\"windows\":[\(refs)]}"
    }
}

func cmdHud(_ args: [String]) -> Int32 {
    let style: HudStyle = hasFlag(args, "--wall") ? .wall : .toast
    if hasFlag(args, "--check") {
        emit(HudController.shared.checkJSON(style: style))
        return 0
    }
    let defaultSecs: Double = style == .wall ? 6 : 3
    let secs = Double(argValue(args, "--seconds") ?? "") ?? defaultSecs
    let n = HudController.shared.present(style: style, seconds: secs, terminateWhenDone: true)
    emit("{\"ok\":true,\"style\":\"\(style.rawValue)\",\"tiles\":\(n),\"seconds\":\(secs),"
         + "\"screen_recording\":\(CGPreflightScreenCaptureAccess())}")
    NSApplication.shared.run()
    return 0
}
