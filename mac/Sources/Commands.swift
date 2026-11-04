// ddir macOS backend — command implementations.
// Each command prints exactly one line of JSON (except list --text / log / board / selftest / help,
// which are human text like the Windows build). Field names and error codes match src/main.rs.

import AppKit
import Foundation

let store = Store.shared
let win = MacWin.shared

// MARK: - shared

func sameApp(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

/// Every geometry/lifecycle write needs the accessibility grant (D24/D25).
func axGuard() -> Bool {
    if win.axTrusted { return true }
    emit("{\"ok\":false,\"error\":\"permission_required\",\"hint\":\"系统设置 → 隐私与安全性 → 辅助功能 勾选 Ddir（证书/路径变了要重新勾）\"}")
    return false
}

func modeGuard() -> Bool {
    if store.mode() == "off" {
        emit("{\"ok\":false,\"error\":\"mode_off\",\"hint\":\"ddir mode semi|auto 再操作\"}")
        return false
    }
    return true
}

func activityTuple() -> (idle: Int, moved: Int, fgChanged: Bool, active: Bool) {
    win.activity()
}

/// Equal-width columns so windows sit side by side instead of stacking (D30).
func layoutFor(_ count: Int, _ work: [Int]) -> [[Int]] {
    let n = max(count, 1)
    let (wx, wy, ww, wh) = (work[0], work[1], work[2], work[3])
    if n == 1 { return [[wx + GAP, wy + GAP, ww - 2 * GAP, wh - 2 * GAP]] }
    let col = (ww - (n + 1) * GAP) / n
    return (0..<n).map { i in
        [wx + GAP + i * (col + GAP), wy + GAP, col, wh - 2 * GAP]
    }
}

func parseNeeds(_ spec: String) -> [String] {
    if spec.trimmingCharacters(in: .whitespaces).isEmpty { return [""] }
    return spec.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map { String($0.split(separator: ":").first ?? "").trimmingCharacters(in: .whitespaces) }
        .prefix(3)
        .map { $0 }
}

func matches(_ w: WinInfo, _ name: String) -> Bool {
    if name.isEmpty { return true }
    let n = name.lowercased()
    return w.app.lowercased().contains(n) || w.title.lowercased().contains(n) || w.subrole.lowercased().contains(n)
}

func quotaExceeded() -> Int32 {
    emit("{\"ok\":false,\"error\":\"quota_exceeded\",\"hint\":\"单 Agent 最多 3 个窗口；先 release 不用的\"}")
    return 0
}

func capsJSON() -> String {
    let ax = win.axTrusted
    let hide: String = ax ? "\"app\"" : "false"
    return "{\"window_move\":\(ax),\"window_hide\":\(hide),\"window_close\":\(ax),\"focus_control\":\(ax),"
        + "\"display_enumerate\":true,\"thumbnail\":\(win.screenRecording),\"idle_signal\":\"input\","
        + "\"accessibility\":\(ax),\"screen_recording\":\(win.screenRecording)}"
}

func displayJSON(_ d: Display) -> String {
    "{\"uid\":\"\(es(d.uid))\",\"gdi\":\"\(es(d.gdi))\",\"label\":\"\(es(d.label))\",\"primary\":\(d.primary),"
        + "\"managed\":\(d.managed),\"monitor\":\(rectJSON(d.monitor)),\"work\":\(rectJSON(d.work)),\"scale\":\(d.scale)}"
}

func displayListJSON(_ ds: [Display]) -> String {
    "[" + ds.map(displayJSON).joined(separator: ",") + "]"
}

func windowJSON(_ w: WinInfo) -> String {
    "{\"hwnd\":\"\(es(w.ref))\",\"app\":\"\(es(w.app))\",\"class\":\"\(es(w.subrole))\",\"title\":\"\(es(w.title))\","
        + "\"display\":\"\(es(w.display))\",\"rect\":\(rectJSON(w.frame)),\"win\":\(rectJSON(w.win)),\"dpi\":\(w.dpi),"
        + "\"scale\":\(w.scale),\"maximized\":\(w.maximized),\"minimized\":\(w.minimized),\"foreground\":\(w.foreground),"
        + "\"hidden\":\(w.hidden),\"pid\":\(w.pid)}"
}

// MARK: - mode

func cmdMode(_ args: [String]) -> Int32 {
    if let m = positional(args).first {
        if let err = store.setMode(m) {
            emit("{\"ok\":false,\"error\":\"\(es(err))\"}")
            return 1
        }
        store.audit("mode", m)
        store.log("mode -> \(m)")
    }
    let (idle, moved, fg, active) = activityTuple()
    emit("{\"ok\":true,\"mode\":\"\(store.mode())\",\"agent\":\"\(es(win.agentId()))\","
         + "\"input_age_s\":\(idle),\"user_active\":\(active),\"cursor_moved_px\":\(moved),"
         + "\"foreground_changed\":\(fg),\"signal\":\"cursor+foreground\"}")
    return 0
}

// MARK: - displays

/// Resolve the config value ("all" / "all_except_primary" / "none" / uid list) into concrete uids.
func concreteManagedUIDs() -> [String] {
    let ds = win.displays()
    let cfg = store.configGet("managed_displays") ?? "all_except_primary"
    if cfg == "none" { return [] }
    if cfg == "all" { return ds.map { $0.uid } }
    if cfg == "all_except_primary" { return ds.filter { $0.managed }.map { $0.uid } }
    return cfg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

@discardableResult
func applyManagedUIDs(_ uids: [String]) -> String {
    let value = uids.isEmpty ? "none" : uids.joined(separator: ",")
    _ = store.configSet("managed_displays", value)
    store.log("managed_displays -> \(value)")
    return value
}

func cmdDisplays(_ args: [String]) -> Int32 {
    if let target = argValue(args, "--manage") {
        let on = !hasFlag(args, "--off")
        let ds = win.displays()
        guard let hit = ds.first(where: { $0.uid == target || $0.gdi == target || (target == "primary" && $0.primary) }) else {
            emit("{\"ok\":false,\"error\":\"no_such_display\",\"hint\":\"看到 ddir displays 里的 uid/gdi\"}")
            return 0
        }
        var list = concreteManagedUIDs()
        if on {
            if !list.contains(hit.uid) { list.append(hit.uid) }
        } else {
            list.removeAll { $0 == hit.uid || $0 == hit.gdi }
        }
        let value = applyManagedUIDs(list)
        emit("{\"ok\":true,\"managed_displays\":\"\(es(value))\"}")
        return 0
    }
    let ds = win.displays()
    let managed = ds.filter { $0.managed }
    let user = ds.filter { !$0.managed }
    emit("{\"ok\":true,\"platform\":\"macos\",\"managed\":\(displayListJSON(managed)),\"user\":\(displayListJSON(user))}")
    return 0
}

// MARK: - list / status

func cmdList(_ args: [String]) -> Int32 {
    let ws = win.listWindows()
    if hasFlag(args, "--text") {
        for w in ws {
            print("\(w.ref)\t\(w.app)\t\(w.display)\t\(formatRect(w.frame))\t\(w.title)")
        }
        return 0
    }
    emit("{\"ok\":true,\"count\":\(ws.count),\"windows\":[\(ws.map(windowJSON).joined(separator: ","))]}")
    return 0
}

func focusHolder() -> (String, UInt64)? {
    guard let txt = try? String(contentsOfFile: store.path("focus.tsv"), encoding: .utf8) else { return nil }
    let f = txt.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
    if f.count < 2 { return nil }
    return (f[0], UInt64(f[1]) ?? 0)
}

func cmdStatus() -> Int32 {
    let me = win.agentId()
    let now = nowUnix()
    let all = store.leases()
    let live = all.filter { $0.expires > now }
    let mine = live.filter { $0.agent == me }
    let others = live.count - mine.count
    let apps = store.apps()
    let owns = apps.filter { $0.owner == me && $0.since + $0.ttl > now }.map { "\"\(es($0.app))\"" }
    let winsJSON = mine.map {
        "{\"window\":\"\(es($0.window))\",\"action\":\"\(es($0.action))\",\"expires\":\($0.expires)}"
    }
    let (idle, moved, fg, active) = activityTuple()
    let holder = focusHolder().map { $0.0 } ?? "none"
    emit("{\"ok\":true,\"platform\":\"macos\",\"mode\":\"\(store.mode())\",\"you\":\"\(es(me))\","
         + "\"leases\":\(mine.count),\"lease\":\"\(es(mine.first?.lease ?? ""))\","
         + "\"windows\":[\(winsJSON.joined(separator: ","))],\"held_by_others\":\(others),"
         + "\"owns\":[\(owns.joined(separator: ","))],\"focus_holder\":\"\(es(holder))\","
         + "\"input_age_s\":\(idle),\"user_active\":\(active),\"cursor_moved_px\":\(moved),"
         + "\"foreground_changed\":\(fg),\"version\":\"\(VERSION)\",\"caps\":\(capsJSON())}")
    return 0
}

// MARK: - claim / plan

struct PlanItem {
    var win: WinInfo
    var rect: [Int]
    var lease: Store.Lease?
    var from: [Int]
}

func cmdClaim(_ args: [String], dry: Bool) -> Int32 {
    let mode = store.mode()
    if mode == "off" {
        emit("{\"ok\":false,\"error\":\"mode_off\",\"hint\":\"用户没开启 ddir\"}")
        return 0
    }
    let me = win.agentId()
    let lock = store.lock()
    defer { _ = lock }
    let (_, _, _, active) = activityTuple()
    if active && !hasFlag(args, "--force") {
        emit("{\"ok\":false,\"error\":\"user_active\",\"hint\":\"用户正在操作；等它空闲，或加 --force\"}")
        return 0
    }
    let managed = win.managedDisplays()
    if managed.isEmpty {
        emit("{\"ok\":false,\"error\":\"display_not_managed\",\"hint\":\"没有托管屏\"}")
        return 0
    }
    let prio = argValue(args, "--priority") ?? "normal"
    if !["low", "normal", "high", "user"].contains(prio) {
        emit("{\"ok\":false,\"error\":\"invalid_priority\",\"hint\":\"--priority low|normal|high|user\"}")
        return 0
    }
    var preempted: [String] = []
    let spec = argValue(args, "--needs") ?? positional(args).first ?? ""
    let needs = parseNeeds(spec)
    let now = nowUnix()
    let live = store.leases().filter { $0.expires > now }
    let busy = live.filter { $0.agent != me }
    let managedIds = managed.map { $0.uid }
    let wins = win.listWindows()

    var targets: [(WinInfo, Store.Lease?)] = []
    for l in live.filter({ $0.agent == me }) {
        if let w = wins.first(where: { $0.ref == l.window }), !w.minimized {
            targets.append((w, l))
        }
    }
    var blocked: Store.Lease?
    for need in needs {
        var chosen: WinInfo?
        for w in wins {
            if targets.contains(where: { $0.0.ref == w.ref }) { continue }
            if w.minimized { continue }
            if w.hidden && !live.contains(where: { $0.agent == me && $0.window == w.ref }) { continue }
            if !matches(w, need) { continue }
            if let b = busy.first(where: { $0.window == w.ref && !preempted.contains($0.lease) }) {
                func rank(_ p: String) -> Int {
                    switch p { case "user": return 3; case "high": return 2; case "normal": return 1; default: return 0 }
                }
                let victimIdle = now > b.since && now - b.since > 60
                let canPreempt = rank(prio) > rank(b.priority) && victimIdle && !w.foreground
                if canPreempt {
                    preempted.append(b.lease)
                    store.log("preempt \(w.ref) \(b.agent) -> \(me) (prio \(prio)>\(b.priority), age \(now - b.since)s)")
                    store.audit("preempt", "\(w.ref) from \(b.agent)")
                } else {
                    blocked = b
                    continue
                }
            }
            chosen = w
            break
        }
        if let w = chosen { targets.append((w, nil)) }
    }
    if targets.count > 3 { return quotaExceeded() }
    if targets.isEmpty {
        if let b = blocked {
            emit("{\"ok\":false,\"error\":\"window_owned_by\",\"window\":\"\(es(b.window))\","
                 + "\"owner_agent\":\"\(es(b.agent))\",\"expires_in_s\":\(b.expires > now ? b.expires - now : 0),"
                 + "\"hint\":\"该窗口正被另一个 Agent 使用；换窗口，或等它 release\"}")
        } else {
            emit("{\"ok\":false,\"error\":\"no_window\",\"hint\":\"没有匹配到托管屏上的窗口；先打开目标软件\"}")
        }
        return 0
    }

    let cells = layoutFor(targets.count, managed[0].work)
    let plan: [PlanItem] = targets.enumerated().map { i, t in
        PlanItem(win: t.0, rect: cells[i], lease: t.1, from: t.1?.from ?? t.0.win)
    }
    let assignJSON = plan.map {
        "{\"window\":\"\(es($0.win.ref))\",\"app\":\"\(es($0.win.app))\",\"title\":\"\(es($0.win.title))\","
            + "\"display\":\"\(es(managed[0].uid))\",\"from\":\(rectJSON($0.from)),\"rect\":\(rectJSON($0.rect)),"
            + "\"retiled\":\($0.lease != nil)}"
    }
    let managedUIDJSON = managedIds.map { "\"\(es($0))\"" }.joined(separator: ",")

    if dry {
        emit("{\"ok\":true,\"dry_run\":true,\"mode\":\"\(es(mode))\",\"displays_managed\":[\(managedUIDJSON)],"
             + "\"assign\":[\(assignJSON.joined(separator: ","))],\"focus\":\"none\"}")
        return 0
    }

    if !axGuard() { return 0 }
    let leaseId = String(format: "ls_%06x", UInt32(truncatingIfNeeded: now) ^ UInt32(getpid()))
    var all: [Store.Lease] = []
    for l in live {
        if preempted.contains(l.lease) { continue }
        if l.agent == me {
            if let p = plan.first(where: { $0.win.ref == l.window }) {
                var nl = l
                nl.to = p.rect
                nl.expires = now + LEASE_TTL
                all.append(nl)
                continue
            }
            if !wins.contains(where: { $0.ref == l.window }) { continue }
        }
        all.append(l)
    }
    let paced: Bool
    if let v = argValue(args, "--present") {
        paced = v == "paced"
    } else {
        paced = Present.presentation() == "paced"
    }
    let raiseOK = !live.contains { $0.agent != me && $0.expires > now }
    var pending = 0
    if paced {
        pending = Present.enqueue(plan.map { ($0.win.ref, $0.rect) }, raise: raiseOK)
    }
    var moved = 0
    for p in plan {
        if p.win.hidden { _ = win.showApp(p.win.pid) }
        if !paced {
            if win.setRect(p.win.ref, p.rect).0 { moved += 1 }
        }
        if p.lease == nil {
            all.append(Store.Lease(window: p.win.ref, agent: me, action: "move", from: p.from, to: p.rect,
                                   expires: now + LEASE_TTL, lease: leaseId, priority: prio, since: now))
        }
    }
    store.saveLeases(all)
    let retiled = plan.filter { $0.lease != nil }.count
    store.audit("claim", "lease=\(leaseId) windows=\(plan.count) retiled=\(retiled)")
    store.log("claim lease=\(leaseId) windows=\(plan.count) retiled=\(retiled)")
    emit("{\"ok\":true,\"lease\":\"\(leaseId)\",\"mode\":\"\(es(mode))\",\"displays_managed\":[\(managedUIDJSON)],"
         + "\"assign\":[\(assignJSON.joined(separator: ","))],\"retiled\":\(retiled),\"focus\":\"none\","
         + "\"ttl_s\":\(LEASE_TTL),\"presentation\":\"\(paced ? "paced" : "instant")\",\"pending\":\(pending),"
         + "\"preempted\":\(preempted.count),\"moved\":\(moved)}")
    return 0
}

// MARK: - move / hide / show

func cmdMove(_ args: [String]) -> Int32 {
    if !modeGuard() || !axGuard() { return 0 }
    guard let ref = argValue(args, "--window"), win.parseRef(ref) != nil else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"move --window pid:cgwin --rect x,y,w,h\"}")
        return 0
    }
    guard let rect = parseRect(argValue(args, "--rect") ?? "") else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"--rect x,y,w,h\"}")
        return 0
    }
    let (_, _, _, active) = activityTuple()
    if active && !hasFlag(args, "--force") {
        emit("{\"ok\":false,\"error\":\"user_active\",\"hint\":\"用户正在操作；等它空闲，或加 --force\"}")
        return 0
    }
    if win.resolve(ref) == nil {
        emit("{\"ok\":false,\"error\":\"no_window\",\"window\":\"\(es(ref))\"}")
        return 0
    }
    let (ok, actual) = win.setRect(ref, rect)
    let app = win.parseRef(ref).map { win.appName($0.pid) } ?? "?"
    store.audit("move", "\(ref) \(formatRect(rect)) actual=\(formatRect(actual))")
    emit("{\"ok\":\(ok),\"window\":\"\(es(ref))\",\"app\":\"\(es(app))\",\"rect\":\(rectJSON(rect)),"
         + "\"actual\":\(rectJSON(actual)),\"exact\":\(actual == rect)}")
    return 0
}

