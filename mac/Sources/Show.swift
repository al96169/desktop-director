// ddir macOS backend — `ddir stage`: a scripted, fully ddir-driven desktop performance.
//
//   ddir stage assets [--force]     (re)generate the demo assets in ~/.ddir/show
//   ddir stage run [--fast] [--keep] [--no-audio]
//   ddir stage rollback             close what it opened, restore layout/mode, quit what it launched
//   ddir stage status
//
// The stage is a normal ddir client: it opens windows, claims leases, tiles them, shows the HUD
// and releases everything. Input is not injected — the "typing" and "scrolling" beats are
// choreographed pages (see ShowAssets), which keeps the show reproducible.
//
// Every run writes ~/.ddir/show/journal.json first, so `ddir stage rollback` can clean up even
// after an interrupted run, and the same show can be played again and again.

import AppKit
import Foundation

private let stageDir = ShowAssets.dir()

struct StageJournal: Codable {
    var startedAt: Double
    var modeBefore: String
    var presentationBefore: String?
    var autoCloseBefore: String?
    var quickTimeWasRunning: Bool
    var opened: [Opened]
    var hiddenApps: [Hidden]?
    var frontBundleBefore: String?
    var audioPid: Int32

    struct Hidden: Codable {
        var pid: Int32
        var name: String
    }

    struct Opened: Codable {
        var ref: String
        var app: String
        var bundle: String
        var title: String
    }
}

private func journalPath() -> String { stageDir.appendingPathComponent("journal.json").path }

private func saveJournal(_ j: StageJournal) {
    if let data = try? JSONEncoder().encode(j) {
        try? data.write(to: URL(fileURLWithPath: journalPath()))
    }
}

private func loadJournal() -> StageJournal? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: journalPath())) else { return nil }
    return try? JSONDecoder().decode(StageJournal.self, from: data)
}

private func runSelf(_ args: [String]) -> Int32 {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

private func spawnSelf(_ args: [String]) -> Process? {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    return p
}

// MARK: - window helpers

private func refs(forApp app: String) -> Set<String> {
    Set(win.listWindows().filter { sameApp($0.app, app) }.map { $0.ref })
}

/// NSWorkspace's app snapshot only refreshes on the main run loop; this CLI has no NSApp,
/// so pump it explicitly before enumerating (otherwise freshly launched windows are invisible).
private func pump(_ seconds: Double = 0.05) {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(seconds))
}

@discardableResult
private func waitForWindow(app: String, title: String, excluding: Set<String>,
                           timeout: Double = 12) -> WinInfo? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        pump()
        win.invalidateCG()
        if let w = win.listWindows().first(where: {
            sameApp($0.app, app) && !excluding.contains($0.ref) && $0.title.localizedCaseInsensitiveContains(title)
        }) {
            // prefer a CGWindowNumber ref: index fallbacks can be remapped by later calls
            if w.cgwin != nil || Date().timeIntervalSince(deadline) > -timeout + 2.0 { return w }
        }
        usleep(150_000)
    }
    return nil
}

@discardableResult
private func openWeb(_ file: String, title: String, hash: String) -> Process? {
    spawnSelf(["web", "\(ShowAssets.url(file).path)#\(hash)", "--title", title])
}

/// Clear the stage: hide every other regular app so the show owns the screen.
/// Everything hidden here is restored by `ddir stage rollback`.
private func hideDistractors(keep: Set<String>) -> [StageJournal.Hidden] {
    var out: [StageJournal.Hidden] = []
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
        let name = app.executableURL?.lastPathComponent ?? ""
        if keep.contains(name) || app.processIdentifier == getpid() || app.isHidden { continue }
        let hasWindow = !axWindowsForPid(app.processIdentifier).isEmpty
        if !hasWindow && name != "Finder" { continue }
        if win.hideApp(app.processIdentifier) {
            out.append(StageJournal.Hidden(pid: app.processIdentifier, name: name))
        }
    }
    return out
}

private func axWindowsForPid(_ pid: pid_t) -> [AXUIElement] {
    win.axWindows(pid).filter { el in
        win.str(el, kAXRoleAttribute as String) == "AXWindow"
            && !win.str(el, kAXTitleAttribute as String).trimmingCharacters(in: .whitespaces).isEmpty
    }
}

