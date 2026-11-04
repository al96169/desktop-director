// ddir macOS backend — HUD overlay: dim the managed display and show a thumbnail wall
// of the windows this agent holds a lease on ("科幻感" layer, stage 1 of the product idea).
//
//   ddir hud [--seconds N]   show the overlay for N seconds (default 6), never steals focus
//   ddir hud --check         print what would be shown (JSON) and exit
//
// Thumbnails need Screen Recording. macOS 15 removed CGWindowListCreateImage, so the capture
// path is ScreenCaptureKit (SCScreenshotManager, macOS 14+). Without the permission the HUD
// still works: it falls back to app icons + titles, and says so.

import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

final class HudTile {
    var ref: String
    var app: String
    var title: String
    var rect: [Int]
    var icon: NSImage?
    var thumb: NSImage?
    var agent: String = ""
    var live: Bool = false

    init(ref: String, app: String, title: String, rect: [Int]) {
        self.ref = ref
        self.app = app
        self.title = title
        self.rect = rect
    }
}

final class HudView: NSView {
    var mode: String = "semi"
    var tiles: [HudTile] = []
    var note: String = ""
    var onLayout: (([Int], [Int]) -> Void)?   // (tile index) -> nothing; kept for tests

    override var isFlipped: Bool { false }

    private func tileRects(in bounds: NSRect) -> [NSRect] {
        let n = max(tiles.count, 1)
        let pad: CGFloat = 28
        let top: CGFloat = 64
        let avail = NSRect(x: bounds.minX + pad, y: bounds.minY + pad,
                           width: bounds.width - 2 * pad, height: bounds.height - 2 * pad - top)
        let cols = n <= 1 ? 1 : (n == 2 ? 2 : (n <= 4 ? 2 : 3))
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

        // header
        let head = "DDIR  ·  \(mode)  ·  \(tiles.count) 窗口"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
        head.draw(at: NSPoint(x: 30, y: bounds.height - 48), withAttributes: attrs)
        if !note.isEmpty {
            let nattrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            ]
            note.draw(at: NSPoint(x: 32, y: bounds.height - 68), withAttributes: nattrs)
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
                drawAspectFit(thumb, in: imageRect)
            } else if let icon = tile.icon {
                let s = min(min(imageRect.width, imageRect.height), 128)
                let ir = NSRect(x: imageRect.midX - s / 2, y: imageRect.midY - s / 2, width: s, height: s)
                icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 0.9)
            }

            var name = "\(tile.app)  ·  \(tile.title)"
            if !tile.agent.isEmpty, tile.agent != win.agentId() { name += "  ·  \(tile.agent)" }
            let title = name.count > 52 ? String(name.prefix(52)) + "…" : name
            let tattrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
            title.draw(at: NSPoint(x: inner.minX + 2, y: r.minY + 20), withAttributes: tattrs)

            let geo = "\(tile.rect[0]),\(tile.rect[1])  \(tile.rect[2])×\(tile.rect[3])   \(tile.ref)"
            let gattrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            ]
            geo.draw(at: NSPoint(x: inner.minX + 2, y: r.minY + 6), withAttributes: gattrs)
        }
    }

    private func drawAspectFit(_ img: NSImage, in rect: NSRect) {
        let size = img.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        let r = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

final class HudController {
    static let shared = HudController()

    private var windows: [NSWindow] = []
    private var views: [HudView] = []
    private var timer: Timer?
    private var deadline: Date = .distantFuture
    private var thumbs: [String: NSImage] = [:]
    private var terminateWhenDone = false

    /// Build the tile list from live leases (mine first, then other agents').
    func tiles() -> [HudTile] {
        let now = nowUnix()
        let me = win.agentId()
        let live = store.leases().filter { $0.expires > now }
        let mine = live.filter { $0.agent == me }
        let others = live.filter { $0.agent != me }
        let wins = win.listWindows()
        var out: [HudTile] = []
        for l in mine + others {
            guard let w = wins.first(where: { $0.ref == l.window }) else { continue }
            let t = HudTile(ref: w.ref, app: w.app, title: w.title, rect: w.win)
            t.icon = NSWorkspace.shared.icon(forFile: win.bundlePath(w.pid))
            t.agent = l.agent
            t.live = true
            out.append(t)
        }
        if out.isEmpty {
            // nothing leased yet: show what is on the managed display so the HUD is never blank
            let managed = win.managedDisplays().map { $0.uid }
            for w in wins where managed.contains(w.display) && !w.minimized {
                let t = HudTile(ref: w.ref, app: w.app, title: w.title, rect: w.win)
                t.icon = NSWorkspace.shared.icon(forFile: win.bundlePath(w.pid))
                out.append(t)
            }
        }
        return Array(out.prefix(6))
    }

    /// Create the overlay windows and start the refresh/close timer. Does NOT enter a run loop,
    /// so it is safe to call from the tray (which already owns one). `terminateWhenDone` makes
    /// the blocking CLI variant quit the process when the overlay closes.
    @discardableResult
    func present(seconds: Double = 6, terminateWhenDone: Bool = false) -> Int {
        self.terminateWhenDone = terminateWhenDone
        let tiles = tiles()
        let notes = CGPreflightScreenCaptureAccess()
            ? "ScreenCaptureKit 缩略图 · \(VERSION)"
            : "仅应用图标：需要「屏幕录制」授权才能出缩略图 · \(VERSION)"
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        for screen in NSScreen.screens {
            let uid = displayUID(screen)
            let managed = win.managedDisplays().contains { $0.uid == uid }
            if !managed { continue }
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: screen)
            w.level = .floating
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = HudView(frame: screen.frame)
            v.mode = store.mode()
            v.tiles = tiles
            v.note = notes
            w.contentView = v
            windows.append(w)
            views.append(v)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                w.animator().alphaValue = 1
            }
        }
        store.log("hud: showing \(tiles.count) tiles on \(windows.count) display(s), screen_recording=\(CGPreflightScreenCaptureAccess())")
        loadThumbnails()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        deadline = Date().addingTimeInterval(seconds)
        return tiles.count
    }

    private func displayUID(_ screen: NSScreen) -> String {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let id = CGDirectDisplayID(num?.uint32Value ?? 0)
        return id == 0 ? "screen-0" : "cg-\(id)"
    }

    private func tick() {
        // keep the wall in sync with claims/releases while the overlay is up.
        // Thumbnails live in `thumbs` (keyed by ref) so a refresh never wipes them.
        let fresh = tiles()
        for t in fresh where t.thumb == nil {
            t.thumb = thumbs[t.ref]
        }
        for v in views {
            v.tiles = fresh
            v.mode = store.mode()
            v.needsDisplay = true
        }
        if Date() >= deadline {
            timer?.invalidate()
            timer = nil
            for w in windows {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    w.animator().alphaValue = 0
                }
            }
            let deadlineCopy = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard Date() >= deadlineCopy else { return }
                for w in self.windows { w.orderOut(nil) }
                self.windows.removeAll()
                self.views.removeAll()
                self.thumbs.removeAll()
                if self.terminateWhenDone { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: - ScreenCaptureKit thumbnails (macOS 14+)

    private func loadThumbnails() {
        guard CGPreflightScreenCaptureAccess() else { return }
        guard #available(macOS 14.0, *) else { return }
        let snapshot = views.flatMap { $0.tiles }.filter { $0.thumb == nil && thumbs[$0.ref] == nil }
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
                    tile.thumb = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    self.thumbs[tile.ref] = tile.thumb
                }
            }
            for v in self.views {
                for t in v.tiles where t.thumb == nil { t.thumb = self.thumbs[t.ref] }
                v.needsDisplay = true
            }
            store.log("hud: thumbnails captured \(self.thumbs.count)/\(snapshot.count) (this round)")
        }
    }

    func checkJSON() -> String {
        let t = tiles()
        let bounds = t.map { "\"\(es($0.ref))\"" }.joined(separator: ",")
        return "{\"ok\":true,\"platform\":\"macos\",\"mode\":\"\(es(store.mode()))\",\"tiles\":\(t.count),"
            + "\"screen_recording\":\(CGPreflightScreenCaptureAccess()),\"accessibility\":\(win.axTrusted),"
            + "\"displays\":\(win.managedDisplays().count),\"windows\":[\(bounds)]}"
    }
}

func cmdHud(_ args: [String]) -> Int32 {
    if hasFlag(args, "--check") {
        emit(HudController.shared.checkJSON())
        return 0
    }
    let secs = Double(argValue(args, "--seconds") ?? "") ?? 6
    // present() returns immediately; emit the JSON first, then pump the loop until it closes
    let n = HudController.shared.present(seconds: secs, terminateWhenDone: true)
    emit("{\"ok\":true,\"tiles\":\(n),\"seconds\":\(secs),\"screen_recording\":\(CGPreflightScreenCaptureAccess())}")
    NSApplication.shared.run()
    return 0
}