func cmdShowHide(_ args: [String], hide: Bool) -> Int32 {
    if hide && (!modeGuard() || !axGuard()) { return 0 }
    guard let ref = argValue(args, "--window"), let r = win.parseRef(ref) else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"hide|show --window pid:cgwin\"}")
        return 0
    }
    let ws = win.listWindows()
    guard let w = ws.first(where: { $0.ref == ref }) else {
        emit("{\"ok\":false,\"error\":\"no_window\",\"window\":\"\(es(ref))\"}")
        return 0
    }
    if hide {
        let me = win.agentId()
        let lock = store.lock()
        defer { _ = lock }
        let now = nowUnix()
        var leases = store.leases()
        leases.removeAll { $0.agent == me && $0.window == w.ref }
        leases.append(Store.Lease(window: w.ref, agent: me, action: "hide", from: w.win, to: w.win,
                                  expires: now + LEASE_TTL,
                                  lease: String(format: "ls_hide_%06x", UInt32(truncatingIfNeeded: now) ^ UInt32(getpid())),
                                  priority: "normal", since: now))
        store.saveLeases(leases)
        store.log("hide \(w.ref) @\(w.app) (lease recorded)")
    }
    let ok = hide ? win.hideApp(r.pid) : win.showApp(r.pid)
    store.audit(hide ? "hide" : "show", "\(ref) app=\(w.app)")
    emit("{\"ok\":\(ok),\"window\":\"\(es(ref))\",\"app\":\"\(es(w.app))\",\"hidden\":\(hide),"
         + "\"scope\":\"app\",\"note\":\"macOS 只能整应用隐藏/恢复（caps.window_hide=app）\"}")
    return 0
}

