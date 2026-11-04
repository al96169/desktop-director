# macOS 后端（0.7.3）

> 实现位置：`mac/`（Swift 6，直接用 `swiftc` 编译，无 SPM 依赖、无第三方库）。
> 命令集、JSON 字段、状态目录与 Windows 版 `src/` 对齐；能力差异按 `docs/platforms.md` 如实上报。
> 这份文档记录"怎么做的、为什么这么做、哪些不能做"，避免下一个 Agent 重新试错。

## 1. 现状

| 能力 | 状态 |
|---|---|
| `selftest`（7 项） | ✅ 7/7 PASS |
| `mode` / `displays` / `list` / `status` | ✅ 只读全通 |
| `claim` / `plan`（等宽并排、`retiled`、抢占、配额） | ✅ 1–3 列，`release` 像素级还原 |
| `move` / `hide` / `show` / `release` | ✅ 坐标是 points；`hide` 应用级 |
| `close`（AX 关闭按钮）/ `own` / `disown` | ✅ 关窗不退进程；`not_owned` / `owned_by_other` 照旧 |
| `heartbeat` / `focus` / `config` / `log` / `board` / `flush` | ✅ 与 Windows 同一份文件语义 |
| `auto status|plan|on|close|undo` | ✅ 基于 TextEdit/Finder 实测；`auto_close=off` 仍是默认 |
| `demo` | ✅ TextEdit 版（自己开、自己关） |
| `tray`（NSStatusItem：三档/还原/auto_close/窗口/托管屏/日志/自启/退出） | ✅ 菜单栏常驻，3s tick 消费 `paced` 队列 + 越权关闭检测 |
| `autostart`（LaunchAgent） | ✅ `on/off/status`，`launchctl bootstrap/bootout` |
| HUD（缩略图墙/暗化/入场动画） | ❌ 未做；需要 ScreenCaptureKit + 屏幕录制授权 |
| 托管屏"借用"、热插拔回滚 | ❌ 未做（与 Windows 同步的欠账） |

## 2. 托盘与开机自启

```bash
ddir tray                # 菜单栏图标（◐ semi / ● auto / ○ off），单实例（flock）
ddir tray --check        # 不启动常驻进程，只把 NSMenu 树打成 JSON（给测试/自动化用）
ddir autostart on|off|status   # ~/Library/LaunchAgents/com.ddir.mac.tray.plist
```

菜单：`状态行` / `模式 ▸ off·semi·auto` / `全部还原（所有人）` / `自动关闭 ▸ off·minimize·close` /
`窗口列表 ▸`（点一条即 raise + 激活）/ `托管屏 ▸`（勾选=托管）/ `查看日志` / `打开状态目录` /
`开机自启`（勾）/ `退出`（⌘Q）。图标旁一直显示当前档位，动作后短暂显示 `还原 N` / `auto:close` 之类的反馈。

设计要点：

- **托盘代表人，不代表某个 Agent**：`全部还原` 用 `releaseAll(force: true)` 恢复**所有 Agent** 的活跃租约；
  CLI 的 `ddir release` 仍然只释放自己的（D22）。托盘进程的身份与 CLI 的宿主进程无关，若按身份过滤，
  按钮会变成空操作（下一个坑已踩过）。
- **单实例**：`~/.ddir/tray.lock` 上加 `flock(LOCK_EX|LOCK_NB)`，进程退出内核自动释放；
  第二个实例返回 `{"ok":false,"error":"already_running"}`，不弹窗。
- **3s tick**：消费 `presentation=paced` 队列（实测：claim 入队后不调用 `flush`，托盘在 3s 内把窗口摆好）、
  跑 `unmanaged_kill` 检测（窗口消失且无 20s 内 close 审计 → 记审计；`downgrade_on_unmanaged_kill=true` 时降 semi）。
- **开机自启**是 `~/Library/LaunchAgents/com.ddir.mac.tray.plist`（`RunAtLoad`，`launchctl bootstrap gui/$UID`），
  不是 `loginwindow` 脚本；首次开启时 macOS 会弹「后台项目已添加」，属正常。关掉 = `bootout` + 删 plist。
- LaunchAgent 启动的进程同样拿到辅助功能授权（实测 `accessibility=true`，能看到 8 个窗口）：
  TCC 认签名身份，不认启动方式。

## 3. 构建 / 安装 / 自测

```bash
cd ~/desktop-director
./mac/build.sh              # swiftc -> Ddir.app -> codesign(ddir-dev) -> ~/.local/bin/ddir
./mac/build.sh --no-install # 只编译（产物 mac/build/ddir-mac）
./mac/test.sh               # 15 项验收（TextEdit，只用自己开的窗口）
```

* App 固定在 `~/Applications/Ddir.app`，bundle id `com.ddir.mac`，可执行文件 `Contents/MacOS/Ddir`。
  TCC（辅助功能）授权认的是**代码签名身份**（`com.ddir.mac` + `ddir-dev` 证书），所以重编译重签不掉权限；
  **换证书、换 bundle id、或改成 ad-hoc 签名会掉**，需要用户在系统设置里重新勾选。
* 命令入口：`~/.local/bin/ddir` → `exec ~/Applications/Ddir.app/Contents/MacOS/Ddir "$@"`。
* 只读命令（`list`/`displays`/`status`/`selftest`）在未授权时仍可用；所有写命令返回 `permission_required`。

## 4. 平台事实（实测，别再试错）

