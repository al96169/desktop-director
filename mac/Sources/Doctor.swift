// ddir macOS backend — `ddir doctor`: one command that answers "why is ddir not working?"
// Checks the things that actually break on macOS: TCC grants, signing identity, bundle path,
// state dir, tray/launch agent, prompt installation, and basic window/display sanity.

import AppKit
import Foundation

struct DoctorCheck {
    var name: String
    var ok: Bool
    var detail: String
    var hint: String
    var warn: Bool = false   // "works, but something optional is missing" — does not fail doctor
}

func runProcess(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "") }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// "Identifier=com.ddir.mac", "Authority=ddir-dev" out of `codesign -dv --verbose=2`.
func signingInfo(_ path: String) -> (identifier: String, authority: String) {
    let r = runProcess("/usr/bin/codesign", ["-dv", "--verbose=2", path])
    var id = "", auth = ""
    for line in r.out.split(separator: "\n") {
        let s = String(line)
        if s.hasPrefix("Identifier=") { id = String(s.dropFirst("Identifier=".count)) }
        if s.hasPrefix("Authority=") { auth = String(s.dropFirst("Authority=".count)) }
    }
    return (id, auth)
}

func trayRunning() -> Bool {
    let r = runProcess("/usr/bin/pgrep", ["-f", "Ddir.app/Contents/MacOS/Ddir tray"])
    return r.status == 0
}

func launchAgentLoaded() -> Bool {
    let r = runProcess("/bin/launchctl", ["print", "gui/\(getuid())/\(Autostart.label)"])
    return r.status == 0
}