// MARK: - close / own

/// Ownership is by name; a pid matches if the stored name equals any of its aliases
/// (bundle executable / localized name / bundle id), so `own --app TextEdit` and
/// `own --app 文本编辑` both gate the same windows.
/// macOS window tabbing: closing a tab keeps the NSWindow (same CGWindowNumber) but shows
/// another document, so "closed" must also accept "this window now shows a different title".
func windowClosed(ref: String, title: String) -> Bool {
    guard let w = win.listWindows().first(where: { $0.ref == ref }) else { return true }
    return w.title != title
}

func ownedByMe(_ app: String, pid: pid_t, _ me: String) -> String? {
    let now = nowUnix()
    let apps = store.apps()
    let aliases = ([app] + win.appAliases(pid)).map { $0.lowercased() }
    guard let a = apps.first(where: { aliases.contains($0.app.lowercased()) }) else { return "not_owned" }
    if a.since + a.ttl <= now { return "not_owned" }
    if a.owner != me { return "owned_by_other:\(a.owner)" }
    return nil
}

func cmdClose(_ args: [String]) -> Int32 {
    if !modeGuard() || !axGuard() { return 0 }
    guard let ref = argValue(args, "--window"), win.parseRef(ref) != nil else {
        emit("{\"ok\":false,\"error\":\"invalid_args\"}")
        return 0
    }
    let ws = win.listWindows()
    guard let w = ws.first(where: { $0.ref == ref }) else {
        emit("{\"ok\":false,\"error\":\"no_window\"}")
        return 0
    }
    let me = win.agentId()
    if let e = ownedByMe(w.app, pid: w.pid, me) {
        if e.hasPrefix("owned_by_other") {
            emit("{\"ok\":false,\"error\":\"owned_by_other\",\"owner_agent\":\"\(es(e.components(separatedBy: ":").dropFirst().joined(separator: ":")))\"}")
        } else {
            emit("{\"ok\":false,\"error\":\"not_owned\",\"hint\":\"先 ddir own --app \\\"\(es(w.app))\\\" 认领\"}")
        }
        return 0
    }
    let pressed = win.closeWindow(ref)
    var dead = false
    for _ in 0..<30 {
        usleep(100_000)
        win.invalidateCG()
        if windowClosed(ref: ref, title: w.title) { dead = true; break }
    }
    store.audit("close", "\(w.ref) \(w.app) pressed=\(pressed) dead=\(dead)")
    if dead {
        emit("{\"ok\":true,\"closed\":true,\"window\":\"\(es(w.ref))\",\"app\":\"\(es(w.app))\",\"process_alive\":true}")
    } else {
        emit("{\"ok\":false,\"error\":\"close_blocked\",\"window\":\"\(es(w.ref))\","
             + "\"reason\":\"3 秒内窗口未消失（可能有未保存内容或模态框），不重试、不强杀\"}")
    }
    return 0
}

