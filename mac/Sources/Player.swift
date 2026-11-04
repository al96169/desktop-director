// ddir macOS backend — `ddir play`: a tiny, self-contained media window.
// Used by `ddir stage` for the multimedia beat: no AppleScript, no TCC automation prompts,
// two of these can play at the same time and they tile like any other window.

import AVFoundation
import AppKit

/// A black, opaque surface with the AVPlayerLayer as a sublayer. Assigning the player layer
/// directly as the view's backing layer made the window composite translucent (desktop showed through).
final class PlayerView: NSView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    // AX resize (ddir move) changes the frame without necessarily running a layout pass
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        playerLayer.frame = bounds
    }
}

/// Audio files get a proper player face instead of a black window: title, source, level bars and
/// a timecode. Still one AVPlayer per window, so several tracks can play at the same time.
final class AudioPlayerView: NSView {
    let title: String
    let source: String
    private var bars: [CGFloat] = Array(repeating: 0.2, count: 28)
    private var elapsed: Double = 0
    private var total: Double = 0
    private var timer: Timer?

    init(title: String, source: String) {
        self.title = title
        self.source = source
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.12, alpha: 1).cgColor
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            for i in self.bars.indices { self.bars[i] = 0.15 + CGFloat.random(in: 0...0.85) }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(elapsed: Double, total: Double) {
        self.elapsed = elapsed
        self.total = total
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.12, alpha: 1).setFill()
        b.fill()
        let accent = NSColor(calibratedRed: 0.22, green: 0.96, blue: 1, alpha: 1)
        // header
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: accent.withAlphaComponent(0.9),
            .kern: 3,
        ]
        "AUDIO".draw(at: NSPoint(x: 24, y: b.height - 34), withAttributes: small)
        // title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ]
        title.draw(in: NSRect(x: 24, y: b.height * 0.55, width: b.width - 48, height: 40), withAttributes: titleAttrs)
        let srcAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(calibratedRed: 0.42, green: 0.54, blue: 0.66, alpha: 1),
        ]
        source.draw(in: NSRect(x: 24, y: b.height * 0.55 - 26, width: b.width - 48, height: 18), withAttributes: srcAttrs)
        // level bars
        let area = NSRect(x: 24, y: 82, width: b.width - 48, height: max(60, b.height * 0.32))
        let gap: CGFloat = 4
        let barW = (area.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        for (i, level) in bars.enumerated() {
            let h = max(6, area.height * level)
            let r = NSRect(x: area.minX + CGFloat(i) * (barW + gap), y: area.minY, width: barW, height: h)
            let color = i % 5 == 0 ? NSColor(calibratedRed: 1, green: 0.78, blue: 0.25, alpha: 0.9)
                                   : accent.withAlphaComponent(0.85)
            color.setFill()
            NSBezierPath(roundedRect: r, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
        // timecode
        let fmt = { (s: Double) -> String in
            let t = max(0, s.rounded())
            return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
        }
        let tc = "\(fmt(elapsed)) / \(fmt(total))"
        let tcAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72),
        ]
        tc.draw(at: NSPoint(x: 24, y: 46), withAttributes: tcAttrs)
        NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
        NSRect(x: 24, y: 34, width: b.width - 48, height: 2).fill()
        let progress = total > 0 ? min(1, elapsed / total) : 0
        accent.setFill()
        NSRect(x: 24, y: 34, width: (b.width - 48) * CGFloat(progress), height: 2).fill()
    }
}

final class PlayerController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var player: AVPlayer?

    func run(file: String, muted: Bool) -> Int32 {
        let url = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: url.path) else {
            emit("{\"ok\":false,\"error\":\"no_such_file\",\"file\":\"\(es(file))\"}")
            return 1
        }
        store.log("player: start \(url.lastPathComponent) pid=\(getpid())")
        NSApplication.shared.setActivationPolicy(.accessory)
        let asset = AVURLAsset(url: url)
        let hasVideo = !asset.tracks(withMediaType: .video).isEmpty
        let player = AVPlayer(url: url)
        player.volume = muted ? 0 : 0.6
        player.play()
        self.player = player

        let w = NSWindow(contentRect: NSRect(x: 120, y: 120, width: 960, height: 540),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = url.lastPathComponent
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        if hasVideo {
            w.contentView = PlayerView(player: player)
        } else {
            let audioView = AudioPlayerView(title: url.deletingPathExtension().lastPathComponent,
                                            source: url.lastPathComponent)
            w.contentView = audioView
            let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak audioView, weak player] _ in
                guard let player, let audioView else { return }
                audioView.update(elapsed: player.currentTime().seconds,
                                 total: player.currentItem?.duration.seconds ?? 0)
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
        store.log("player: window shown \(url.lastPathComponent) frame=\(NSStringFromRect(w.frame))")

        // loop the clip so the stage never shows a frozen window mid-demo
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        emit("{\"ok\":true,\"playing\":\"\(es(url.lastPathComponent))\",\"muted\":\(muted)}")
        NSApplication.shared.run()
        return 0
    }

    func windowWillClose(_ notification: Notification) {
        player?.pause()
        NSApp.terminate(nil)
    }
}

func cmdPlay(_ args: [String]) -> Int32 {
    guard let file = positional(args).first else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"play <file> [--muted]\"}")
        return 1
    }
    return PlayerController().run(file: file, muted: hasFlag(args, "--muted"))
}
