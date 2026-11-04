# 多平台支持（Windows / macOS / Linux）

> 2026-11-03 · 需求变更为"三平台"，本文固定各平台的可做与不可做，避免后面拿 Windows 的经验去承诺做不到的事。
> 结论先行：**同一套协议 + 每平台一个后端**；Windows 全功能、macOS 基本可用（需授权）、Linux 分 X11 与 Wayland 两档。

## 0. 一句话

协议与仲裁逻辑（`ddir-core`）**一份**；窗口/显示器/进程/焦点这些"脏活"**每平台一份**。daemon 启动时自报 `caps`，Agent 按 `caps` 决定策略——而不是让 Agent 去猜"这台机器能不能隐藏窗口"。

## 1. 能力矩阵

| 能力 | Windows | macOS | Linux / X11 | Linux / Wayland |
|---|---|---|---|---|
| 枚举窗口 | ✅ `EnumWindows` + 过滤链 | ✅ `CGWindowListCopyWindowInfo`（标题需屏幕录制权限） | ✅ EWMH `_NET_CLIENT_LIST` | ⚠️ 仅 `wlr-foreign-toplevel`（合成器支持才行） |
| 移动/缩放 | ✅ `SetWindowPos` | ✅ AX `kAXPositionAttribute`/`kAXSizeAttribute`（需辅助功能权限） | ✅ `_NET_MOVERESIZE_WINDOW` | ❌ 通用协议没有；仅合成器 IPC（Hyprland/KWin） |
| 显示/隐藏 | ✅ `ShowWindow`（窗口级） | ⚠️ `NSRunningApplication.hide()`（**应用级**，不是窗口级） | ⚠️ unmap 或 `_NET_WM_STATE_HIDDEN`（各家 WM 行为不一） | ❌ |
| 激活/抢焦点 | ⚠️ `SetForegroundWindow`（受前台锁限制） | ✅ AX `kAXRaiseAction` + `NSRunningApplication.activate` | ✅ `_NET_ACTIVE_WINDOW` | ❌ |
| 优雅关闭 | ✅ `WM_CLOSE` | ✅ AX 按关闭按钮 / `NSRunningApplication.terminate()` | ✅ `_NET_CLOSE_WINDOW` | ⚠️ 合成器 IPC |
| 用户空闲 | ✅ `GetLastInputInfo`（本机需叠加光标判据） | ✅ `CGEventSourceSecondsSinceLastEventType` | ✅ XScreenSaver idle | ⚠️ `ext-idle-notify`（合成器支持） |
| 显示器枚举 | ✅ `EnumDisplayMonitors` + `QueryDisplayConfig`（稳定 uid） | ✅ `CGGetActiveDisplayList` + display serial | ✅ XRandR | ⚠️ `wlr-randr`/合成器 |
| 缩略图（HUD） | ✅ `DwmRegisterThumbnail` | ✅ ScreenCaptureKit（`CGWindowListCreateImage` 已弃用） | ✅ XComposite | ⚠️ 合成器相关（Hyprland 可 layer-shell；GNOME 不行） |
| 提权/高权限窗口 | ❌ UIPI 隔离 | ⚠️ 需 Accessibility；部分系统窗口拒绝 | ⚠️ 其他用户/Wayland 安全模型 | — |

图例：✅ 完整；⚠️ 可用但有语义差异或前置条件；❌ 做不到（必须在 `caps` 里如实报告）。

## 2. 各平台实现要点

### 2.1 Windows（已有参考实现）

- 枚举过滤链：`IsWindowVisible` → 非 `WS_EX_TOOLWINDOW` → `GA_ROOTOWNER==self` → `DWMWA_CLOAKED==0` → 有标题 → 类名黑名单
- 几何：展示用 `DWMWA_EXTENDED_FRAME_BOUNDS`，落盘/还原用 `GetWindowRect`（差 7–8px，实测过）
- 前台锁：`SetForegroundWindow` 有系统规则，semi 永不抢焦点
- 权限：UIPI，管理员窗口只能枚举不能动；`GetLastInputInfo` 会被本机鼠标注入污染（D19）

### 2.2 macOS

- **枚举**：`CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`；拿 `kCGWindowOwnerPID` + `kCGWindowNumber`；窗口标题在 10.15+ 需要**屏幕录制**权限，否则为空 → 用 `kCGWindowOwnerName` 兜底
- **摆放**：`AXUIElementCreateApplication(pid)` → `AXWindows` → 对目标窗口设 `AXPosition`（AXValue 包装的 CGPoint）与 `AXSize`。失败常见原因：App 不支持 AX（如部分 Electron/游戏）、窗口被 App 固定尺寸
- **隐藏**：macOS 没有"隐藏单个窗口"的通用 API。两条路：
  1. `NSRunningApplication.hide()` —— **应用级**，会把该 App 所有窗口一起藏起来；
  2. `AXMinimize`（最小化到 Dock）—— 窗口级，但视觉上是"进 Dock"不是"消失"。
  → 协议里 `hide` 必须带 `scope: "window" | "app"`，macOS 只能满足 `app`
