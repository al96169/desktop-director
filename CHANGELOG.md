# Changelog

## 0.11.3 - 2026-11-05

**多路原生播放 + 新会话实测反馈修复**

- `ddir play <file> [--muted] [--detach]`：视频走 AVPlayerLayer；纯音频改为自绘"音频播放器"卡
  （标题 / 文件名 / 28 段电平条 / 时间码 / 进度线）；`--detach` 让脚本一次开多个播放器时不被前台阻塞
- 修播放器图层不跟随 AX 缩放（`setFrameSize` 同步 playerLayer.frame），平铺后不再出现"细条视频"
- **`ddir move` 现在会记租约**（action=move，from=移动前矩形）：`move --force` 之后 `ddir release` 能还原
- `ddir close` 返回里加 note：macOS 只关窗口、进程按平台语义继续运行（避免 `process_alive:true` 被当成失败）
- 演示：`demo/webdev/run.py` 增加 2x2 原生媒体墙（2 视频 + 2 音频同时播放）；
  素材改为业务化命名（brand-film / product-teaser / customer-call / standup-notes，NASA 公有领域 + CC0）
- 提示词 v2.0 补三条：`play --detach`、`move` 记得 `release`、演示前确认 `mode != off` 并演完切回 off

实测：新会话（独立上下文）仅凭任务提示词完成 4 窗口 2x2 编排、播放与收队；按反馈修掉
"play 阻塞 / move 不算租约 / close 语义误读"。

## 0.11.2 - 2026-11-05

**提示词 v2.0：轻量演示规则**（并修 README/文档里的版本引用）

- 新增「演示（给用户看，不是表演）」一节：
  - **不要逐字敲代码**（VS Code/Electron 丢合成按键，慢且费 token）——写文件 + 让页面/编辑器刷新即可
  - 预算：几秒、几条命令；`claim` 并排 →（可选）`hud` → `release`，不重排桌面、不反复录屏
  - 优先复用现成演示：macOS `ddir stage run`、跨平台 `python3 demo/webdev/run.py`
  - 用户没要求时不专门准备演示；任务本身有可见成果时顺手展示
- `ddir prompt` 打进 bundle 的规则同步更新（本机 `~/.dsh/AGENTS.md` 已重装 v2.0）
- 新增跨平台演示 `demo/webdev/`（上一提交），README 增加入口

## 0.11.1 - 2026-11-04

**演出改用真实素材**（去网上找，不再全靠本机合成）：

- `ddir stage fetch [--force]`：下载 **NASA/STScI JWST 船底座星云**、**Hubble 螺旋星系**
  （公有领域）与 **CC0 太空环境音乐**（yd / OpenGameArt），缓存到 `~/.ddir/show/media/`，
  写 `sources.json` 记录标题/作者/许可/来源 URL
- 静态星图 → **12 秒竖屏 Ken Burns 片段**（540×960、H.264、推镜 + 平移 + 柔边暗角），
  三列平铺满屏无黑边；暗角修复：不要用 `drawsAfterEndLocation`（会画出硬边圆）
- 音乐改为 46 秒循环（`loop-score.sh` 包装 `afplay`，回滚杀包装进程），离线时自动退回合成音
- 无网络/未 fetch 时 `stage` 自动退回本机生成素材，演出不会断
- 素材许可见 `~/.ddir/show/media/sources.json` 与 `docs/macos-backend.md`

## 0.11.0 - 2026-11-04

**演出模式 `ddir stage`**：一条命令把桌面变成导播台，全程 ddir 编排，可重复、可回滚。

- `ddir stage assets [--force]`：本机生成 6 个素材（HTML 仪表盘 / 打字 IDE / 代码 / 环境音 WAV /
  两个 540×960 H.264 片段）；无 ffmpeg、无下载，素材版本号变更时自动重建
- `ddir stage run`：清场（隐藏其它 App）→ Mission Control → `claim` 单窗 → 打开 IDE → `claim` 并排 →
  代码逐字出现 → `claim` 三窗（IDE + 双媒体）→ `hud --wall` 缩略图墙 → `release` + 关窗 + 恢复现场，
  约 70 秒；`--fast` 冒烟、`--keep` 保留现场
- `ddir stage rollback`：按 journal 关窗（按 app+title，抗 ref 重映射）、release 全部租约、
  恢复被隐藏的 App 与档位；幂等，可在任何中断后使用
- 新增 `ddir play`（AVPlayer 窗口，独立进程，可被 claim 平铺，无 AppleScript/TCC 弹窗）与
  `ddir web`（无地址栏 WKWebView 窗口）
