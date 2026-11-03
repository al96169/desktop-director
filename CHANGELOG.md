# Changelog

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