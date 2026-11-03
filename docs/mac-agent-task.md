# 派给 Mac 上 DSH Agent 的任务书（可直接粘贴）

> 用途：Windows 这边通过 SSH 无法驱动 Mac 上的 DSH（只有 GUI App，没有 `dsh` CLI 可执行文件）。
> 在 Mac 上打开 DeepSeek Harness，新开会话，把下面「任务」整段粘进去即可。
> 仓库已克隆好：`~/desktop-director`（git bundle 导入，含 0.1.1）。

## 任务（复制以下全部内容）

你在一台 Apple Silicon Mac（macOS 15.7.3，逻辑屏 1680×1050 points，Swift 6.2.3 可用）上工作。
仓库在 `~/desktop-director`。目标：实现 **ddir 的 macOS 后端**，命令集与 Windows 版完全一致，并通过 `selftest`。

### 背景（已经实测确认，别重新试错）

- 窗口枚举/摆放用 **Accessibility API**：`AXUIElementCreateApplication(pid)` → `AXWindows` → `AXPosition` / `AXSize` / `AXTitle`
- **AX 写权限已授权**：App 必须位于 `/Users/<user>/Applications/Ddir.app`，bundle id `com.ddir.mac`，用 `~/.ddir-sign` 里的 `ddir-dev` 自签证书签名（`codesign --force --deep --keychain ~/.ddir-sign/ddir.keychain-db -s ddir-dev ...`）。**不要换 bundle id 或路径**，否则 TCC 授权失效，需要人工重新授权。
- `close` 用 AX 关闭按钮（`kAXCloseButtonAttribute` + `AXPress`）：**关窗口不退进程**；`quit` 不是 close 的别名，先不要实现。
- `hide` 只能用应用级（`kAXHiddenAttribute` 置 true）；`NSRunningApplication.hide()` 实测无效。
- 空闲：`CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`
- 显示器：`CGGetActiveDisplayList`，坐标是 **points**（不是像素）
- 屏幕录制权限已授权，缩略图以后再做

### 交付（v0.1，别做多）

新建 `mac/` 目录，Swift 实现，导出这些子命令，JSON 输出与 Windows 版同构：

```
mac/ddir macos mode [off|semi|auto]
mac/ddir macos displays
mac/ddir macos list [--text]
mac/ddir macos status
mac/ddir macos plan [--needs "a,b"]     # 只算不做
mac/ddir macos claim [--needs "a,b"] [--force]
mac/ddir macos move --window <pid:index 或 hex> --rect x,y,w,h [--force]
mac/ddir macos hide|show --window <id>
mac/ddir macos close --window <id>       # AX 关闭按钮，3 秒内没关返回 close_blocked
mac/ddir macos own --app <name> | disown --app <name>
mac/ddir macos release
mac/ddir macos selftest
```

要求：

1. **`claim` 必须重排**：把本 Agent 已持有的窗口 + 本次新增窗口一起做**等宽并排**（1/2/3 列，间隔 16px），返回 `retiled: true` 标出旧窗口；超过 3 个返回 `quota_exceeded`。这是最新需求，Windows 版已实现，照抄语义。
2. 租约/状态文件放 `~/.ddir/`，格式参考 `src/store.rs`（TSV）：`leases.tsv` / `apps.tsv` / `audit.tsv` / `mode.txt`。
3. 窗口标识：macOS 没有 hwnd，用 `pid:CGWindowNumber`（例如 `1234:56789`）作为 `window` 字段；AX 操作时用 pid 找应用、用 `AXWindows` 下标或 `AXWindowNumber` 匹配（若取不到窗口号，退化为 pid:index）。
4. `selftest` 输出 7 项 PASS/FAIL：displays≥1、managed≥1、windows>0、geometry sane、mode valid、idle readable、work area>0。退出码非 0 表示失败。
5. **自己测试**：用 TextEdit 开一个文档窗口，跑 `move_abs`（240,160）→ 读回坐标 → `release` 还原；再测 `claim` 两个窗口并排、`release` 还原。把结果贴在你的回答里。
6. 提交代码：`git add -A && git commit -m "feat(mac): ..."`（Conventional Commits）。**不要**把 `~/.ddir` 或证书提交进仓库。
7. 推送：如果 `git push` 成功就推；失败就算了（网络问题），在回答里说明本地 commit hash。

### 约束

- 不要动用户正在用的窗口（Obsidian / 终端 / 系统设置）；测试只用 TextEdit。
- 不要改 `bundle id` / App 路径 / 证书。
- 不要实现 HUD、托盘、自动关闭倒计时——那是后续里程碑。
- 完成后用 6 行以内报告：实现了哪些命令、selftest 结果、TextEdit 测试结果、commit hash、push 是否成功。
