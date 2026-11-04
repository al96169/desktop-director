# Changelog

## 0.4.1 - 2026-11-04

- `auto undo` 现在会恢复该应用**全部**被最小化的窗口（之前只恢复第一个）

## 0.4.0 - 2026-11-04

### 配置：auto 档是否动窗口（默认 off）

- 新增 `~/.ddir/config.ini`：`auto_close = off | minimize | close`，默认 **off（永不自动关窗口）**
- `auto_close=minimize`：用最小化代替关闭，`ddir auto undo` 会把窗口恢复
- `auto_close=close`：保留原来的 `WM_CLOSE` 管道（需先武装）
- `countdown_seconds` 可配（默认 10）
- `ddir config` / `ddir config auto_close minimize`

### 日志

- `~/.ddir/ddir.log`：每条命令一行（本地时间 + 动作），`ddir log --lines N` 查看
- 托盘右键新增「查看日志」「自动关闭 ▸ off/minimize/close」
- 超过 2MB 自动轮转为 `ddir.log.1`

## 0.3.1 - 2026-11-04

- `auto on` 默认倒计时 30s -> **10s**
- 倒计时期间**随时切回 semi/off 即取消武装**（每 250ms 检查一次模式），并写 `auto_abort` 审计
- `auto on` 现在要求当前已经是 auto 档，否则返回 `mode_not_auto`

## 0.3.0 - 2026-11-04

### auto 武装 / 处决 / 撤销（M2.5 骨架）

- `ddir auto plan`：列出候选（排除前台、被 Agent 认领的、explorer、ddir 自身）
- `ddir auto on --seconds N`：N 秒倒计时后武装（1 小时有效），Ctrl+C 取消
- `ddir auto close --app <名字>`：只对指定目标发 `WM_CLOSE`、等 3 秒；没关掉记 `close_blocked` 不重试
  - 不带 `--app` 默认拒绝（`needs_explicit_target`），必须加 `--force` 才允许自动挑（最多 3 个）
- 关闭前记录 exe 路径 + 窗口位置到 `~/.ddir/closed.tsv`
- `ddir auto undo`：重新拉起刚关掉的软件并把窗口摆回原位置
- 未武装时 `auto close` 返回 `needs_user_consent`

## 0.2.0 - 2026-11-04

### Rust 原生托盘（M3）

- `ddir tray`：Win32 Shell_NotifyIcon，单实例（命名互斥体），7.8 MB 内存（旧 PowerShell 预览版约 40 MB）
- 右键菜单：状态 / 模式（off·semi·auto，带勾选）/ 全部还原 / 窗口列表（前 8 个）/ 开机自启 / 打开项目目录 / 退出
- 每 3 秒刷新 tooltip：`ddir - <mode> - <n> lease(s)`
- `ddir autostart on|off|status`：写入/删除 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- 双击托盘图标弹气泡状态

### 其它

- 托盘与 CLI 共用 `~/.ddir` 状态：CLI 切模式，托盘下一次刷新即同步
- 保留 `tools/ddir-tray.ps1` 作为预览/对照实现

## 0.1.1 - 2026-11-04

### 并排，不再叠放

用户反馈：新窗口摆上去会把旧窗口压到底部、内容被遮住。

- `claim` 现在是**重排**：把本 Agent 已持有的窗口和本次新增窗口一起做**等宽并排**
  （1 个=满宽 / 2 个=各半 / 3 个=各 1/3，间隔 16px），返回里 `retiled: true` 标出被重排的旧窗口
- 超过 3 个窗口返回 `quota_exceeded`
- `release` 仍然还原到每个窗口**最初**的位置（不是上一次重排后的位置）
- 提示词升级 v1.3：明确要求"并排、不叠放"，并说明一次 claim 要说全需要的窗口

## 0.1.0 - 2026-11-04

首个可用版本：**Windows 单文件 CLI**（338 KB，无运行时依赖）。

### 能用

- `ddir list` / `displays` / `status` / `board` / `selftest`
- `ddir claim` / `plan`（干跑）/ `move` / `hide` / `show` / `release`
- `ddir own` / `disown` / `close`（只关自己认领过的：`WM_CLOSE` + 3s + `close_blocked`）
- 窗口租约**排他**（I1 单写者）：别人持有的窗口返回 `window_owned_by`
- 用户活跃判定：光标位移 >25px 或前台窗口变化（`input_text` 原始值同时上报）
- 三档模式：`off` / `semi` / `auto`（当前实现 semi 语义；auto 的武装倒计时未做）
- 屏幕托管策略：≥2 屏时托管"除主屏外全部"，单屏时托管该屏；新屏默认归用户

### 已知限制

- 仅 Windows 后端；macOS 已完成能力验证（AX 可摆窗口、TCC 要求），实现待做；Linux 仅设计
- 无常驻 daemon / 托盘 / HUD（M3/M4）
- 多 Agent 仲裁只有"排他"，没有优先级与抢占（M5 剩余）
- `close` 是关闭窗口，不是退出应用；macOS 需要区分 `quit`

### 参考实现

`tools/ddir.ps1` 是早期 PowerShell 版本，保留作行为对照，已被 Rust 版取代。