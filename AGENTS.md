# AGENTS.md — Desktop Director（ddir）

本仓库是 **Desktop Director**：一个把 Windows 桌面当导播台、给多个 Agent 发「屏幕 / 窗口 / 软件」租约的工具。

## 给在本仓库里干活的 Agent（Claude Code / Codex / DSH / Trae / Cursor 等）

1. **先确认 ddir 是否存在**：`ddir mode`。
   - 命令不存在或返回 `off` → 忽略窗口编排，正常干活。
   - 返回 `semi` / `auto` → 按 `prompts/AGENTS.m0.md` 里的规矩管理窗口（**先读那个文件**）。
2. 窗口编排的硬规矩（简版，完整版见 `prompts/AGENTS.m0.md`）：
   - 只在 `ddir displays` 里 `managed=true` 的屏上摆放；用户屏一个像素都不碰
   - 一次最多 3 个窗口；多余的先 `ddir own` 再 `ddir hide`，结束 `ddir release --all`
   - 关闭只能 `ddir close --window <hwnd>`，且必须先 `own`；绝不 `taskkill` / `Stop-Process`
   - `--rect` 一定加引号：`--rect "0,0,1280,918"`
3. 改代码时：`docs/decisions.md` 是已定结论，别重新讨论；`docs/protocol.md` 是协议契约。
   macOS 的 window-id 是 `pid:CGWindowNumber`（不是 hwnd），`hide` 只能整应用——见 `docs/macos-backend.md`。
4. 提交信息用 Conventional Commits（`feat:` / `fix:` / `docs:` / `test:` / `chore:`）。

## 目录速览

| 路径 | 用途 |
|---|---|
| `prompts/AGENTS.m0.md` | M0 提示词安装版（贴进全局指令用，v1.8 跨平台） |
| `mac/` | **macOS 后端**（Swift + AX）：`build.sh` 编译/签名/安装，`test.sh` 15 项验收 |
| `docs/macos-backend.md` | macOS 平台事实、与 Windows 的差异、已知边界 |
| `tools/ddir.ps1` | 参考实现（零依赖 PowerShell；Rust 版见 `src/`） |
| `docs/plan.md` | 开发规划与 Gate |
| `docs/protocol.md` | 协议草案（claim/own/close/displays + 错误码） |
| `docs/decisions.md` | 已定决策 D1–D20 |
| `docs/m0-observations.md` | 真实会话测试记录 |
