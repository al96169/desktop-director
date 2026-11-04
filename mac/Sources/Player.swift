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
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
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
        let view = PlayerView(player: player)
        w.contentView = view
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