- **关闭**：按下 `AXCloseButton`（等价点红叉，会触发"是否保存"弹窗）或 `terminate()`（更粗暴，跳过保存）→ 只用前者，后者列为 `force` 且默认禁用
- **空闲**：`CGEventSourceSecondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)`
- **显示器**：`CGGetActiveDisplayList` → `CGDisplayCreateUUIDFromDisplayID` 作稳定 id；分辨率用 `CGDisplayBounds`
- **HUD**：ScreenCaptureKit 抓窗口流（需要屏幕录制权限），或 `CGWindowListCreateImage`（macOS 14 起弃用）
- **权限（TCC，最大的坑）**：
  - **辅助功能**（Accessibility）：摆窗口、按关闭按钮必需
  - **屏幕录制**（Screen Recording）：读窗口标题、抓缩略图必需
  - **自动化**（Automation）：仅走 AppleScript 路线时需要
  - 这三项**只能在本机 GUI 里授权**，SSH 远程无法代授；授权后需要重启被授权的进程
  - 检测：`AXIsProcessTrusted()`；未授权时 `caps` 报 `accessibility: false`，daemon 以只读模式运行

- **⚠️ 通过 SSH 启动的进程，不享受 Terminal 的 TCC 授权**：TCC 按"责任进程"归属，`sshd → bash → ddir-mac` 这条链上的授权对象是 `sshd`/二进流本体，给 Terminal.app 打钩没用。远程调试时会看到 `-1743 (not authorized to send Apple events)` 或 AX 操作全部失败，即使你已经给终端授权了。
  → 正确做法：**macOS 后端做成一个 `.app` bundle + LaunchAgent**（登录后在 GUI 会话里常驻），TCC 授权打在这个 bundle 上，只授权一次、长期有效；SSH 只用来构建、看日志、触发 CLI（CLI 通过自建的本地 socket 找 daemon，而不是自己去碰 AX）。

### 2.3 Linux

按会话类型分档，**daemon 启动时检测 `XDG_SESSION_TYPE`**：

| 会话 | 做法 | 结论 |
|---|---|---|
| **X11** | EWMH：`_NET_CLIENT_LIST` 枚举、`_NET_MOVERESIZE_WINDOW` 摆放、`_NET_ACTIVE_WINDOW` 激活、`_NET_CLOSE_WINDOW` 关闭；显示器用 XRandR | 与 Windows 同级，**首选支持** |
| **Wayland · Hyprland** | IPC socket：`hyprctl -j clients` 枚举、`dispatch movewindowpixel/resizewindowpixel`、`dispatch closewindow`；事件用 socket2 | 可用，但全是合成器私有协议 |
| **Wayland · KWin** | KWin 脚本（JS）经 DBus 调用，注入 `workspace.windowList()` 改 `frameGeometry` | 可用，需要用户启用脚本 |
| **Wayland · GNOME** | 没有通用窗口控制；GNOME Shell 扩展可行但成本高 | **不支持**，`caps` 全 false，只做"启动/观察" |
| **Wayland · 其他 wlroots** | `wlr-foreign-toplevel-management`（部分合成器实现，只能激活/关闭，不能摆放） | 半支持 |

- 关闭：X11 `_NET_CLOSE_WINDOW`；Hyprland `dispatch closewindow`；KWin `window.close()`
- 空闲：X11 `XScreenSaverQueryInfo`；Hyprland `idleinhibitor`/`ext-idle-notify`；GNOME 无
- HUD：X11 用 XComposite 取窗口 pixmap 画到 override-redirect 窗口；Wayland 只能 layer-shell（Hyprland 支持）
- 提权/多用户：Linux 没有 UIPI 那套，但 Wayland 的安全模型直接等于"不给"，X11 则相反（任何客户端都能读别人的窗口）

## 3. 协议改动（向后兼容）

```jsonc
// ddir status / mode 增加：
{
  "platform": "windows|macos|linux-x11|linux-wayland-hyprland|linux-wayland-kwin|linux-wayland-other",
  "caps": {
    "window_move": true, "window_hide": "window|app|false", "window_close": true,
    "focus_control": true, "display_enumerate": true, "thumbnail": true,
    "idle_signal": "input|cursor|none", "accessibility": true, "screen_recording": true
  }
}
```

