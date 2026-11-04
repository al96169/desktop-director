# Mac 上继续开发 · 任务书（v0.7.2 基线）

> 给 Mac 上的 DSH Agent。仓库已在这台机器上（`~/desktop-director`，可能是旧快照）。
> 目标：实现 **ddir 的 macOS 后端**，命令集/JSON 与 Windows 版一致，并通过 `selftest`。

## 0. 先同步代码

```bash
cd ~/desktop-director && git log --oneline -1
# 如果是旧版本（不是 0.7.x），用下面两种方式之一同步：
#   a) git pull        （GitHub 通的时候）
#   b) 让 Windows 侧导一个 git bundle 过来：
#      git bundle create ddir.bundle --all      # Windows 上执行
#      scp ddir.bundle mac:/tmp/ && git clone /tmp/ddir.bundle ~/desktop-director
```

## 1. 当前 Windows 版已经有什么（照着对齐即可）

```
ddir mode [off|semi|auto]                 档位；off 时 move/hide/close/claim 返回 mode_off
ddir displays [--manage UID [--off]]      托管屏（uid 用设备名，如 \\.\DISPLAY1）
ddir list [--text]                        窗口列表（Alt-Tab 级过滤）
ddir status                               JSON：mode/leases/windows/owns/focus_holder/input_age_s/user_active
ddir plan|claim [--needs "a,b"] [--force] [--priority P] [--present paced]
ddir move --window ID --rect x,y,w,h [--force]
ddir hide|show --window ID                hide 记租约，release 恢复
ddir close --window ID                    只关自己 own 过的，WM_CLOSE + 3s → close_blocked
ddir own|disown --app NAME
ddir release                              还原我的租约（位置/隐藏）
ddir heartbeat                            续租（TTL 300s）
ddir focus [--seconds N] | focus release  焦点令牌
ddir auto status|plan|on|close|undo       auto 管线（默认 auto_close=off）
ddir config [k v] / ddir log [--lines N] / ddir flush / ddir demo / ddir tray / ddir autostart
ddir selftest                             7 项平台自检
```

状态目录 `~/.ddir/`：`mode.txt`、`leases.tsv`、`apps.tsv`、`audit.tsv`、`config.ini`、`ddir.log`、`queue/*.op`。
**格式要与 Windows 版一致**（TSV，字段见 `src/store.rs`），这样两边行为可以对照。

## 2. 你要写的（`mac/` 目录，Swift）

优先级从高到低：

1. `selftest`（7 项：displays≥1 / managed≥1 / windows>0 / geometry sane / mode valid / idle readable / work area>0）
2. `mode` / `displays` / `list` / `status`（只读先跑通）
3. `claim` / `plan`（等宽列并排；重排本 Agent 已占窗口；`retiled` 标记）
4. `move` / `hide` / `show` / `release`
5. `close`（AX 关闭按钮）/ `own` / `disown`
6. `heartbeat` / `focus`（直接复用 Windows 的文件语义即可）

输出必须是 JSON（一行），字段名与 Windows 版一致（见 `docs/protocol.md`）。

## 3. 已验证的 macOS 事实（别重新试错）

| 事实 | 说明 |
|---|---|
| 枚举/摆放 | Accessibility API：`AXUIElementCreateApplication(pid)` → `AXWindows` → `AXPosition`/`AXSize` |
| 隐藏 | `AXHidden` 属性可用；`NSRunningApplication.hide()` 实测无效，别用 |
| 关闭 | 按 `AXCloseButton`：**关窗口不退进程**；不要用 `terminate()` |
| 坐标 | 全部是 **points**（这台机器 1680×1050 逻辑分辨率） |
| 空闲 | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)` |
| 窗口标识 | macOS 没有 hwnd，用 `pid:CGWindowNumber`（取不到就用 `pid:index`），字段仍叫 `window` |
| **签名** | App 必须在 `/Users/<user>/Applications/Ddir.app`，bundle id `com.ddir.mac`；用 `~/.ddir-sign/ddir.keychain-db` 里的 `ddir-dev` 证书签名。**换路径/换签名会让 TCC 授权失效**，需要用户在 GUI 重新授权 |
| **TCC** | 辅助功能 + 屏幕录制授权已给 `com.ddir.mac`；SSH 启动的进程不继承 Terminal 的授权，所以必须走 `.app` |

签名的固定命令：

```bash
security unlock-keychain -p ddir ~/.ddir-sign/ddir.keychain-db
codesign --force --deep --keychain ~/.ddir-sign/ddir.keychain-db -s ddir-dev "$HOME/Applications/Ddir.app"
```

## 4. 测试要求（写进你的回答）

1. `./ddir-mac selftest` → 7/7 PASS
2. `ddir list` 能看到至少 3 个 App 的窗口，标题非空
3. TextEdit 打开一个临时文件 →
   - `move --rect` 后读回位置一致（误差 ≤1pt）
   - `hide` 后窗口不可见，`release` 后恢复
   - `close` 后窗口消失、进程仍在
4. `claim --needs "a.txt"` 两个窗口 → 等宽并排；`release` 还原

不要在用户的 Obsidian / 终端 / 系统设置上做测试，只用 TextEdit 和你自己开的窗口。

## 5. 约束

- 不改 `bundle id`、不改 App 路径、不重新生成证书
- 不实现 HUD / 托盘 / 自动关闭倒计时（后续里程碑）
- 提交用 Conventional Commits；**本地 commit 后在回答里报 hash**；GitHub 能 push 就 push，push 失败不影响
- 不把 `~/.ddir`、证书、`.app` 提交进仓库

## 6. 回答格式（6 行以内）

```
实现：selftest/mode/displays/list/status/claim/move/hide/release/close/own
selftest：7/7 PASS
TextEdit：move 177,73→240,160 读回 240,160；hide ✓；release ✓；close ✓（进程存活）
并排：2 窗口 936+936，release 还原
commit：<hash>
push：成功/失败（原因）
```