- 关键修复：CLI 无 run loop 导致 `NSWorkspace` 看不到新窗口（显式 pump）、AX 关窗 `-25204` 误判为失败、
  播放器窗口透明（AVPlayerLayer backing layer）、媒体三列出现黑边（改为竖屏素材）、
  媒体拍次撞 3 租约配额（先 release 再 claim）
- `mac/test.sh` 42 项；文档新增「演出模式」整节（含 8 个踩坑记录）

## 0.10.0 - 2026-11-04

**HUD 轻量化 + 体检/提示词/写路径自检**（把 mac 侧能做的收尾）：

- `ddir hud` 默认改为**右下角轻量小卡**：360×~100 圆角、应用图标 + 标题 + 档位色点，
  静态快照、无定时器、不截屏、只要辅助功能；3 秒自动淡出
- 全屏暗化 + 缩略图墙保留为 `ddir hud --wall`（ScreenCaptureKit，需屏幕录制 + macOS 14），
  演示时再开；托盘菜单同时提供两档
- 小卡位置改到**右下角**：右上角会被 macOS 通知横幅盖住（通知窗口层级高于 `.floating`）
- `ddir hud --check` 输出 `style/tiles/权限`，方便脚本判断
- 新增 `ddir doctor [--text]`：辅助功能/屏幕录制/bundle 路径/签名/状态目录/mode/显示器/窗口/
  托盘/自启/提示词/提示词资源 共 12 项，`ok`/`warn`/`fail` 三级，warn 不影响退出码
- 新增 `ddir prompt [--install|--check]`：把 `prompts/AGENTS.m0.md` 打进 bundle，
  可一键安装到 `~/.dsh/AGENTS.md`（本机已装 v1.9）
- 新增 `ddir selftest --write`：自己开 TextEdit 窗口跑 move/hide/show/close（7+6 项）
- 修 macOS **窗口 tabbing** 的 close 判定：关掉 tab 时 NSWindow 仍在、标题换成别的文档，
  现在"窗口消失 **或** 标题变了"都算关闭成功（`ddir close` 与 selftest 同步）
- 提示词 v1.9：补 HUD/doctor 用法；去掉"macOS 托盘未实现"的过期说法
- `mac/test.sh` **39 项**

## 0.9.0 - 2026-11-04

**macOS HUD：暗化 + 缩略图墙**（阶段 1 的"科幻感"层）：

- `ddir hud [--seconds N]`：托管屏暗化 78%，把当前租约窗口摆成卡片墙（缩略图 + `App · 标题` + 坐标 + window-id），
  淡入 0.35s、到时淡出；`ddir hud --check` 只输出将要展示的 JSON
- 覆盖窗不抢焦点、点击穿透（`ignoresMouseEvents`、`orderFrontRegardless`、全空间、floating 层）；
  只覆盖 `managed_displays`，用户屏不碰
- 缩略图走 **ScreenCaptureKit**：macOS 15 已删除 `CGWindowListCreateImage`，改为
  `SCShareableContent` + `SCContentFilter(desktopIndependentWindow:)` + `SCScreenshotManager`（14+）；
  无屏幕录制授权/旧系统时退化为应用图标并注明原因
- 1s 刷新租约与布局；缩略图按 `ref` 缓存（修掉"每次 tick 重建卡片把缩略图冲掉"）
- 托盘菜单加「预览 HUD（6 秒）」（复用 `HudController.present`，不嵌套 run loop）
- `mac/test.sh` 33 项
- 屏幕录制授权在这台机器上已生效（`screen_recording=true`），HUD 实测有真实缩略图

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

**同一版本号的 Windows 线（main，0.8.0）**：

- **DPI 感知**：启动时设 Per-Monitor V2，混合 DPI 下窗口坐标不再被虚拟化
- **托盘「屏幕」子菜单**：每块屏一个勾选项，点一下即切换托管（等价 `ddir displays --manage`）；处理 `WM_DISPLAYCHANGE`
- **`ddir doctor`**：9 项诊断（状态目录/mode/配置/租约/锁/队列/显示/日志/托盘），输出 PASS/WARN/FAIL，有 FAIL 时退出码 1
- **进程级软件所有权**：`ddir own --pid <PID>`，`close` 同时认应用名和 `pid:<PID>`；两个 Chrome 实例可以各归一个 Agent
- **`list` 输出 pid**
- **集成测试** `tests/integration.ps1`：20 项断言（claim 并排/等宽/不重叠、hide 记租约、release 还原、own --pid + close 拒绝未认领、doctor），本机 20/20 通过


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