func promptPath() -> String? {
    let candidates: [String?] = [
        Bundle.main.resourceURL?.appendingPathComponent("AGENTS.m0.md").path,
        (Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/AGENTS.m0.md").path),
        FileManager.default.currentDirectoryPath + "/prompts/AGENTS.m0.md",
    ]
    for c in candidates {
        if let p = c, FileManager.default.fileExists(atPath: p) { return p }
    }
    return nil
}

func cmdDoctor(_ args: [String]) -> Int32 {
    let bundlePath = Bundle.main.bundleURL.path
    let expected = "\(NSHomeDirectory())/Applications/Ddir.app"
    let sign = signingInfo(bundlePath)
    let stateWritable: Bool = {
        store.ensureHome()
        let probe = store.path("doctor.probe")
        do {
            try "ok".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true
        } catch { return false }
    }()
    let windows = win.listWindows()
    let displays = win.displays()
    let promptInstall = "\(NSHomeDirectory())/.dsh/AGENTS.md"
    let promptInstalled = (try? String(contentsOfFile: promptInstall, encoding: .utf8))?.contains("Desktop Director") ?? false
    let packedPrompt = promptPath()

    var checks: [DoctorCheck] = []
    checks.append(DoctorCheck(name: "accessibility", ok: win.axTrusted, detail: "\(win.axTrusted)",
        hint: "系统设置 → 隐私与安全性 → 辅助功能 勾选 Ddir"))
    checks.append(DoctorCheck(name: "screen_recording", ok: win.screenRecording, detail: "\(win.screenRecording)",
        hint: "只有 HUD 缩略图墙需要；系统设置 → 隐私与安全性 → 屏幕录制",
        warn: !win.screenRecording))
    checks.append(DoctorCheck(name: "bundle_path", ok: bundlePath == expected, detail: bundlePath,
        hint: "必须在 \(expected)；换路径会让 TCC 授权失效"))
    checks.append(DoctorCheck(name: "signed", ok: sign.identifier == "com.ddir.mac" && !sign.authority.isEmpty,
        detail: "\(sign.identifier) / \(sign.authority.isEmpty ? "unsigned" : sign.authority)",
        hint: "mac/build.sh 会用 ddir-dev 证书签名；ad-hoc 签名每次重建都会掉权限"))
    checks.append(DoctorCheck(name: "state_dir", ok: stateWritable, detail: store.home().path,
        hint: "检查 ~/.ddir 权限，或设置 DDIR_HOME"))
    checks.append(DoctorCheck(name: "mode_valid", ok: ["off", "semi", "auto"].contains(store.mode()),
        detail: store.mode(), hint: "ddir mode off|semi|auto"))
    checks.append(DoctorCheck(name: "displays", ok: !displays.isEmpty,
        detail: "\(displays.count) (managed \(displays.filter { $0.managed }.count))", hint: "没有显示器？"))
    checks.append(DoctorCheck(name: "windows", ok: !windows.isEmpty, detail: "\(windows.count)", hint: "AX 读到 0 个窗口通常还是权限问题"))
    checks.append(DoctorCheck(name: "tray", ok: trayRunning(), detail: trayRunning() ? "running" : "not running",
        hint: "ddir tray 或 ddir autostart on", warn: !trayRunning()))
    checks.append(DoctorCheck(name: "autostart", ok: true,
        detail: Autostart.on() ? (launchAgentLoaded() ? "enabled+loaded" : "plist only") : "disabled",
        hint: "ddir autostart on"))
    checks.append(DoctorCheck(name: "prompt", ok: promptInstalled, detail: promptInstalled ? promptInstall : "not installed",
        hint: "ddir prompt --install（写 ~/.dsh/AGENTS.md）", warn: !promptInstalled))
    checks.append(DoctorCheck(name: "prompt_resource", ok: packedPrompt != nil, detail: packedPrompt ?? "missing",
        hint: "重新 ./mac/build.sh（会把 prompts/AGENTS.m0.md 打进 bundle）"))

    let failed = checks.filter { !$0.ok && !$0.warn }.count
    let warned = checks.filter { !$0.ok && $0.warn }.count

    if hasFlag(args, "--text") {
        print("ddir doctor \(VERSION) (macos)")
        for c in checks {
            let tag = c.ok ? "ok  " : (c.warn ? "warn" : "FAIL")
            print("\(tag)  \(c.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(c.detail)")
            if !c.ok { print("      → \(c.hint)") }
        }
        print("---")
        if failed > 0 {
            print("\(failed) 项需要处理，\(warned) 项可选（warn）")
        } else {
            print("全绿：\(checks.count) 项检查通过" + (warned > 0 ? "（\(warned) 项可选未启用）" : ""))
        }
        return failed == 0 ? 0 : 1
    }

    let rows = checks.map { c -> String in
        let status = c.ok ? "ok" : (c.warn ? "warn" : "fail")
        return "{\"name\":\"\(es(c.name))\",\"status\":\"\(status)\",\"ok\":\(c.ok),\"detail\":\"\(es(c.detail))\",\"hint\":\"\(es(c.hint))\"}"
    }
    emit("{\"ok\":\(failed == 0),\"platform\":\"macos\",\"version\":\"\(VERSION)\",\"failed\":\(failed),"
         + "\"checks\":[\(rows.joined(separator: ","))]}")
    return failed == 0 ? 0 : 1
}

// MARK: - prompt (bundled AGENTS.m0.md)

func cmdPrompt(_ args: [String]) -> Int32 {
    guard let path = promptPath(), let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        emit("{\"ok\":false,\"error\":\"prompt_missing\",\"hint\":\"重新 ./mac/build.sh 把 prompts/AGENTS.m0.md 打进 bundle\"}")
        return 1
    }
    let dest = "\(NSHomeDirectory())/.dsh/AGENTS.md"
    if hasFlag(args, "--install") {
        try? FileManager.default.createDirectory(atPath: (dest as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        do {
            try text.write(toFile: dest, atomically: true, encoding: .utf8)
            store.log("prompt installed -> \(dest)")
            emit("{\"ok\":true,\"installed\":\"\(es(dest))\",\"bytes\":\(text.utf8.count)}")
            return 0
        } catch {
            emit("{\"ok\":false,\"error\":\"\(es(error.localizedDescription))\"}")
            return 1
        }
    }
    if hasFlag(args, "--check") {
        emit("{\"ok\":true,\"source\":\"\(es(path))\",\"target\":\"\(es(dest))\",\"installed\":\(FileManager.default.fileExists(atPath: dest)),\"bytes\":\(text.utf8.count)}")
        return 0
    }
    print(text)
    return 0
}