private func quickTimeApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        ($0.executableURL?.lastPathComponent ?? "") == "QuickTime Player" || ($0.bundleIdentifier ?? "") == "com.apple.QTKit"
    }
}

// MARK: - rollback

private func stageRollback(quiet: Bool = false) -> (closed: Int, released: Int) {
    guard let j = loadJournal() else {
        if !quiet { emit("{\"ok\":true,\"rollback\":\"nothing_to_do\"}") }
        return (0, 0)
    }
    if j.audioPid > 0 { kill(j.audioPid, SIGTERM) }

    // 1. release every lease (restores geometry of anything the show moved)
    let (released, _) = releaseAll(force: true)

    // 2. close the windows the show opened.
    // Match on (app, title) first: CGWindowNumber-based refs can shift between calls
    // (and an index-style ref is ambiguous), titles are unique in the show.
    var closed = 0
    var missed: [String] = []
    for o in j.opened {
        pump()
        win.invalidateCG()
        let ws = win.listWindows()
        if let w = ws.first(where: { sameApp($0.app, o.app) && $0.title == o.title }) {
            let ok = win.closeWindow(pid: w.pid, title: o.title)
            store.log("stage: rollback close \(o.title) ref=\(o.ref) now=\(w.ref) pid=\(w.pid) ok=\(ok)")
            if ok { closed += 1 } else { missed.append(o.title) }
        } else if win.isWindow(o.ref) {
            let ok = win.closeWindow(o.ref)
            store.log("stage: rollback close-by-ref \(o.title) ref=\(o.ref) ok=\(ok)")
            if ok { closed += 1 } else { missed.append(o.title) }
        } else {
            store.log("stage: rollback skip \(o.title) ref=\(o.ref) (already gone)")
        }
        usleep(200_000)
    }
    if !missed.isEmpty { store.log("stage: rollback could not close: \(missed)") }

    // 3b. restore the apps the stage hid, and the frontmost app the user had
    for h in j.hiddenApps ?? [] {
        if NSRunningApplication(processIdentifier: h.pid) != nil { _ = win.showApp(h.pid) }
    }
    if let b = j.frontBundleBefore,
       let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == b }) {
        app.activate()
    }

    // 4. restore settings
    _ = store.setMode(j.modeBefore)
    if let p = j.presentationBefore { _ = store.configSet("presentation", p) }
    if let a = j.autoCloseBefore { _ = store.configSet("auto_close", a) }
    try? FileManager.default.removeItem(atPath: journalPath())
    store.log("stage: rollback closed=\(closed) released=\(released) mode=\(j.modeBefore)")
    if !quiet {
        emit("{\"ok\":true,\"rolled_back\":true,\"closed\":\(closed),\"released\":\(released),\"mode\":\"\(es(j.modeBefore))\"}")
    }
    return (closed, released)
}

// MARK: - run

private struct Pace {
    var boot: Double = 3.0
    var tiling: Double = 1.6
    var typing: Double = 17.0
    var media: Double = 7.0
    var wall: Double = 9.0
    var finale: Double = 6.0
    var fast = false

    func scaled(_ s: Double) -> Double { fast ? min(s, 0.4) : s }
    func sleep(_ s: Double) { usleep(useconds_t(max(0, s) * 1_000_000)) }
}