- Agent 侧策略：`caps.window_hide != "window"` → 不要指望"只藏一个窗口"；`caps.window_move == false` → 放弃摆窗口，只在回答里说明
- 错误码新增：`unsupported_on_platform`、`permission_required`（macOS TCC）、`compositor_unsupported`

## 4. 一致性与验收：一个可执行的 conformance 套件

跨平台最大的风险不是"做不到"，而是"以为做到了"。所以每个后端都要跑同一套 `ddir selftest`：

| 用例 | 期望 |
|---|---|
| `list` 与系统任务栏/Alt-Tab 一致 | 差 ≤1 |
| 摆窗口后 `list` 读回几何 | 误差 ≤2px（macOS AX 可能有 1px 取整） |
| `hide` 的 scope 与 `caps` 一致 | 声明 `app` 就不能声称窗口级 |
| `close` 对未保存文档 | 返回 `close_blocked`，进程存活 |
| `own`/`release` 排他性 | 第二个 Agent 收 `window_owned_by` |
| 未授权时（macOS 关掉 Accessibility） | `caps.accessibility=false`，所有写操作返回 `permission_required` |

`ddir selftest --json` 输出逐条 pass/fail，作为每个平台的发布门槛。

## 5. 里程碑调整

| 新增 | 内容 | 估时 |
|---|---|---|
| **M5.5** | 协议加 `platform`/`caps` + `ddir selftest` 套件 + 后端 trait 抽出（`ddir-core` 保持零平台依赖） | 3–4 人日 |
| **M7** | macOS 后端（AX 摆放/关闭/空闲 + TCC 检测 + 只读降级） | ✅ 0.7.3 完成（见 [macos-backend.md](macos-backend.md)）；托盘/HUD 待做 |
| **M8** | Linux X11 后端（EWMH） | 4–6 人日 |
| **M9** | Wayland：Hyprland IPC → KWin 脚本；GNOME 明牌不支持 | 5–8 人日 |

**顺序建议**：M5.5 先做（否则每个平台都会各写一套私有语义）→ Windows 收尾 → macOS（你手上有机器）→ Linux X11 → Wayland 按需。

## 6. macOS 远程协作（你这台 Mac 怎么接进来）

要在 Mac 上跑和验证 `ddir-mac`，需要三件事：

1. **SSH 通道**（我来执行命令、看日志）：
   - Mac：系统设置 → 通用 → 共享 → **远程登录** 打开；记下 `ssh 用户名@局域网IP`
   - 建议为测试建一个专用用户，或至少确认允许密码/密钥登录
2. **无法用 SSH 代授的 TCC 权限**（必须你在 Mac 前点一下）：
   - 系统设置 → 隐私与安全性 → **辅助功能**：把运行 `ddir-mac` 的终端/iTerm 加进去
   - 同页 → **屏幕录制**：同上（读窗口标题、抓缩略图需要）
   - 授权后**重启那个终端**，否则不生效
3. **一根"能看到屏幕"的通道**（可选，排障用）：系统设置 → 共享 → **屏幕共享**，或直接让我用 SSH 跑 `screencapture` 截图回传（需屏幕录制权限）

我这边需要的全部信息：`ssh 用户名@IP`、你的 Mac 是否 Apple Silicon、macOS 版本（`sw_vers` 一条命令即可）。
拿到之后我可以先在 Mac 上跑只读探针（枚举窗口/显示器/权限状态），确认 `caps` 再决定先做哪一块。

### 6.1 实践进度（2026-11-03）

- 目标机：`user@192.168.1.x`（用户名带空格，命令行要写成 `"user"@192.168.1.x`）
- 22 端口已开、ping 通；服务器接受 `publickey,password,keyboard-interactive`
- 本机已生成密钥 `F:\envs\ssh\id_ddir`（ed25519，无口令），`~/.ssh/config` 里加了 `Host ddir-mac`
- **待办**：把公钥追加到 Mac 的 `~/.ssh/authorized_keys`（见下），之后统一用 `ssh ddir-mac` 免密登录

```bash
# 在 Mac 的 Terminal 里执行一次（公钥来自 F:\envs\ssh\id_ddir.pub）
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAA... ddir@windows' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> 提醒：即使 SSH 通了，`ddir-mac` 也不要由 SSH 直接启动（TCC 归属问题，见 §2.2）。先用 SSH 做构建、跑只读探针、看日志；真正带窗口控制能力的 daemon 用 `.app` + LaunchAgent 在 GUI 会话里跑。
