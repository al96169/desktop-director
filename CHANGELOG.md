# Changelog

## 0.8.0 - 2026-11-04

**macOS 托盘 + 开机自启**（补齐阶段 2 的用户控制面）：

- `ddir tray`：菜单栏常驻（`NSStatusItem`），图标旁常显档位（◐ semi / ● auto / ○ off）；
  菜单 = 状态 / 模式（off·semi·auto）/ 全部还原 / 自动关闭（off·minimize·close）/ 窗口列表（点击 raise+激活）/
  托管屏（勾选托管）/ 查看日志 / 打开状态目录 / 开机自启 / 退出
- `ddir tray --check`：不启动常驻进程，把 NSMenu 树打成 JSON（测试用）
- 单实例：`flock` 锁 `~/.ddir/tray.lock`；第二个实例返回 `already_running`，不弹窗
- 3s tick：消费 `paced` 演示队列 + `unmanaged_kill` 检测（沿用 D9 语义）
- **全部还原 = 所有人**：托盘代表人，`releaseAll(force: true)` 恢复所有 Agent 的活跃租约；
  CLI `ddir release` 仍只释放自己的（D22）。托盘进程身份与 CLI 无关，按身份过滤会让按钮变成空操作
- `ddir autostart on|off|status`：`~/Library/LaunchAgents/com.ddir.mac.tray.plist` +
  `launchctl bootstrap/bootout gui/$UID`；实测 LaunchAgent 启动的进程同样 `accessibility=true`
- `mac/test.sh` 扩到 32 项：新增 auto 武装/最小化/撤销、焦点令牌、两 Agent 并发抢同一窗口（恰好 1 胜）、过期租约不挡新 claim、托盘菜单接线
- 已知问题：Windows `src/tray.rs` 的 `release_all()` 同样只释放托盘自身租约，待修

## 0.7.3 - 2026-11-04

**macOS 后端落地**（Swift 6 + Accessibility API，`mac/`）：

- 命令面与 Windows 一致：`mode/displays/list/status/plan/claim/move/hide/show/close/own/disown/release/heartbeat/focus/auto/config/log/flush/board/selftest/demo`
- 窗口标识 `pid:CGWindowNumber`（CG 号经 `CGWindowListCopyWindowInfo` 按 pid+几何+标题配对，且保证一号一窗）；坐标全程 points
- `hide` = 应用级（`kAXHiddenAttribute`），`caps.window_hide="app"`；`close` = AX 关闭按钮，关窗不退进程
- `selftest` 7/7；`mac/test.sh` 15 项验收（TextEdit，只用自己开的窗口）
- 构建：`./mac/build.sh` → `~/Applications/Ddir.app`（签名 ddir-dev，bundle id 不变，TCC 不掉）→ `~/.local/bin/ddir`
- 托盘 / 开机自启 / HUD 明确返回 `unsupported_on_platform`（未实现，不静默成功）
- 新文档 `docs/macos-backend.md`：平台事实、与 Windows 的差异、已知边界
- 提示词 v1.8：`window-id` 平台中立化（Windows `0x…` / macOS `pid:cgwin`），补「平台差异」小节
- Rust 版版本号对齐 0.7.3（无行为变更）

## 0.7.2 - 2026-11-04

- 提示词 v1.7：去掉硬编码路径，补齐 heartbeat / priority / focus / config / log / displays --manage / flush / demo / tray
- `prompts/AGENTS.ddir.md` 改成"设计说明"，规则以 `AGENTS.m0.md` 为唯一真源（避免两份规则漂移）
- 明确 `hide` 会记租约、`release` 恢复；明确 `claim` 会跨屏把窗口拉到托管屏
- 与代码同步的检查清单写进 AGENTS.ddir.md

## 0.7.1 - 2026-11-04

修复 Agent 反馈的 7 个问题：

- **无参运行 panic**：`ddir` / `ddir --help` 之前会 `args[1..]` 越界，现在正常打印帮助
- **hide 不写租约**：`hide` 现在记一条 `action=hide` 的租约，`release` 会把窗口重新显示出来
- **mode 不校验**：`move`/`hide`/`close`/`claim` 在 `off` 档统一返回 `mode_off`
- **demo 硬编码盘符**：演示目录改为 `~/.ddir/demo`
- **notepad 大小写**：应用名比较统一走 `eq_ignore_ascii_case`（Win11 的 `Notepad` 也能匹配）
- **窗口开在主屏导致 claim 找不到**：claim 现在匹配**所有屏幕**的窗口，命中后把它拉到托管屏；`release` 再放回原位置
- **help 漏命令**：补齐 displays/mode/plan/claim/move/hide/show/close/own/release/heartbeat/focus/auto/config/log/flush/demo/tray/autostart/board/selftest

## 0.7.0 - 2026-11-04

- 多屏托管：`managed_displays` 配置（`all` / `all_except_primary` / `none` / 逗号分隔的 uid）
- `ddir displays --manage <uid|gdi|primary> [--off]` 增删托管屏；关闭全部后 claim 返回 `display_not_managed`
- 显示器 uid 使用设备名（`\\.\DISPLAY1`），重启/热插拔后仍可识别
- 新增 `docs/company-onboarding.md`：公司电脑 10 分钟上手清单（含 SmartScreen、回滚、排障）
- 注意：per-display「借用/热插拔回滚」仍未实现

## 0.6.0 - 2026-11-04

多 Agent 加固（P0 + P1 + P3）：

- **跨进程锁 + 原子写**：`state.lock` 串行化 leases/apps 的读改写，`atomic_write` 先写 tmp 再 rename
- **心跳**：`ddir heartbeat` 续期自己的租约与软件认领（TTL 300s；claim 也会续期）
- **优先级**：`--priority low|normal|high|user` 写入租约；高优可抢占低优，条件=对方租约 >60s **且**窗口不在前台；抢占记日志/审计，返回 `preempted` 计数
- **焦点令牌**：`ddir focus [--seconds N]` / `ddir focus release`；冲突返回 `focus_denied`；`status` 显示 `focus_holder`
- **越权检测**：托盘每 3s 比对窗口集合，消失且 20s 内无 ddir 关闭记录 → `unmanaged_kill` 审计 + 日志；可选 `downgrade_on_unmanaged_kill=true` 自动降档 semi
- **display_uid**：显示器标识改为设备名（`\\.\DISPLAY1`），多屏时不再依赖索引
- **raise 收敛**：只有当没有其他 Agent 持租约时才把窗口提到最前，避免 z-order 打架
- prompt v1.6：心跳、优先级、焦点令牌、越权规则

## 0.5.1 - 2026-11-04

- 摆窗口后把窗口提到 z-order 顶部（不抢焦点），paced 演示时能看到逐列铺开
- `ddir demo` 改为"开一个 → claim 一个 → 再开下一个"，依次铺成 1/2/3 列
- demo 结束恢复 `presentation` 原值（默认 instant）

## 0.5.0 - 2026-11-04

### 操作 / 演示分离

- 新增 `presentation = instant | paced` 与 `step_ms`（默认 400ms）
- `paced` 下 `claim` 立刻返回（`pending: N`），几何与租约即时生效，改动进入展示队列按节拍上屏
- 展示队列是 `~/.ddir/queue/*.op` 小文件，生产/消费不共写一个文件
- 托盘每 150ms 消费队列；`ddir flush` 可立即清空
- 新增 `ddir demo`：自开 3 个演示窗口、逐个 claim、自动还原并关闭

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