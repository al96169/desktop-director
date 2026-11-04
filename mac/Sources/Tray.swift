// ddir macOS backend — menu bar app (NSStatusItem).
// Mirrors the Windows tray (src/tray.rs): three modes, restore-all, auto_close policy,
// window list, log, state folder, autostart, quit. Runs as an accessory app (no Dock icon).
//
//   ddir tray            run in the menu bar (blocks; quit from the menu)
//   ddir tray --check    print the menu tree as JSON and exit (automation / tests)

import AppKit
import ApplicationServices

final class TrayController: NSObject, NSMenuDelegate {
    static let shared = TrayController()

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lockFD: Int32 = -1
    private var watched: [(ref: String, app: String)] = []
    private var transientTitle: String?

    // MARK: - lifecycle

    func run() -> Int32 {
        guard acquireLock() else {
            emit("{\"ok\":false,\"error\":\"already_running\",\"hint\":\"托盘已在运行（菜单栏右上角的 ddir 图标）\"}")
            return 0
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatus()

        watched = currentWindows()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }

        Store.shared.log("tray: started (mode=\(store.mode()), pid=\(getpid()), accessibility=\(win.axTrusted), windows=\(watched.count), autostart=\(Autostart.on()))")
        app.run()
        Store.shared.log("tray: stopped")
        return 0
    }

    /// One process per user; the kernel drops the flock when we die.
    private func acquireLock() -> Bool {
        store.ensureHome()
        lockFD = open(store.path("tray.lock"), O_CREAT | O_RDWR, 0o644)
        if lockFD < 0 { return true }
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0
    }

