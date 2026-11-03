# macOS 实测记录（M1/M7 前置验证）

> 2026-11-03 · 目标机 `user@192.168.1.x` · macOS 15.7.3 · Apple M1 · 逻辑屏 1680×1050 points

## 环境

| 项 | 值 |
|---|---|
| SSH | `ssh ddir-mac`（ed25519 免密，`~/.ssh/config` 已配） |
| 编译 | Command Line Tools 已装，Swift 6.2.3，可直接 `swiftc` 出 `.app` |
| Homebrew | 无 |
| 屏幕 | 1 块，CG 逻辑坐标 `1680×1050`，面板 2560×1600（Retina 缩放）；**所有坐标是 points** |
| Python | 系统 3.9.6，无 pyobjc（所以探针用 Swift 写） |

## 权限（TCC）实测

| 权限 | 结果 |
|---|---|
| 屏幕录制 | ✅ 授权后 `CGPreflightScreenCaptureAccess()` 返回 true（窗口标题/缩略图需要） |
| 辅助功能 | ✅ 授权后 `AXIsProcessTrusted()` 返回 true；AX 可读可写 |
| **SSH 启动的进程** | ❌ 不继承 Terminal 的授权；必须把 **`.app` 本体**加入列表（这就是 daemon 要做成 `.app` 的直接证据） |
| **ad-hoc 签名 + 重建** | ❌ 每次重新 `codesign -s -` 都会让 TCC 失效（辅助功能与屏幕录制同时掉），必须重新授权 |

→ 正式开发要么固定签名证书（用户在本机信任一次自签证书），要么"一次构建、一次授权、配置驱动迭代"。当前探针走后者。

## 能力验证（`Ddir.app`，配置驱动）

| 操作 | 结果 |
|---|---|
| `caps` | `accessibility=true`、`screen_recording=true`、`window_hide="app"`、其余 true |
| `list` | ✅ AX 枚举出 9 个 App 的窗口，含**标题**（如"打开"）、role/subrole、坐标、尺寸 |
| `move`（AX `kAXPositionAttribute`） | ✅ `before 177,73` → 写入成功 → 还原成功（`set_err=0`、`restore_err=0`） |
| `move_abs 200,200` | ✅ 读回 `200,200`，确认是真实位移而不是假成功 |
| `close`（AX 关闭按钮） | ✅ 按下成功（`press_err=0`），**窗口关闭但进程仍在** —— 与 Windows 的 `WM_CLOSE`+"最后一个窗口关闭通常退出"不同 |
| `hide`（`NSRunningApplication.hide()`） | ❌ 返回 false（未生效）；改用 `AXHidden` 属性（`hide_ax`）验证（待复测） |
| `minimize`（AX `kAXMinimized`） | 待复测 |
| 空闲 | ✅ `CGEventSource.secondsSinceLastEventType` 正常 |

## 对协议/设计的影响

1. **`caps` 必须如实上报**：macOS `window_hide` 只能是 `"app"`（应用级），协议里已经是枚举而不是布尔。
2. **`close` 的语义要分开**：macOS 关窗 ≠ 退出进程。协议里 `close` 定义为"关闭窗口"，"退出应用"是另一个 op（`quit`），且默认禁用（可能丢未保存内容）。
3. **`hide` 用 AX 属性**，不用 `NSRunningApplication.hide()`（后者在后台/非激活 App 上不可靠）。
4. 坐标单位：macOS 全程 **points**；Windows 是像素。协议里的 `rect` 必须带单位语义（按平台解释），布局算法不能跨平台混用数值。
5. 稳定签名是 macOS 分发的必答题（见 `docs/toolchain.md` 与 D29）。

## 复用资产

| 文件 | 用途 |
|---|---|
| `tools/probe_mac.sh` | 只读探针（系统/权限/显示器） |
| `tools/probe_mac.swift` | CG/AX 只读探针（无签名要求，跑一次就知道 caps） |
| `tools/ddir_mac_probe.swift` | **配置驱动的 `.app` 探针**：`/tmp/ddir_cmd.json` → `/tmp/ddir_result.json`，支持 caps/list/move/move_abs/close/hide/hide_ax/show/activate/minimize/app_quit |
## 复测：全部能力打通（2026-11-04）

| 操作 | 结果 |
|---|---|
| `caps` | `accessibility=true`、`screen_recording=true`、`window_hide="app"`、其余 true |
| `move_abs 240,160` | ✅ 读回 `240,160`（`set_err=0`） |
| `hide_ax`（AX `AXHidden` 属性） | ✅ `set_err=0` —— **AX 隐藏可用，`NSRunningApplication.hide()` 不可用** |
| `activate` | ✅ 能把 App 唤到前台 |
| `close`（AX 关闭按钮） | ✅ 窗口关闭、进程存活（与 Windows 语义差异，协议已区分 `close` 与 `quit`） |

## 签名稳定性验证（关键）

用自签证书 `ddir-dev` 签名后，**重新编译二进制并重新签名，TCC 授权仍然有效**（`accessibility=true`、`screen_recording=true`）。

→ 结论：macOS 开发不再需要"每次重编译都让用户点授权"。做法：
1. `~/.ddir-sign/` 下自签证书（keyUsage=digitalSignature, EKU=codeSigning）
2. 导入独立 keychain（`ddir.keychain-db`，密码 `ddir`），`security import -T /usr/bin/codesign -A`
3. 用户在本机信任该证书（`security add-trusted-cert -r trustRoot -k <keychain> cert.pem`，或钥匙串访问里设为始终信任）
4. `codesign --force --deep --keychain <keychain> -s ddir-dev Ddir.app`
5. 首次给 App 授权一次，之后不变

> ad-hoc 签名（`codesign -s -`）每次重编译都会失效——这是之前反复掉权限的原因，已弃用。