func cmdOwn(_ args: [String], disown: Bool) -> Int32 {
    guard let app = argValue(args, "--app") else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"own --app <name>\"}")
        return 0
    }
    let me = win.agentId()
    let now = nowUnix()
    let lock = store.lock()
    defer { _ = lock }
    // Canonicalize to the bundle executable name so one app has one owner row
    // (`TextEdit` == `文本编辑` == `com.apple.TextEdit`).
    var target = app
    if let hit = NSWorkspace.shared.runningApplications.first(where: {
        ([$0.executableURL?.lastPathComponent ?? "", $0.localizedName ?? "", $0.bundleIdentifier ?? ""])
            .contains { sameApp($0, app) }
    }) {
        target = win.appName(hit.processIdentifier)
    }
    var apps = store.apps()
    let idx = apps.firstIndex { sameApp($0.app, target) }
    if disown {
        if let i = idx {
            apps.remove(at: i)
            store.saveApps(apps)
        }
        store.audit("disown", app)
        emit("{\"ok\":true,\"app\":\"\(es(app))\"}")
        return 0
    }
    if let i = idx {
        let a = apps[i]
        if a.since + a.ttl > now && a.owner != me {
            emit("{\"ok\":false,\"error\":\"owned_by_other\",\"owner_agent\":\"\(es(a.owner))\","
                 + "\"owner_since\":\(a.since),\"hint\":\"换实例或等它 disown\"}")
            return 0
        }
        apps.remove(at: i)
    }
    apps.append(Store.AppOwner(app: target, owner: me, since: now, ttl: 1800))
    store.saveApps(apps)
    store.audit("own", target)
    emit("{\"ok\":true,\"app\":\"\(es(target))\",\"owner\":\"\(es(me))\"}")
    return 0
}

// MARK: - release / heartbeat / focus

