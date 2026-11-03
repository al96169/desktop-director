# 已定决策（ADR 简版）

> 目的：把"已经讨论过、别再反复"的结论固定下来。改一条要写理由和日期。
> 完整论证见 `研究分析报告.md`（vault）。

| # | 决策 | 理由 | 后果 |
|---|---|---|---|
| D1 | **不做"Agent 之间自由协商"，做中央仲裁 + 需求竞标** | 模型不擅长几何谈判、无全局视图、易死锁；仲裁可审计可回放 | 所有 Agent 必须走 `ddir`；协议成为唯一事实来源 |
| D2 | **三条不变量：单写者 / 单焦点 / 单负责人** | 把"不打架"变成可断言的测试，而不是提示词里的礼貌 | 违反即 bug；验收用例见 protocol §8 |
| D3 | **auto 允许关闭软件，但走"武装 → 处决 → 撤销"** | 用户要的资源释放能力，靠流程控风险而不是禁用功能 | 30s 倒计时；每轮 ≤3；只 `WM_CLOSE`；可重启还原 |
| D4 | **semi 永不自动关闭**（只隐藏；只允许关自己 spawn 的进程） | 半自动的定位是"别干扰我"，不是"帮我清理" | semi 下 `close` 一律拒绝（自己的除外） |
| D5 | **关闭前必须可逆** | 不可逆关闭对用户不可接受；可逆关闭只是"有点烦" | 抓 `restart{cmd,args,cwd,rect}`；记录留 24h；提权进程降级 `restart_partial` |
| D6 | **屏幕是一等资源：semi 只托管用户勾选的屏** | 物理隔离比"猜用户前台意图"可靠得多 | 新增 `display_uid`、`display_not_managed`、借用/热插拔规则 |
| D7 | **新插上的屏默认归用户** | 绝不静默把 Agent 窗口摆到用户新屏上 | `on_new_display: "user"`，需要用户手动勾选 |
| D8 | **semi 默认托管"除主屏外全部"** | 用户已确认；比"首次全手动勾选"少一步操作 | `mode_defaults.semi = "all_except_primary"` |
| D9 | **Agent 绕过 CLI 直接杀进程：审计 + 自动降档** | 同权限下技术上拦不住，只能"抓现行 + 刹权限" | `unmanaged_kill` → 降为 semi + 通知 |
| D10 | **不做虚拟桌面切换 / P2P 协商 / 强杀 / 全局钩子注入** | 收益低、风险高、见 README 非目标 | 相关需求一律拒绝并指向替代方案 |
| D11 | **技术栈：Rust + `windows` crate，从 M1 开始**（~~原计划 Node 原型→Rust 重写~~，2026-11-03 修订） | M1 第一行就要 `EnumWindows`，Node 只能靠 native 模块/子进程桥接，验证不到"真窗口行为"这个真难点；协议冻结靠文档 + 回放夹具，不靠语言；避免二次实现 | 单一 workspace（`ddir-core` / `ddir-win` / `ddir-hud` / `ddir-cli`）；Node 只保留可选 MCP shim/看板客户端 |
| D12 | **不耦合任何 Harness**：CLI + 管道 + MCP + 本地 HTTP，Harness 侧只放提示词 | 用户明确要求；不同 Harness 接入能力不同 | 协议层必须与模型无关 |
| D13 | **写操作默认 dry-run，编译期用 feature gate 禁止** | 开发期最怕"调试时把用户桌面搞乱"，靠自觉不可靠 | `exec` 只在 `feature = "write"` 下编译进二进制；M2 前默认二进制里没有 `SetWindowPos` |
| D14 | **协议在 R1 结束冻结 v1.0** | Agent 提示词里写死了错误码处理，改语义会静默破坏所有接入方 | 之后 op 只增、错误码只增；不兼容变更升主版本并在 daemon 返回 `proto` 字段 |
| D15 | **单屏时 semi 也托管这块屏**（否则 semi 无事可做） | 决策 D8 假设 ≥2 屏；实测本机单屏，托管集合为空会让 semi 完全失效 | `managed = (display_count <= 1) or (not primary)`；单屏时退回"不遮挡用户前台窗口"的启发式 |
| D16 | **M1 先交 PowerShell 参考实现**（`tools/ddir.ps1`），Rust 正式版待工具链 | 实测本机无 cargo/rustc/gcc/.NET SDK，Docker 引擎未启动；而 M0 要真实会话测试就必须先有可调用的 `ddir` | 参考实现只做只读 + `move/claim/release/own`，**不实现 close**；Rust 版按 `docs/plan.md` 的 crate 划分重写，行为以 `docs/protocol.md` 为准 |
| D17 | **M0 的安装位置固定三处**：`~/.dsh/AGENTS.md`、`~/.trae-cn/user_rules/rule-*.md`、测试用 `.testhome/AGENTS.md` | 一个 Harness 一份全局指令，内容同源 | 改 `prompts/AGENTS.m0.md` 后三处一起覆盖；`.testhome/` 含本机凭据，必须 gitignore |
| D18 | **Agent 身份 = 父进程链上的宿主进程**（Trae / 终端 / 执行器），不是本次调用的 PID | 实测 `own` 之后立刻 `hide` 会因 PID 变化报 `owned_by_other`，身份不稳定会废掉所有跨调用语义 | `DDIR_AGENT` 可覆盖；宿主进程退出即身份失效（符合直觉） |
| D19 | **用户活跃信号 = 光标位移 >25px 或前台窗口变化**，`input_age_s` 只作原始值照实报告 | 本机有鼠标抖动/注入（Bloody6 类常驻工具），`GetLastInputInfo` 长期为 0，单用它会让"空闲判断"永远失真 | 判定结果写进 `user_active`；`claim/move` 遇 `user_active` 可 `--force`；后续可加键盘专用信号 |
| D20 | **`hide`/`close` 都要求先 `own`**；`close` 只发 `WM_CLOSE` 等 3s，失败即 `close_blocked`，不重试不强杀 | 关闭是唯一会丢数据的动作，必须挂在"负责人"语义上；也顺手把 M2.5 的闸门做进参考实现 | `not_owned` / `owned_by_other` 直接拒绝；`release` 同时还原隐藏与位置 |
| D21 | **Trae 用户规则需重启才加载**（实测：重启前未进 system prompt，重启后逐字复述成功）；仓库根 `AGENTS.md` 保留为项目级兜底 | 只改文件不重启会静默不生效，最容易误判"已验证" | 跨 Harness 验收一律要求对方**复述规则原文**，不看行为（行为可能来自任务提示）；Trae 侧改动后必须重启 |
| D22 | **窗口租约必须排他（I1），参考实现已落地**：item 级 gent/ts/expires（TTL 300s），claim 跳过别人持有的窗口，撞上则返回 window_owned_by；elease 只释放自己的 | 实测两个 Agent 抢同一窗口时双双成功、rom 被覆盖、B 释放了 A 的租约——不排他的话整套语义都是假的 | 同 Agent 重复 claim 视为续租；租约过期自动可抢；跨 Agent 的抢占留给 M5 的优先级矩阵 |