| 事实 | 细节 |
|---|---|
| 枚举/摆放 | `AXUIElementCreateApplication(pid)` → `AXWindows` → `AXPosition`/`AXSize`；全部 **points**，原点在主屏左上角（与 CG 同一坐标系）|
| 窗口标识 | macOS 没有 HWND。`window` 字段为 `pid:CGWindowNumber`，取不到时退回 `pid:index`。CGWindowNumber 通过 `CGWindowListCopyWindowInfo(.optionAll)` 按 pid + 几何（±8pt）+ 标题配对；**一个 CG 号只能配一个 AX 窗口**（两个文档可以标题与几何完全相同，早期版本在这里出过重复 ref）|
| 隐藏 | 只能**整应用**：`kAXHiddenAttribute`（`caps.window_hide="app"`）。`NSRunningApplication.hide()` 不可靠，仅作失败兜底；`release` 恢复整应用 |
| 关闭 | 按 `kAXCloseButton`，窗口消失、**进程存活**（与 Windows `WM_CLOSE` 不同）。3 秒内窗口没消失 → `close_blocked` |
| 最小化 | `kAXMinimizedAttribute`（`auto_close=minimize` 用）|
| 全屏 | 写几何前若 `AXFullScreen=true` 先退出全屏，否则 AX 会忽略位置写入 |
| 应用名 | 用 bundle 可执行名（`TextEdit`），与 Windows 的 exe 名语义一致；`own`/`close` 同时接受本地化名（`文本编辑`）与 bundle id |
| 空闲 | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: rawValue ~0)` |
| 前台 | `NSWorkspace.frontmostApplication` + 该 app 的 `AXFocusedWindow`，拼成 `pid:cgwin` |
| Agent 身份 | 父进程链顶端宿主（DSH / Terminal / IDE），格式 `Name-pid`，空格换成 `_`；`DDIR_AGENT` 可覆盖（D18）|
| 授权归属 | TCC 辅助功能按**签名身份**判定：同一签名二进制即使被拷到 `/tmp` 仍 `accessibility=true`（实测）；屏幕录制当前 `false`，做 HUD 前要重新勾选 `Ddir` |
| 显示器 | `NSScreen`（左下原点）→ CG（左上原点）换算 `y = mainHeight - (y + h)`；`work` 取 `visibleFrame`（菜单栏 25pt、Dock 已扣除）|

## 5. 与 Windows 版的差异（协议已表达，别当成 bug）

| 项 | Windows | macOS |
|---|---|---|
| `window` 值 | `0x001A2B3C` | `pid:CGWindowNumber`（如 `75098:7449`）|
| `hide` 粒度 | 单窗口 | 整应用（`scope:"app"`）|
| `close` 后进程 | 通常退出 | 一定存活 |
| `class` 字段 | Win32 类名 | AX subrole（`AXStandardWindow` 等）|
| `dpi` | 96/120/144… | `72 × backingScaleFactor`（Retina 144），另有 `scale` 字段 |
| 托盘 / 自启 | Rust 原生托盘 + HKCU Run | NSStatusItem + LaunchAgent |
| `auto` 的候选过滤 | explorer / 前台 / 已认领 | Finder / 前台 / 已认领 |
| `demo` | notepad | TextEdit |

JSON 里额外提供了 `actual`（move 后的读回值）、`hidden`、`pid`、`scale`、`process_alive` 等字段；只增不改，Windows 客户端可忽略。

## 6. 已知边界

1. **AX 只对"有窗口的 app"有效**：菜单栏常驻 / 后台进程没有窗口，`list` 看不到（与 Alt-Tab 一致）。
2. **同一文档开两个窗口**时标题与几何可能完全相同；现在靠 CGWindowNumber 唯一性区分，`close` 一次只关一个。
3. **TextEdit 会自动保存**（NSDocument autosave），所以很难复现 `close_blocked`；该分支已实现（3 秒轮询 + 不重试），
   在真实弹保存面板的 app 上会正常返回。
4. **`hide` 的应用级语义**意味着"藏一个窗口"在 macOS 上做不到；`release` 会把该应用所有隐藏窗口一起恢复。
5. **不动用户的屏**：单屏时按 D15 回退为"托管这块屏"，`claim` 仍会避开前台窗口与用户活跃时段（`user_active`）。
6. **HUD 未做**：需要屏幕录制授权（当前 `screen_recording=false`），先补授权再上 ScreenCaptureKit。
7. **`tray` 必须跑在 GUI 会话里**（`launchctl` 的 gui/$UID 域）。SSH 里直接 `ddir tray` 能起来但图标不显示，
   因为不在同一个 session；排障时用 `launchctl print gui/$(id -u)/com.ddir.mac.tray` 看状态。
8. **Windows 的托盘 `全部还原` 有同样的身份问题**（`src/tray.rs` 调 `release_all()`，只释放托盘进程自己的租约）。
   macOS 侧已用 `force: true` 修正；Windows 侧待确认/修复。

## 7. 下一步（按优先级）

1. HUD：ScreenCaptureKit 抓窗 → 缩略图墙 + 暗化 + 入场动画（先补屏幕录制授权）。
2. 借用屏 / 热插拔回滚（与 Windows 同步欠账）。
3. 软件所有权到进程级（当前粒度是应用名）。
4. 托盘补充：显示"最近接管/关闭"历史、auto 武装倒计时状态；Windows 侧 `release_all` 同款修复。