/// Restore leases.
/// - `force: false` (CLI `ddir release`) restores only *my* live leases (D22: agents never
///   release somebody else's windows).
/// - `force: true` (tray menu, human pressed "全部还原") restores every live lease: the user
///   outranks all agents, and the tray's own process identity is unrelated to theirs.
func releaseAll(force: Bool = false) -> (Int, Int) {
    let lock = store.lock()
    defer { _ = lock }
    let me = win.agentId()
    let now = nowUnix()
    let all = store.leases()
    let live = all.filter { $0.expires > now }
    let targets = live.filter { force || $0.agent == me }
    let others = all.filter { l in !targets.contains(where: { $0.lease == l.lease && $0.window == l.window }) }
    var n = 0
    for l in targets {
        guard let r = win.parseRef(l.window) else { continue }
        win.invalidateCG()
        if l.action == "hide" {
            if win.showApp(r.pid) { n += 1 }
        } else if win.resolve(l.window) != nil {
            if win.setRect(l.window, l.from).0 { n += 1 }
        }
    }
    store.saveLeases(others)
    store.audit("release", "restored=\(n) forced=\(force)")
    store.log("release restored=\(n) forced=\(force) kept=\(others.count)")
    return (n, others.count)
}

func cmdRelease() -> Int32 {
    let (n, kept) = releaseAll()
    emit("{\"ok\":true,\"released\":\(n),\"other_leases_kept\":\(kept)}")
    return 0
}

func cmdHeartbeat() -> Int32 {
    let me = win.agentId()
    let now = nowUnix()
    let lock = store.lock()
    defer { _ = lock }
    var leases = store.leases()
    var n = 0
    for i in leases.indices where leases[i].agent == me && leases[i].expires > now {
        leases[i].expires = now + LEASE_TTL
        n += 1
    }
    store.saveLeases(leases)
    var apps = store.apps()
    var na = 0
    for i in apps.indices where apps[i].owner == me {
        apps[i].since = now
        na += 1
    }
    store.saveApps(apps)
    store.log("heartbeat leases=\(n) apps=\(na)")
    emit("{\"ok\":true,\"renewed\":\(n),\"apps\":\(na),\"ttl_s\":\(LEASE_TTL)}")
    return 0
}

func cmdFocus(_ args: [String]) -> Int32 {
    let me = win.agentId()
    let now = nowUnix()
    let sub = args.first ?? "acquire"
    if sub == "release" {
        if let (h, _) = focusHolder(), h == me {
            try? FileManager.default.removeItem(atPath: store.path("focus.tsv"))
            store.log("focus released")
            emit("{\"ok\":true,\"holder\":null}")
            return 0
        }
        emit("{\"ok\":false,\"error\":\"not_holder\"}")
        return 0
    }
    if let (h, exp) = focusHolder(), h != me, exp > now {
        emit("{\"ok\":false,\"error\":\"focus_denied\",\"holder\":\"\(es(h))\",\"expires_in_s\":\(exp - now)}")
        return 0
    }
    let ttl = UInt64(argValue(args, "--seconds") ?? "") ?? 120
    try? "\(me)\t\(now + ttl)\n".write(toFile: store.path("focus.tsv"), atomically: false, encoding: .utf8)
    store.log("focus acquired ttl=\(ttl)")
    emit("{\"ok\":true,\"holder\":\"\(es(me))\",\"ttl_s\":\(ttl)}")
    return 0
}

// MARK: - config / log / flush

func cmdConfig(_ args: [String]) -> Int32 {
    let pos = positional(args)
    if pos.isEmpty {
        var all = store.configAll()
        for (k, v) in [("auto_close", "off"), ("countdown_seconds", "10")] where !all.contains(where: { $0.0 == k }) {
            all.append((k, v))
        }
        let rows = all.map { "{\"\(es($0.0))\":\"\(es($0.1))\"}" }
        emit("{\"ok\":true,\"path\":\"\(es(store.configPath()))\",\"config\":[\(rows.joined(separator: ","))]}")
        return 0
    }
    let key: String
    let value: String
    if pos.count >= 2 {
        key = pos[0]
        value = pos[1]
    } else if let eq = pos[0].firstIndex(of: "=") {
        key = String(pos[0][pos[0].startIndex..<eq])
        value = String(pos[0][pos[0].index(after: eq)...])
    } else {
        emit("{\"ok\":false,\"error\":\"invalid_args\",\"hint\":\"config <key> <value>  或  config key=value\"}")
        return 0
    }
    if let err = store.configSet(key, value) {
        emit("{\"ok\":false,\"error\":\"\(es(err))\"}")
    } else {
        store.log("config \(key)=\(value)")
        emit("{\"ok\":true,\"\(es(key))\":\"\(es(value))\"}")
    }
    return 0
}

func cmdLog(_ args: [String]) -> Int32 {
    let n = argValue(args, "--lines").flatMap { Int($0) } ?? 40
    let lines = store.logTail(n)
    for l in lines { print(l) }
    if lines.isEmpty { print("(log is empty)") }
    return 0
}

func cmdFlush() -> Int32 {
    let queued = Present.pending()
    let applied = Present.drain(30_000)
    emit("{\"ok\":true,\"queued\":\(queued),\"applied\":\(applied),\"pending\":\(Present.pending())}")
    return 0
}

// MARK: - auto pipeline

func armedPath() -> String { store.path("armed.txt") }
func closedPath() -> String { store.path("closed.tsv") }

