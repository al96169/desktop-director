# Windows 侧接手指南 · 演示录屏

> 给 Windows 上的 Agent。mac 线的成果已合进 `main`（`670c884`）；Windows 源码是 `0.8.0`，
> mac 线单独编号 `0.11.3`（见 `Cargo.toml` 注释）。先 `git pull` 到 `670c884`。

## 0. 先同步

```powershell
cd F:\desktop-director
git pull                      # 或从 GitHub 拉 main
git log --oneline -1          # 期望 670c884
cargo build --release
.\target\release\ddir.exe selftest
.\target\release\ddir.exe doctor      # Windows 是 9 项（mac 是 12 项，别对照错）
```

## 1. 装提示词 v2.0（重要）

Windows 上装的还是 v1.7。把仓库里的 `prompts\AGENTS.m0.md` 整段覆盖到你们的全局指令
（`%USERPROFILE%\.dsh\AGENTS.md`、Trae 用户规则等）。v2.0 新增了「演示」一节：
不逐字敲代码、`claim → hud → release` 三步、`play --detach`、`move` 记租约、演示前确认 `mode != off`。

## 2. 演示脚本现状（Windows 分支未实机验证）

`demo/webdev/run.py` 是跨平台 playbook（Vue 初始化 → 写组件 → Playwright/Edge 多页 → 设计稿 →
文件夹 → 看图 → 媒体）。macOS 已完整跑通；**Windows 分支的 helper 只按文档写好**，第一次跑大概率要修：

```powershell
python demo\webdev\run.py --fast        # 先冒烟
```

需要修/确认的点（都在 `run.py` 底部的 helper）：

| helper | Windows 现状 | 要验证什么 |
|---|---|---|
| `terminal_script()` / `open_terminal()` | 用 `cmd /c start powershell -NoExit -File beat.ps1` | 是否新开一个窗口；`npm` 在 PATH 里 |
| `open_folder()` | `explorer <dir>` | 窗口能否被 `ddir list` 认到（app 名可能是 `explorer`） |
| `open_images()` | `os.startfile`（默认看图应用，可能是"照片"） | 窗口标题/进程名，用于 `ddir move` |
| `type_text()` / `key()` | PowerShell `Set-Clipboard` + `SendKeys` | **不建议用**：演示不逐字敲，只用文件写入 + HMR |
| `open_media()` | `os.startfile`（系统播放器 = Media Player） | 同时开 4 个媒体时能否各自成窗、被 `ddir move` 平铺 |

## 3. 与 macOS 的功能缺口（先知道，别硬学）

| 能力 | macOS | Windows |
|---|---|---|
| `ddir play <file>`（自带播放器、`--detach`、音频播放器卡） | ✅ | ❌ 用系统默认播放器 `start "" file`，再用 `ddir move` 平铺 |
| `ddir web <file>`（无 chrome 的 WebView 窗口） | ✅ | ❌ 用 Edge/Chrome 窗口（Playwright 或 `start`） |
| `ddir stage run`（科幻风演出） | ✅ | ❌ 这是 Swift 实现的 macOS 专属；Windows 用 `demo/webdev/run.py` |
| 托盘 / `autostart` | ✅ | ✅（Rust 托盘，HKCU Run） |

想让 Windows 也有"原生多播放器 + 2x2 平铺"，可以在 Rust 侧加一个 `play`（ShellExecute 打开，
或用 `windows` crate + Media Foundation 自绘窗口）——**这是后续任务，不阻塞这次录屏**。

## 4. 录屏

- 工具：Xbox Game Bar（`Win+G`，最省事）或 OBS（可控分辨率/帧率）；分辨率统一 1920×1080。
- 录之前：`ddir mode semi`，`ddir list` 确认没有私人窗口（微信/邮件）在托管屏上；
  把要录的窗口 `claim`/`move` 好，**不要录整个桌面**。
- 节奏：一次演示 60–90 秒足够；录完 `ddir release` + `ddir close` 收队，`ddir status` 应为 0 租约。

## 5. 回报格式

1. `ddir selftest` / `ddir doctor` 结果（几条 PASS / 有没有 FAIL）
2. `run.py --fast` 在 Windows 上第一次跑到哪一步、报了什么（把 helper 的补丁一并提交）
3. 录屏文件路径 + 时长 + 分辨率；3–5 张关键帧截图
4. 有没有 Windows 特有的坑（窗口 id、播放器进程名、Playwright 的 Edge channel 等）