## 待观察（还没定，先记着）

- 武装倒计时 30s / 每轮 3 个 的默认值是否合适。
- 用户借用托管屏后 30 分钟归还是否太长。
- `stateless` 程序的强杀白名单要不要留（当前倾向：不留）。
- 是否要"布局预设 + 按任务类型记忆"（可能比多 Agent 协调更早见效）。
- 许可证（倾向 MIT，与其他个人项目一致）。
| D23 | **多平台是硬需求**：Windows / macOS / Linux 三平台，协议与仲裁一份、后端各一份 | 用户明确要求；单一 Windows 实现会把语义写死，后面拆不出来 | ddir-core 零平台依赖；ddir-win / ddir-mac / ddir-linux 各自实现 Backend trait |
| D24 | **daemon 启动自报 platform + caps**，Agent 按 caps 决策 | 三平台能力差异巨大（macOS 只能应用级隐藏、Wayland 不能摆窗口），让 Agent 猜必然出错 | 写操作前先看 caps；不支持的能力返回 unsupported_on_platform，而不是静默失效 |
| D25 | **macOS 用 Accessibility API（AX）**，不用 AppleScript/SIP hack | AX 是唯一稳定的窗口摆放途径（yabai/AeroSpace 同路线）；AppleScript 走 System Events 更慢且同样要 TCC | 需要用户授权"辅助功能 + 屏幕录制"；未授权时只读降级 |
| D26 | **Linux 分档：X11 全支持 / Hyprland-KWin 半支持 / GNOME Wayland 明牌不支持** | Wayland 没有通用窗口控制协议，这是安全模型的必然结果，不是实现偷懒 | caps 如实报告；GNOME 下只做启动与观察，文档写明 |
| D27 | **每个后端必须通过 ddir selftest 才发布** | 跨平台最大的坑是"以为做到了"；三套系统各有一套边界行为 | selftest 输出逐条 pass/fail，作为发布门槛（见 docs/platforms.md §4） |