func isArmed() -> Bool {
    guard let s = try? String(contentsOfFile: armedPath(), encoding: .utf8),
          let ts = UInt64(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return nowUnix() < ts + 3600
}

func arm() { try? String(nowUnix()).write(toFile: armedPath(), atomically: false, encoding: .utf8) }

struct Candidate {
    var app: String
    var windows: Int
    var refs: [String]
    var pids: [pid_t]
    var bundle: String
}

func agentsOwn(_ app: String) -> Bool {
    let now = nowUnix()
    return store.apps().contains { sameApp($0.app, app) && $0.since + $0.ttl > now }
}

func candidates(_ only: String?) -> [Candidate] {
    let front = NSWorkspace.shared.frontmostApplication.map { win.appName($0.processIdentifier) } ?? ""
    var out: [Candidate] = []
    for w in win.listWindows() {
        if w.minimized { continue }
        if let name = only {
            if !sameApp(w.app, name) && !w.title.lowercased().contains(name.lowercased()) { continue }
        } else {
            if sameApp(w.app, front) || agentsOwn(w.app) || sameApp(w.app, "Finder") { continue }
        }
        if let i = out.firstIndex(where: { $0.app == w.app }) {
            out[i].windows += 1
            out[i].refs.append(w.ref)
            if !out[i].pids.contains(w.pid) { out[i].pids.append(w.pid) }
        } else {
            out.append(Candidate(app: w.app, windows: 1, refs: [w.ref], pids: [w.pid],
                                 bundle: win.bundlePath(w.pid)))
        }
    }
    return out
}

func cmdAuto(_ args: [String]) -> Int32 {
    let sub = args.first ?? "status"
    switch sub {
    case "status":
        let closed = ((try? String(contentsOfFile: closedPath(), encoding: .utf8)) ?? "")
            .split(separator: "\n").count
        emit("{\"ok\":true,\"mode\":\"\(store.mode())\",\"armed\":\(isArmed()),\"closed\":\(closed)}")
    case "plan":
        let cs = candidates(argValue(args, "--app"))
        let rows = cs.map { "{\"app\":\"\(es($0.app))\",\"windows\":\($0.windows),\"pids\":\($0.pids.count)}" }
        emit("{\"ok\":true,\"mode\":\"\(store.mode())\",\"armed\":\(isArmed()),\"candidates\":[\(rows.joined(separator: ","))]}")
    case "on":
        if store.mode() != "auto" {
            emit("{\"ok\":false,\"error\":\"mode_not_auto\",\"hint\":\"先 ddir mode auto（或托盘切到全自动）再武装\"}")
            return 0
        }
        let secs = UInt64(argValue(args, "--seconds") ?? "")
            ?? UInt64(store.configGet("countdown_seconds") ?? "") ?? 10
        let cs = candidates(nil)
        let names = cs.map { "\($0.app)(\($0.windows)窗口)" }
        print("== 将接管（只是候选，不会立刻关闭）")
        print("   " + (names.isEmpty ? "（没有候选）" : names.joined(separator: "、")))
        print("== 保护：被 Agent 认领 / 前台软件 / Finder / ddir 自身")
        print("== 倒计时 \(secs) 秒；期间随时切回 semi/off（ddir mode）即可取消")
        var i = secs
        while i >= 1 {
            if store.mode() != "auto" {
                store.audit("auto_abort", "mode switched during countdown")
                print("\n已取消武装：模式已切回 \(store.mode())")
                emit("{\"ok\":false,\"error\":\"aborted\",\"mode\":\"\(store.mode())\"}")
                return 0
            }
            print("\r  \(i) 秒 ", terminator: "")
            fflush(stdout)
            usleep(250_000)
            if store.mode() != "auto" {
                store.audit("auto_abort", "mode switched during countdown")
                print("\n已取消武装：模式已切回 \(store.mode())")
                emit("{\"ok\":false,\"error\":\"aborted\",\"mode\":\"\(store.mode())\"}")
                return 0
            }
            usleep(750_000)
            i -= 1
        }
        arm()
        store.audit("auto_arm", "seconds=\(secs) candidates=\(cs.count)")
        print("\n已武装（1 小时内有效）：现在可以 ddir auto close 了")
        emit("{\"ok\":true,\"armed\":true,\"candidates\":\(cs.count)}")
    case "close":
        if store.mode() != "auto" {
            emit("{\"ok\":false,\"error\":\"mode_not_auto\",\"hint\":\"先 ddir mode auto\"}")
            return 0
        }
        if !isArmed() {
            emit("{\"ok\":false,\"error\":\"needs_user_consent\",\"hint\":\"先 ddir auto on 武装（倒计时确认）\"}")
            return 0
        }
        let autoClose = store.configGet("auto_close") ?? "off"
        if autoClose == "off" {
            store.log("auto close 被配置拒绝（auto_close=off）")
            emit("{\"ok\":false,\"error\":\"auto_close_disabled\",\"hint\":\"配置 auto_close=off，不会自动关任何窗口。需要时 ddir config auto_close minimize|close\"}")
            return 0
        }
        let explicit = argValue(args, "--app")
        if explicit == nil && !hasFlag(args, "--force") {
            emit("{\"ok\":false,\"error\":\"needs_explicit_target\",\"hint\":\"自动挑目标很容易关错东西：用 --app <名字> 指定，或加 --force 让它自己挑（最多 3 个）\"}")
            return 0
        }
        let limit = argValue(args, "--max").flatMap { Int($0) } ?? 3
        let cs = candidates(explicit)
        var closed = 0
        var blocked = 0
        for c in cs.prefix(limit) {
            let bundle = c.bundle
            let firstRect = win.listWindows().first { $0.app == c.app }?.win ?? [0, 0, 0, 0]
            if autoClose == "minimize" {
                for ref in c.refs { _ = win.minimize(ref) }
                store.append(closedPath(), "\(c.app)\t\tminimize\t\(nowUnix())\n")
                store.log("auto minimize: \(c.app)")
                print("已最小化：\(c.app)（auto_close=minimize）")
                closed += 1
                continue
            }
            for ref in c.refs { _ = win.closeWindow(ref) }
            var gone = false
            for _ in 0..<30 {
                usleep(100_000)
                win.invalidateCG()
                if !win.listWindows().contains(where: { $0.app == c.app }) { gone = true; break }
            }
            if gone {
                store.append(closedPath(), "\(c.app)\t\(bundle)\t\(formatRect(firstRect))\t\(nowUnix())\n")
                store.audit("auto_close", c.app)
                print("已关闭：\(c.app)" + (bundle.isEmpty ? "（无路径，撤销时只能提示）" : ""))
                closed += 1
            } else {
                store.audit("auto_close_blocked", c.app)
                print("close_blocked：\(c.app)（有未保存内容或模态框，已跳过，不重试）")
                blocked += 1
            }
        }
        emit("{\"ok\":true,\"closed\":\(closed),\"blocked\":\(blocked)}")
    case "undo":
        let txt = (try? String(contentsOfFile: closedPath(), encoding: .utf8)) ?? ""
        var n = 0
        for line in txt.split(separator: "\n") {
            let f = line.components(separatedBy: "\t")
            if f.isEmpty { continue }
            if f.count >= 3 && f[1].isEmpty && f[2] == "minimize" {
                let app = f[0]
                for w in win.listWindows() where w.app == app && w.minimized {
                    if win.restore(w.ref) { n += 1 }
                }
                store.log("undo minimize: \(app) (all windows)")
                continue
            }
            if f.count < 3 || f[1].isEmpty { continue }
            let app = f[0]
            let path = f[1]
            let rect = parseRect(f[2]) ?? []
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", path]
            if (try? p.run()) != nil {
                n += 1
                for _ in 0..<40 {
                    usleep(250_000)
                    win.invalidateCG()
                    if let w = win.listWindows().first(where: { $0.app == app }), rect.count == 4, rect[2] > 0 {
                        _ = win.setRect(w.ref, rect)
                        break
                    }
                }
            }
        }
        try? FileManager.default.removeItem(atPath: closedPath())
        store.audit("auto_undo", "relaunched=\(n)")
        emit("{\"ok\":true,\"relaunched\":\(n)}")
    default:
        emit("{\"ok\":false,\"error\":\"unknown_auto_subcmd\"}")
    }
    return 0
}

// MARK: - autostart (LaunchAgent)

func cmdAutostart(_ args: [String]) -> Int32 {
    let action = args.first ?? "status"
    switch action {
    case "on":
        emit("{\"ok\":true,\"enabled\":\(Autostart.set(true)),\"plist\":\"\(es(Autostart.plistPath))\"}")
    case "off":
        emit("{\"ok\":true,\"enabled\":\(Autostart.set(false)),\"plist\":\"\(es(Autostart.plistPath))\"}")
    default:
        emit("{\"ok\":true,\"enabled\":\(Autostart.on()),\"plist\":\"\(es(Autostart.plistPath))\"}")
    }
    return 0
}

// MARK: - board / selftest / demo / help

func cmdBoard() -> Int32 {
    let me = win.agentId()
    let now = nowUnix()
    let live = store.leases().filter { $0.expires > now }
    let (idle, moved, _, active) = activityTuple()
    print("== ddir v\(VERSION) (macos)  mode \(store.mode())  you \(me)  input_age=\(idle)s user_active=\(active) cursor_moved=\(moved)pt")
    let ws = win.listWindows()
    print("== windows \(ws.count)  displays \(win.displays().count)")
    if live.isEmpty {
        print("== no lease")
    } else {
        for l in live {
            print("== lease \(l.lease)  \(l.agent)  \(l.window)  \(l.priority)  expires_in \(l.expires > now ? l.expires - now : 0)s")
        }
        var agents = live.map { $0.agent }
        agents.sort()
        for a in Set(agents).sorted() {
            print("== agent \(a)  leases=\(live.filter { $0.agent == a }.count)")
        }
    }
    for a in store.apps() where a.since + a.ttl > now {
        print("== owned \(a.app) -> \(a.owner)")
    }
    return 0
}

/// Open a TextEdit window of our own (never touches the user's documents).
func openTestWindow(_ label: String) -> WinInfo? {
    let path = NSTemporaryDirectory() + "ddir-selftest-\(getpid()).txt"
    try? "ddir write-path self test\n".write(toFile: path, atomically: true, encoding: .utf8)
    let before = Set(win.listWindows().filter { sameApp($0.app, "TextEdit") }.map { $0.ref })
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-a", "TextEdit", path]
    try? p.run()
    for _ in 0..<25 {
        usleep(120_000)
        win.invalidateCG()
        let fresh = win.listWindows().filter { sameApp($0.app, "TextEdit") && !before.contains($0.ref) }
        if let w = fresh.first { return w }
    }
    return nil
}

func cmdSelftest(_ args: [String]) -> Int32 {
    var pass = 0
    var fail = 0
    func check(_ name: String, _ ok: Bool, _ detail: String) {
        if ok { pass += 1; print("PASS  \(name)") } else { fail += 1; print("FAIL  \(name)  \(detail)") }
    }
    let ds = win.displays()
    check("displays>=1", !ds.isEmpty, "no display")
    check("managed displays>=1", ds.contains { $0.managed }, "no managed display")
    let ws = win.listWindows()
    check("windows>0", !ws.isEmpty, "no visible window")
    check("geometry sane", ws.allSatisfy { $0.frame[2] >= 0 && $0.frame[3] >= 0 && $0.frame[0] > -20000 && $0.frame[1] > -20000 }, "insane rect")
    check("mode valid", ["off", "semi", "auto"].contains(store.mode()), "bad mode")
    check("idle readable", win.idleSeconds() >= 0, "CGEventSource idle failed")
    let (w, h) = win.workSize()
    check("work area", w > 0 && h > 0, "bad work area")
    print("INFO  accessibility=\(win.axTrusted) screen_recording=\(win.screenRecording) windows=\(ws.count) displays=\(ds.count)")
    print("INFO  state=\(store.home().path)")

    if hasFlag(args, "--write") {
        // Opt-in write path: our own TextEdit window, moved / hidden / closed then cleaned up.
        guard let w = openTestWindow("selftest") else {
            check("write: open window", false, "TextEdit did not open a window")
            print("---")
            print("RESULT: \(pass) passed, \(fail) failed")
            return 1
        }
        check("write: open window", true, "")
        let target = [60, 60, 520, 360]
        let moved = win.setRect(w.ref, target)
        let actual = win.setRect(w.ref, target).1
        check("write: move", moved.0 && actual == target, "readback \(formatRect(actual))")
        let hiddenOK = win.hideApp(w.pid)
        usleep(250_000)
        let isHidden = NSRunningApplication(processIdentifier: w.pid)?.isHidden ?? false
        check("write: hide", hiddenOK && isHidden, "hidden=\(isHidden)")
        _ = win.showApp(w.pid)
        usleep(250_000)
        check("write: show", !(NSRunningApplication(processIdentifier: w.pid)?.isHidden ?? true), "still hidden")
        // own + close: window gone, process alive
        var apps = store.apps()
        apps.removeAll { sameApp($0.app, "TextEdit") }
        apps.append(Store.AppOwner(app: "TextEdit", owner: win.agentId(), since: nowUnix(), ttl: 1800))
        store.saveApps(apps)
        let pressed = win.closeWindow(w.ref)
        var gone = false
        for _ in 0..<30 {
            usleep(100_000)
            win.invalidateCG()
            if windowClosed(ref: w.ref, title: w.title) { gone = true; break }
        }
        check("write: close window", pressed && gone, "pressed=\(pressed) gone=\(gone)")
        check("write: process alive", NSRunningApplication(processIdentifier: w.pid) != nil, "TextEdit quit")
        apps.removeAll { sameApp($0.app, "TextEdit") }
        store.saveApps(apps)
    }

    print("---")
    print("RESULT: \(pass) passed, \(fail) failed")
    return fail > 0 ? 1 : 0
}

func cmdDemo() -> Int32 {
    let dir = store.home().appendingPathComponent("demo", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let files = [("a.txt", "alpha\nbeta\ngamma\n"), ("b.txt", "one\ntwo\nthree\n"), ("c.txt", "red\ngreen\nblue\n")]
    for (name, body) in files {
        try? body.write(toFile: "\(dir)/\(name)", atomically: false, encoding: .utf8)
    }
    if store.mode() == "off" {
        _ = store.setMode("semi")
        store.log("demo: mode off -> semi")
    }
    let savedAC = store.configGet("auto_close")
    let savedPres = store.configGet("presentation")
    _ = store.configSet("auto_close", "off")
    _ = store.configSet("presentation", "paced")
    print("== ddir demo (macOS/TextEdit)  节拍 \(Present.stepMs()) ms，演示完自动还原")
    var opened: [String] = []
    var lastLease = ""
    for (i, f) in files.enumerated() {
        let path = "\(dir)/\(f.0)"
        let before = Set(win.listWindows().filter { sameApp($0.app, "TextEdit") }.map { $0.ref })
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "TextEdit", path]
        try? p.run()
        var found: [String] = []
        for _ in 0..<20 {
            usleep(150_000)
            win.invalidateCG()
            found = win.listWindows().filter { sameApp($0.app, "TextEdit") && !before.contains($0.ref) }.map { $0.ref }
            if !found.isEmpty { break }
        }
        opened.append(contentsOf: found)
        let rc = cmdClaim(["--needs", f.0, "--force", "--present", "paced"], dry: false)
        _ = rc
        _ = Present.drain(10_000)
        print("   第 \(i + 1) 个窗口 \(f.0) -> 打开 \(found.count) 个")
        if let l = store.leases().last { lastLease = l.lease }
        usleep(700_000)
    }
    print("== 布局完成（lease \(lastLease)），3 秒后收队")
    sleep(3)
    let (n, _) = releaseAll()
    print("== 已还原 \(n) 个窗口")
    usleep(800_000)
    for ref in opened { _ = win.closeWindow(ref) }
    if let v = savedAC { _ = store.configSet("auto_close", v) }
    if let v = savedPres { _ = store.configSet("presentation", v) } else { _ = store.configSet("presentation", "instant") }
    store.log("demo: finished")
    emit("{\"ok\":true,\"opened\":\(opened.count),\"restored\":\(n)}")
    return 0
}

func usage() {
    print("ddir \(VERSION) - Desktop Director (macOS backend, Accessibility API)")
    print()
    print("  ddir mode [off|semi|auto]              show/switch mode")
    print("  ddir displays [--manage UID [--off]]   list / hand displays to the agent")
    print("  ddir list [--text]                     windows (Alt-Tab level)")
    print("  ddir status                            leases / owned apps / focus (json)")
    print("  ddir plan [--needs \"a,b\"] [--priority P]   dry-run layout")
    print("  ddir claim [--needs \"a,b\"] [--force] [--priority P] [--present paced]")
    print("  ddir move --window pid:cgwin --rect x,y,w,h [--force]")
    print("  ddir hide|show --window pid:cgwin       hide is app-wide on macOS; release restores")
    print("  ddir close --window pid:cgwin           AX close button, owned apps only")
    print("  ddir own --app <n> | disown --app <n>  software ownership")
    print("  ddir release                           restore my leases")
    print("  ddir heartbeat                         renew my lease TTL")
    print("  ddir focus [--seconds N] | focus release   focus token")
    print("  ddir auto status|plan|on|close|undo    auto-mode pipeline")
    print("  ddir config [key value]                view/update config")
    print("  ddir log [--lines N]                   tail ~/.ddir/ddir.log")
    print("  ddir flush                             drain the paced presentation queue")
    print("  ddir demo                              scripted demo (TextEdit windows)")
    print("  ddir hud [--wall] [--seconds N|--check]  corner toast (default) or full thumbnail wall")
    print("  ddir tray [--check]                    menu bar app (modes/restore/log/displays/autostart)")
    print("  ddir autostart [on|off|status]         run tray at login (LaunchAgent)")
    print("  ddir board                             human readable overview")
    print("  ddir selftest [--write]                platform checks (7) + optional write path")
    print("  ddir doctor [--text]                   permissions / signing / tray / autostart diagnostics")
    print("  ddir prompt [--install|--check]        print or install the cross-platform AGENTS prompt")
    print()
    print("env: DDIR_HOME (default ~/.ddir), DDIR_AGENT (identity override)")
    print("permissions: System Settings > Privacy & Security > Accessibility must include Ddir.app")
}