private func stageRun(_ args: [String]) -> Int32 {
    let pace = Pace(fast: hasFlag(args, "--fast"))
    let audio = !hasFlag(args, "--no-audio")
    let keep = hasFlag(args, "--keep")

    do {
        _ = try ShowAssets.ensure()
    } catch {
        emit("{\"ok\":false,\"error\":\"assets: \(es(error.localizedDescription))\"}")
        return 1
    }

    // clean up leftovers from a previous run first, so the show always starts from a clean stage
    if loadJournal() != nil { _ = stageRollback(quiet: true) }

    var journal = StageJournal(
        startedAt: Date().timeIntervalSince1970,
        modeBefore: store.mode(),
        presentationBefore: store.configGet("presentation"),
        autoCloseBefore: store.configGet("auto_close"),
        quickTimeWasRunning: !quickTimeApps().isEmpty,
        opened: [],
        audioPid: 0
    )
    saveJournal(journal)

    _ = store.setMode("semi")
    _ = store.configSet("auto_close", "off")
    _ = store.configSet("presentation", "instant")

    journal.frontBundleBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    journal.hiddenApps = hideDistractors(keep: ["Safari", "Ddir"])
    saveJournal(journal)
    usleep(400_000)

    var beats: [(String, Double)] = []
    let t0 = Date()
    func beat(_ name: String) {
        beats.append((name, Date().timeIntervalSince(t0)))
        store.log("stage: beat \(name) at \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
    }

    // ambient score: downloaded CC0 track (looped) or the generated pad, no window either way
    if audio, let score = ShowMedia.score() {
        let p = Process()
        p.executableURL = ShowMedia.scoreLoopScript()
        p.arguments = [score.path, "0.30"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            journal.audioPid = p.processIdentifier
            saveJournal(journal)
        }
    }

    // ---- 1. mission control ------------------------------------------------
    let webBefore = Set(win.listWindows().filter { sameApp($0.app, "Ddir") }.map { $0.ref })
    _ = openWeb("index.html", title: "Mission Control", hash: "scroll=30")
    guard let dash = waitForWindow(app: "Ddir", title: "Mission Control", excluding: webBefore) else {
        emit("{\"ok\":false,\"error\":\"dashboard_not_found\"}")
        _ = stageRollback(quiet: true)
        return 1
    }
    journal.opened.append(.init(ref: dash.ref, app: dash.app, bundle: win.bundleId(dash.pid), title: dash.title))
    saveJournal(journal)
    pace.sleep(pace.scaled(pace.boot))
    beat("mission-control")

    _ = runSelf(["claim", "--needs", "Mission Control", "--force"])
    _ = spawnSelf(["hud", "--seconds", "3"])?.waitUntilExit()
    pace.sleep(pace.scaled(pace.tiling))

    // ---- 2. the agent writes code -----------------------------------------
    let webBefore2 = Set(win.listWindows().filter { sameApp($0.app, "Ddir") }.map { $0.ref })
    _ = openWeb("editor.html", title: "code.swift", hash: "type=1.5&speed=8")
    guard let editor = waitForWindow(app: "Ddir", title: "code.swift", excluding: webBefore2) else {
        emit("{\"ok\":false,\"error\":\"editor_not_found\"}")
        _ = stageRollback(quiet: true)
        return 1
    }
    journal.opened.append(.init(ref: editor.ref, app: editor.app, bundle: win.bundleId(editor.pid), title: editor.title))
    saveJournal(journal)
    beat("editor-open")
    _ = runSelf(["claim", "--needs", "code.swift,Mission Control", "--force"])
    _ = spawnSelf(["hud", "--seconds", "3"])?.waitUntilExit()
    pace.sleep(pace.scaled(pace.typing))
    beat("code-typed")

    // ---- 3. media: two clips join the triptych ----------------------------
    let playerBefore = Set(win.listWindows().filter { sameApp($0.app, "Ddir") }.map { $0.ref })
    let media = ShowMedia.clips()
    let clips = media.isEmpty ? [ShowAssets.url("clip1.mov"), ShowAssets.url("clip2.mov")] : media
    for clipURL in clips {
        let clip = clipURL.lastPathComponent
        let p = spawnSelf(["play", clipURL.path])
        store.log("stage: spawned player for \(clip) pid=\(p?.processIdentifier ?? -1)")
        if let w = waitForWindow(app: "Ddir", title: clip, excluding: playerBefore) {
            journal.opened.append(.init(ref: w.ref, app: w.app, bundle: win.bundleId(w.pid), title: w.title))
            saveJournal(journal)
        } else {
            let seen = win.listWindows().filter { $0.app == "Ddir" }.map { "\($0.ref):\($0.title)" }
            let instances = NSWorkspace.shared.runningApplications
                .filter { ($0.bundleIdentifier ?? "") == "com.ddir.mac" }
                .map { "pid=\($0.processIdentifier) hidden=\($0.isHidden) policy=\($0.activationPolicy.rawValue) windows=\(win.axWindows($0.processIdentifier).count)" }
            store.log("stage: player window for \(clip) NOT found; Ddir windows=\(seen); instances=\(instances)")
        }
        _ = p
    }
    beat("media-open")
    pace.sleep(pace.scaled(1.2))

    // The dashboard leaves the stage: release the 2 leases and close it, then the editor plus
    // the two signals take the whole stage as a triptych (quota is 3 leases per agent).
    _ = releaseAll(force: true)
    if let d = win.listWindows().first(where: { sameApp($0.app, "Ddir") && $0.title == "Mission Control" }) {
        _ = win.closeWindow(pid: d.pid, title: d.title)
    }
    usleep(300_000)
    let clipNames = clips.map { $0.lastPathComponent }.joined(separator: ",")
    _ = runSelf(["claim", "--needs", "\(clipNames),code.swift", "--force"])
    _ = spawnSelf(["hud", "--seconds", "3"])?.waitUntilExit()
    pace.sleep(pace.scaled(pace.media))
    beat("triptych")

    // ---- 4. HUD wall over the playing windows -----------------------------
    _ = spawnSelf(["hud", "--wall", "--seconds", String(Int(pace.scaled(pace.wall)))])?.waitUntilExit()
    beat("hud-wall")

    pace.sleep(pace.scaled(pace.finale))
    beat("finale")

    if keep {
        emit("{\"ok\":true,\"kept\":true,\"beats\":\(beats.count),\"seconds\":\(Int(Date().timeIntervalSince(t0)))}")
        return 0
    }
    let rb = stageRollback(quiet: true)
    beat("rollback")

    let rows = beats.map { "{\"beat\":\"\(es($0.0))\",\"at\":\(String(format: "%.1f", $0.1))}" }
    store.log("stage: finished closed=\(rb.closed) released=\(rb.released)")
    emit("{\"ok\":true,\"seconds\":\(Int(Date().timeIntervalSince(t0))),\"beats\":[\(rows.joined(separator: ","))],"
         + "\"closed\":\(rb.closed),\"released\":\(rb.released)}")
    return 0
}

// MARK: - command

func cmdStage(_ args: [String]) -> Int32 {
    let sub = args.first ?? "run"
    switch sub {
    case "assets":
        do {
            let inv = try ShowAssets.ensure(force: hasFlag(args, "--force"))
            let rows = inv.map { "{\"name\":\"\(es($0.name))\",\"path\":\"\(es($0.path))\",\"bytes\":\($0.bytes)}" }
            emit("{\"ok\":true,\"dir\":\"\(es(stageDir.path))\",\"assets\":[\(rows.joined(separator: ","))]}")
        } catch {
            emit("{\"ok\":false,\"error\":\"\(es(error.localizedDescription))\"}")
            return 1
        }
    case "fetch":
        do {
            let got = try ShowMedia.fetch(force: hasFlag(args, "--force"))
            let rows = got.map { "{\"file\":\"\(es($0.file))\",\"title\":\"\(es($0.title))\",\"license\":\"\(es($0.license))\"}" }
            emit("{\"ok\":true,\"dir\":\"\(es(ShowMedia.dir().path))\",\"clips\":\(ShowMedia.clips().count),\"sources\":[\(rows.joined(separator: ","))]}")
        } catch {
            emit("{\"ok\":false,\"error\":\"\(es(error.localizedDescription))\",\"hint\":\"需要网络；失败时 stage 会退回本机生成素材\"}")
            return 1
        }
    case "rollback":
        _ = stageRollback()
    case "status":
        let files = (try? FileManager.default.contentsOfDirectory(atPath: stageDir.path)) ?? []
        let j = loadJournal()
        emit("{\"ok\":true,\"dir\":\"\(es(stageDir.path))\",\"files\":\(files.count),"
             + "\"journal\":\(j == nil ? "null" : "{\"opened\":\(j!.opened.count),\"started\":\(j!.startedAt)}"),"
             + "\"mode\":\"\(es(store.mode()))\"}")
    case "run":
        return stageRun(args)
    default:
        emit("{\"ok\":false,\"error\":\"unknown_stage_subcmd\",\"hint\":\"fetch|assets|run|rollback|status\"}")
    }
    return 0
}