    private func refreshStatus() {
        guard let button = statusItem?.button else { return }
        let mode = store.mode()
        let symbol: String
        switch mode {
        case "auto": symbol = "circle.fill"
        case "semi": symbol = "circle.lefthalf.filled"
        default: symbol = "circle"
        }
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ddir \(mode)") {
            img.isTemplate = true
            button.image = img
        }
        if let t = transientTitle {
            button.title = t
        } else {
            button.title = mode
        }
        let n = leaseCount()
        let owned = store.apps().filter { $0.since + $0.ttl > nowUnix() }.count
        button.toolTip = "ddir \(mode) · 租约 \(n) · 认领软件 \(owned)"
    }

    /// Live leases across all agents: the tray speaks for the user, not for one agent.
    private func leaseCount() -> Int {
        let now = nowUnix()
        return store.leases().filter { $0.expires > now }.count
    }

    private func flash(_ text: String) {
        transientTitle = text
        refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.transientTitle = nil
            self?.refreshStatus()
        }
    }

    // MARK: - periodic work (mirrors tray.rs WM_TIMER)

    private func tick() {
        Present.tick()
        watchUnmanagedKills()
        refreshStatus()
    }

    private func currentWindows() -> [(ref: String, app: String)] {
        win.listWindows().map { ($0.ref, $0.app) }
    }

    private func recentCloseAudit(_ app: String) -> Bool {
        let now = nowUnix()
        guard let txt = try? String(contentsOfFile: store.path("audit.tsv"), encoding: .utf8) else { return false }
        for line in txt.split(separator: "\n").suffix(200).reversed() {
            let f = line.components(separatedBy: "\t")
            if f.count < 3 { continue }
            let ts = UInt64(f[0]) ?? 0
            if now > ts && now - ts > 20 { break }
            if ["close", "auto_close", "auto_minimize"].contains(f[1]), f[2].contains(app) { return true }
        }
        return false
    }

    /// D9: an app that loses its last window without a ddir close is an out-of-band kill.
    private func watchUnmanagedKills() {
        let cur = currentWindows()
        for (ref, app) in watched {
            if cur.contains(where: { $0.ref == ref }) { continue }
            if cur.contains(where: { $0.app == app }) { continue }
            if ["Finder", "Ddir"].contains(where: { sameApp(app, $0) }) { continue }
            if recentCloseAudit(app) { continue }
            store.log("unmanaged_kill: \(app) (window \(ref) disappeared without ddir close)")
            store.audit("unmanaged_kill", app)
            if store.configGet("downgrade_on_unmanaged_kill") == "true" {
                _ = store.setMode("semi")
                store.log("unmanaged_kill: downgraded to semi")
            }
        }
        watched = cur
    }

    // MARK: - menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mode = store.mode()
        let now = nowUnix()
        let leases = store.leases().filter { $0.expires > now }.count
        let owned = store.apps().filter { $0.since + $0.ttl > now }.count

        let header = NSMenuItem(title: "状态：\(mode) · 租约 \(leases) · 认领软件 \(owned)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let modeItem = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeItem.submenu = buildModeMenu(current: mode)
        menu.addItem(modeItem)

        let restore = NSMenuItem(title: "全部还原（所有人）", action: #selector(doRelease), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)

        let acItem = NSMenuItem(title: "自动关闭", action: nil, keyEquivalent: "")
        acItem.submenu = buildAutoCloseMenu(current: store.configGet("auto_close") ?? "off")
        menu.addItem(acItem)

        let winItem = NSMenuItem(title: "窗口列表", action: nil, keyEquivalent: "")
        winItem.submenu = buildWindowMenu()
        menu.addItem(winItem)

        let dispItem = NSMenuItem(title: "托管屏", action: nil, keyEquivalent: "")
        dispItem.submenu = buildDisplayMenu()
        menu.addItem(dispItem)

        menu.addItem(.separator())

        let hudItem = NSMenuItem(title: "HUD 提示（3 秒）", action: #selector(previewHud), keyEquivalent: "")
        hudItem.target = self
        menu.addItem(hudItem)
        let wallItem = NSMenuItem(title: "HUD 缩略图墙（6 秒）", action: #selector(previewWall), keyEquivalent: "")
        wallItem.target = self
        menu.addItem(wallItem)

        let logItem = NSMenuItem(title: "查看日志", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        let stateItem = NSMenuItem(title: "打开状态目录 ~/.ddir", action: #selector(openStateDir), keyEquivalent: "")
        stateItem.target = self
        menu.addItem(stateItem)

        let auto = NSMenuItem(title: "开机自启", action: #selector(toggleAutostart), keyEquivalent: "")
        auto.target = self
        auto.state = Autostart.on() ? .on : .off
        menu.addItem(auto)

        if !win.screenRecording {
            let hud = NSMenuItem(title: "HUD 需要屏幕录制授权（系统设置 → 隐私与安全性）", action: nil, keyEquivalent: "")
            hud.isEnabled = false
            menu.addItem(hud)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func buildModeMenu(current: String) -> NSMenu {
        let menu = NSMenu()
        for (m, label) in [("off", "off（不碰窗口）"), ("semi", "semi（半自动）"), ("auto", "auto（全自动）")] {
            let i = NSMenuItem(title: label, action: #selector(setMode(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = m
            i.state = current == m ? .on : .off
            menu.addItem(i)
        }
        return menu
    }

    private func buildAutoCloseMenu(current: String) -> NSMenu {
        let menu = NSMenu()
        for (v, label) in [("off", "off（永不自动关窗口）"), ("minimize", "minimize（最小化代替关闭）"), ("close", "close（允许关闭，需先武装）")] {
            let i = NSMenuItem(title: label, action: #selector(setAutoClose(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = v
            i.state = current == v ? .on : .off
            menu.addItem(i)
        }
        return menu
    }

    private func buildWindowMenu() -> NSMenu {
        let menu = NSMenu()
        let ws = win.listWindows().sorted { ($0.app, $0.title) < ($1.app, $1.title) }
        if ws.isEmpty {
            let none = NSMenuItem(title: "（没有窗口）", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return menu
        }
        for w in ws.prefix(8) {
            let short = w.title.count > 32 ? String(w.title.prefix(32)) + "…" : w.title
            let i = NSMenuItem(title: "\(w.app)：\(short)", action: #selector(focusWindow(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = w.ref
            menu.addItem(i)
        }
        return menu
    }

    private func buildDisplayMenu() -> NSMenu {
        let menu = NSMenu()
        let uids = concreteManagedUIDs()
        for d in win.displays() {
            let i = NSMenuItem(title: "\(d.gdi)  \(d.label)\(d.primary ? "（主屏）" : "")", action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = d.uid
            i.state = uids.contains(d.uid) ? .on : .off
            menu.addItem(i)
        }
        return menu
    }

    // MARK: - actions

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let m = sender.representedObject as? String else { return }
        if let err = store.setMode(m) {
            store.log("tray: setMode failed: \(err)")
            return
        }
        store.audit("mode", m)
        store.log("mode -> \(m) (tray)")
        flash(m)
    }

    @objc private func doRelease() {
        let (n, kept) = releaseAll(force: true)
        store.log("tray: release restored=\(n) other_leases_kept=\(kept)")
        flash("还原 \(n)")
    }

    @objc private func setAutoClose(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        _ = store.configSet("auto_close", v)
        store.log("tray: auto_close=\(v)")
        flash("auto:\(v)")
    }

    @objc private func focusWindow(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? String, let r = win.parseRef(ref) else { return }
        if let el = win.resolve(ref) {
            AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: r.pid)?.activate(options: [.activateIgnoringOtherApps])
        store.log("tray: focus \(ref)")
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        var list = concreteManagedUIDs()
        if let i = list.firstIndex(of: uid) {
            list.remove(at: i)
        } else {
            list.append(uid)
        }
        applyManagedUIDs(list)
        store.log("tray: managed_displays=\(list.joined(separator: ","))")
    }

    @objc private func previewHud() {
        // the tray already runs an NSApplication loop: build the overlay, don't run another loop
        _ = HudController.shared.present(style: .toast, seconds: 3)
    }

    @objc private func previewWall() {
        _ = HudController.shared.present(style: .wall, seconds: 6)
    }

    @objc private func openLog() {
        let p = store.path("ddir.log")
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }

    @objc private func openStateDir() {
        NSWorkspace.shared.open(store.home())
    }

    @objc private func toggleAutostart() {
        let on = Autostart.set(!Autostart.on())
        flash(on ? "自启:on" : "自启:off")
    }

    @objc private func quit() {
        Store.shared.log("tray: quit from menu")
        NSApp.terminate(nil)
    }

    // MARK: - introspection (ddir tray --check)

    func checkJSON() -> String {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        let mode = store.mode()
        return "{\"ok\":true,\"platform\":\"macos\",\"mode\":\"\(es(mode))\",\"leases\":\(leaseCount()),"
            + "\"autostart\":\(Autostart.on()),\"accessibility\":\(win.axTrusted),\"screen_recording\":\(win.screenRecording),"
            + "\"menu\":\(menuJSON(menu))}"
    }

    private func stateName(_ s: NSControl.StateValue) -> String {
        s == .on ? "\"on\"" : (s == .off ? "\"off\"" : "\"mixed\"")
    }

    private func menuJSON(_ menu: NSMenu) -> String {
        let parts: [String] = menu.items.map { item in
            var s = "{\"title\":\"\(es(item.title))\",\"enabled\":\(item.isEnabled),\"state\":\(stateName(item.state))"
            if item.isSeparatorItem { s = "{\"separator\":true" }
            if let sub = item.submenu { s += ",\"submenu\":\(menuJSON(sub))" }
            return s + "}"
        }
        return "[" + parts.joined(separator: ",") + "]"
    }
}

/// `ddir tray` / `ddir tray --check`
func cmdTray(_ args: [String]) -> Int32 {
    if hasFlag(args, "--check") {
        emit(TrayController.shared.checkJSON())
        return 0
    }
    return TrayController.shared.run()
}
