// ddir macOS backend — `ddir web`: a chrome-less WKWebView window.
// Used by the stage for Mission Control / the typing IDE, so the show has no browser toolbar,
// no tabs and no AppleScript. One process per window; closing the window quits the process.

import AppKit
import WebKit

final class WebWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var web: WKWebView?

    func run(target: String, title: String?, width: CGFloat = 1280, height: CGFloat = 820) -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: config)
        self.web = web

        let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: width, height: height),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = title ?? "ddir web"
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = web
        w.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = w

        // target may carry a fragment ("/path/page.html#scroll=30"): split it, or the
        // file URL becomes ".../#scroll=30" and WKWebView loads a non-existent file (black window).
        var path = target
        var fragment: String?
        if let hash = target.firstIndex(of: "#") {
            path = String(target[..<hash])
            fragment = String(target[target.index(after: hash)...])
        }
        if let u = URL(string: path), u.scheme != nil {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
            c?.fragment = fragment
            if let final = c?.url { web.load(URLRequest(url: final)) }
        } else {
            let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            var c = URLComponents(url: file, resolvingAgainstBaseURL: false)
            c?.fragment = fragment
            let final = c?.url ?? file
            web.loadFileURL(final, allowingReadAccessTo: file.deletingLastPathComponent())
        }
        emit("{\"ok\":true,\"web\":\"\(es(target))\",\"title\":\"\(es(w.title))\"}")
        NSApplication.shared.run()
        return 0
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

func cmdWeb(_ args: [String]) -> Int32 {
    guard let target = positional(args).first else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"web <file|url> [--title NAME]\"}")
        return 1
    }
    return WebWindowController().run(target: target, title: argValue(args, "--title"))
}
