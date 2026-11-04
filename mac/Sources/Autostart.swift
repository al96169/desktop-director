// ddir macOS backend — login item (LaunchAgent) support.
// Windows uses HKCU\...\Run; the macOS equivalent is a per-user LaunchAgent that runs
// `Ddir tray` at login. Written by hand (no launchctl plist API) so it is inspectable.

import Foundation

enum Autostart {
    static let label = "com.ddir.mac.tray"

    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
    }

    static var binaryPath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? "\(NSHomeDirectory())/Applications/Ddir.app/Contents/MacOS/Ddir"
    }

    static func on() -> Bool { FileManager.default.fileExists(atPath: plistPath) }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func set(_ enable: Bool) -> Bool {
        let dir = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if enable {
            Store.shared.ensureHome()
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>\(label)</string>
              <key>ProgramArguments</key>
              <array><string>\(xmlEscape(binaryPath))</string><string>tray</string></array>
              <key>RunAtLoad</key><true/>
              <key>ProcessType</key><string>Interactive</string>
              <key>StandardOutPath</key><string>\(xmlEscape(Store.shared.path("tray.out")))</string>
              <key>StandardErrorPath</key><string>\(xmlEscape(Store.shared.path("tray.err")))</string>
            </dict>
            </plist>
            """
            try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
            // bootout first so a re-enable actually reloads the new plist
            run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
            Store.shared.log("autostart on (\(label) -> \(binaryPath) tray)")
        } else {
            run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            try? FileManager.default.removeItem(atPath: plistPath)
            Store.shared.log("autostart off (\(label))")
        }
        return on()
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
