# 开发规划 v1

> 2026-11-03 · Desktop Director（`ddir`）· 单人项目
>
> **怎么读**：按"发布"分 5 档，每档有 **Gate**——通过才进下一档。任何一档停下都不留烂摊子：
> R0 停了就是一段提示词，R1 停了就是一个能天天用的半自动导播台，R3 停了才是多 Agent。

## 0. 三条工程原则

1. **先只读，后写；先 dry-run，后执行。** M2 之前代码里用 feature gate **物理禁止**调用 `SetWindowPos` / `WM_CLOSE`——不是靠自觉，是靠编译期开关。
2. **每档结束都要能自己天天用**，不能"功能全了但不敢开"。
3. **协议在 R1 结束冻结 v1.0**，之后只增不改（op 只增、错误码只增）。Agent 的提示词里写死了错误码处理方式。

## 1. 发布节奏与 Gate

| 发布 | 内容 | 人日 | 日历（按 1 人日/周） | Gate（通过条件） |
|---|---|---|---|---|
| **R0 / M0** | 提示词包（已就绪）+ 观察记录 | 0.5–1 | 1 周 | 5 个真实任务里 ≥3 个"窗口行为不招人烦" |
| **R1 / M1–M3** | 只读内核 + semi 可写 + 最小托盘 = **日常可用的半自动** | 10–13 | 10–13 周 | 连续 10 次任务零抢焦点；`restore` 误差 ≤8px；退出托盘不改变窗口状态 |
| **R2 / M2.2 + M2.5** | 屏幕托管 + auto 处决（倒计时/关闭/撤销） | 7–10 | +7–10 周 | 关 10 个 App 全部可撤销；有未保存的 100% 停在 `close_blocked` |
| **R3 / M5 + M6** | 多 Agent 仲裁 + 关闭保护 | 12–18 | +12–18 周 | protocol §8 的 12 条用例全绿；3 Agent 并发无人能关别人的软件 |
| **R4 / M4** | HUD 科幻层（缩略图墙/暗化/入场动画） | 4–6 | 可插队 | 1080p CPU<3%、GPU<5%；用户屏零绘制（截图断言） |

**执行顺序建议**：`M1 → M2 → M3(最小托盘) → M2.2 → M2.5 → M5 → M6`，M4 在 M3 之后任意时候插队。
理由：托盘是日常使用的入口（切档、勾屏、一键还原），先有它 R1 才真的"能天天用"；HUD 是观感不是能力，随时可插。

**总量**：33–47 人日。按每周投入折算：

| 每周投入 | R1 到手 | 全部完成 |
|---|---|---|
| 4 h（≈0.5 人日） | 5–6 个月 | 15–22 个月 |
| 8 h（≈1 人日） | 2.5–3 个月 | 8–11 个月 |
| 12 h（≈1.5 人日） | 7–9 周 | 5–7 个月 |

> 这个数字不好看，但它是"单人 + 下班时间"的真实值。好在 R0 一周内就有收益，R1 之后每天都能用。

---

## 2. 各里程碑：任务、DoD、回退

### R0 · M0 提示词包（进行中，0.5–1 人日）

- [x] `prompts/AGENTS.ddir.md` v1
- [ ] `docs/m0-observations.md`：5 个任务 ×（它摆了哪些窗口 / 该不该摆 / 你被打扰几次）
- [ ] 根据观察改 3 处以内（**只改提示词，不改文档结构**）

**DoD**：≥3/5 任务"不招人烦"，且能复现"该藏的藏了"。
**回退**：模型判断不可靠 → 提示词退化为"只摆 1 个主窗口 + 其余不碰"，把复杂度留给 R2 的仲裁器。

### R1 · M1 只读内核（3–4 人日）

- [ ] Cargo workspace 骨架：`ddir-core` / `ddir-win` / `ddir-cli`
- [ ] `ddir-win`：`EnumWindows` + 过滤链（visible → 非 `WS_EX_TOOLWINDOW` → `GA_ROOTOWNER==self` → `DWMWA_CLOAKED==0` → 有标题 → 类名黑名单）
- [ ] `ddir-win`：`GetWindowRect` / `DwmGetWindowAttribute(EXTENDED_FRAME_BOUNDS)` / `GetDpiForWindow` / `GetMonitorInfo`
- [ ] `ddir-win`：`display_uid`（`QueryDisplayConfig` + `DISPLAYCONFIG_TARGET_DEVICE_NAME`）
- [ ] `ddir-cli`：`ddir list --json`、`ddir displays --json`、`ddir snapshot`
- [ ] `ddir-core`：布局求解 v0（单屏 guillotine + 权重 + 最小尺寸降级）
- [ ] `ddir plan --dry-run`：输出"打算怎么摆"，不执行
- [ ] 测试夹具：本机 18 窗口快照（2026-11-03 实测）+ 300 个噪声窗口样本

**DoD**：`ddir list` 与肉眼 Alt+Tab 一致（差 ≤1 个）；`plan` 输出人看着合理；**二进制里没有任何写操作**（feature gate 断言）。
**回退**：过滤规则收不住（噪声窗口太多）→ 改用"Alt+Tab 白名单 + 进程树"，放弃纯启发式。

### R1 · M2 semi 可写（4–6 人日）

- [ ] `ddir-win`：`set_window_rect`（`SWP_NOACTIVATE`、先 `SW_SHOWRESTORE`、跨屏重算 DPI）
- [ ] `ddir-core`：lease store（TTL 90s / 心跳 10s / 撤销栈）
- [ ] `ddir-win`：用户所有权判定（`th32ParentProcessID` 上溯 + Job 归属）
- [ ] `ddir-win`：冷却期（`GetLastInputInfo`，用户 5s 内动过 → 只读）
- [ ] `ddir-cli`：`claim / release / status`（单 Agent）
- [ ] `ddir-win`：三类几何适配——终端 cell 量化、UWP 双层、最大化残留 8px
- [ ] 崩溃恢复：`state.json` 落盘 + 启动回滚未释放 lease

**DoD**：10 次连续任务零抢焦点；`restore` 与快照差 ≤8px；kill -9 daemon 后重启能回滚。
**回退**：某些 App 摆不动（`WM_GETMINMAXINFO`）→ 记 `app_refuses_resize`，接受现状，不硬来。

### R1 · M3 最小托盘（3–4 人日）

- [ ] 托盘图标 + **原生 Win32 右键菜单**（不走 muda，usagi-pet 已踩过坑）
- [ ] 菜单：三档 / 每屏勾选 / 全部还原 / 撤销上次关闭 / 打开审计 / 退出
- [ ] 全局热键（默认 `Ctrl+Alt+Shift+R` = 全部还原）+ 单实例 + 开机自启
- [ ] 配置读写 `~/.ddir/config.json`（手改也能生效）

**DoD**：切档/勾屏 1s 内生效；托盘退出后窗口状态不变（与 home-watcher 的"退出不影响检测"一致）。

### R2 · M2.2 屏幕托管（2–3 人日）

- [ ] 托管集合判定（默认"除主屏外全部"）+ 新屏默认 `user`
- [ ] `display_not_managed` / `spans_displays` / `display_lost`
- [ ] 借用机制（轮询 `GetCursorPos` + `WindowFromPoint` + 前台窗口所在屏，活跃 30 分钟）
- [ ] `WM_DISPLAYCHANGE` 热插拔 → 回滚策略
- [ ] 混合 DPI：150%/100% 各一屏的摆放精度

**DoD**：勾选副屏后逐像素零越界；拔线无窗口丢失；150%/100% 各屏误差 ≤1px。

### R2 · M2.5 auto 处决（5–7 人日）

- [ ] 软件表（进程树、exe、`pinned`、owner 判定、`restart` 抓取：`QueryFullProcessImageName` + PEB）
- [ ] 武装流程：三栏清单 + 倒计时状态机（用户输入暂停 / 取消 / 保护某个 / 立刻开始）
- [ ] 处决管道：每轮 ≤3、`WM_CLOSE`、等 8s、模态检测、`close_blocked`
- [ ] `undo-close`：重启 + 几何还原 + `restart_partial` 降级
- [ ] 审计 `~/.ddir/audit.jsonl`（谁/关了谁/为什么/耗时/可否重启）

**DoD**：关 10 个 App 全可撤销；标题带 `*` 的文档 100% `close_blocked`；审计能一眼读出发生了什么。
**回退**：dogfood 里出现一次"差点丢数据" → auto 关闭默认关闭，退化为"隐藏 + Efficiency Mode"，只留 `close` 命令给显式调用。

### R3 · M5 多 Agent 仲裁（7–10 人日）

- [ ] Agent 身份：父进程/环境变量/管道 client id（不靠模型自报）
- [ ] 多客户端 + 配额（3 窗口 / 3 软件 / 1 焦点）
- [ ] 仲裁：排他、先到先得、老化、抢占矩阵、稳定 tie-break
- [ ] 焦点令牌（semi 恒 `none`）
- [ ] 软件所有权表 + close 矩阵 + `owned_by_other`
- [ ] `ddir board` 看板
- [ ] 回放测试框架：随机序列 + 三条不变量断言

**DoD**：protocol §8 的 12 条用例全绿；100 次随机序列无死锁。

### R3 · M6 auto × 多 Agent（5–8 人日）

- [ ] `unmanaged_kill` 检测（进程消失但没走过 close 管道）→ 自动降档 semi + 通知
- [ ] 审计回放 + 一键导出
- [ ] 保护清单/白名单的托盘编辑
- [ ] 4 小时真实使用 dogfood

**DoD**：3 Agent 并发无人能关别人的软件；连续 4h 无"想砸键盘"事件。

### R4 · M4 HUD（4–6 人日，可插队）

- [ ] 装饰层：分层窗口 + 边框光效 + 暗化挖洞（`SetWindowRgn`）+ 点击穿透
- [ ] 合成层：`DwmRegisterThumbnail` 缩略图墙，**只在托管屏**
- [ ] 动效：缩略图插值（几何层一次到位）+ 一次入场动画，稳态零动画
- [ ] 性能预算与自动降级（无 HUD 模式）

**DoD**：1080p CPU<3%、GPU<5%；用户屏零绘制（截图对比断言）；DRM 窗口自动跳过。

---

## 3. 代码结构（Rust 从 M1 开始）

```
desktop-director/
├─ Cargo.toml                 # workspace
├─ crates/
│  ├─ ddir-core/              # 纯逻辑，零 Win32，CI 可跑
│  │   model.rs               #   display/window/app/lease 的数据结构与不变量
│  │   arbiter.rs             #   仲裁：配额/老化/抢占/tie-break
│  │   policy.rs              #   许可矩阵、关闭资格、屏幕作用域
│  │   layout.rs              #   guillotine 求解、最小尺寸降级
│  │   replay.rs              #   随机序列回放 + 不变量断言
│  ├─ ddir-win/               # Win32 后端
│  │   windows.rs             #   枚举+过滤+几何+DPI
│  │   displays.rs            #   display_uid/工作区/热插拔
│  │   procs.rs               #   进程树/owner/restart 信息
│  │   close.rs               #   WM_CLOSE 管道 + 模态检测
│  │   exec.rs                #   SetWindowPos（feature = "write"）
│  ├─ ddir-hud/               # 装饰层 + 合成层（R4）
│  └─ ddir-cli/               # bin：CLI + 管道 + 托盘
└─ tests/
   fixtures/                  # 窗口快照、回放序列
   smoke.rs                   # #[ignore] 真机用例
```

**为什么不用 Node 原型了**（修订 D11）：M1 的第一行代码就要 `EnumWindows`，Node 得靠 native 模块或子进程桥接，验证不到"真窗口行为"这个真正的难点；而协议冻结靠文档 + 回放夹具，不靠语言。用 Node 只保留一个可选件：MCP shim / 看板客户端（几十行）。

**trait 边界**（保证 `ddir-core` 可测）：

```rust
pub trait Backend {
    fn list_windows(&self) -> Vec<WinInfo>;
    fn displays(&self) -> Vec<Display>;
    fn set_rect(&self, hwnd: Hwnd, rect: Rect, dpi: u32) -> Result<()>;
    fn close_window(&self, hwnd: Hwnd) -> Result<CloseOutcome>;
    fn last_input_age(&self) -> Duration;
}
```

真实实现 `Win32Backend`；测试用 `FakeBackend`（读夹具）+ `ReplayBackend`（按脚本回应）。

---

## 4. 测试策略（三层）

| 层 | 内容 | 何时跑 | 成本 |
|---|---|---|---|
| **L1 纯逻辑** | `ddir-core` 的仲裁/布局/许可矩阵 + 回放序列 + 不变量断言 | 每次提交（CI） | 0 |
| **L2 真机 smoke** | 固定 6 场景：终端 cell / UWP 双层 / 最大化残留 / 双 DPI / 提权窗口 / 标题带 `*` 的文档 | 每档结束手动跑 | 10 分钟 |
| **L3 dogfood** | 自己天天用，记录"被打扰次数"和"想砸键盘事件" | 持续 | 0 |

**"不破坏桌面"的四道保险**（开发期默认全开）：

1. 所有写操作默认 `--dry-run`，要 `--commit` 才真执行；
2. 每次执行前快照，失败/异常自动回滚；
3. 全局热键 `Ctrl+Alt+Shift+R` 一键全部还原（不依赖 daemon 活着也能触发）；
4. `ddir daemon --safe`：只摆窗口，不关任何东西（R2 之前的默认）。

---

## 5. 前三个 sprint 的 commit 序列（可直接照做）

**Sprint 1（M1，约 3 个晚上）**

```
chore: cargo workspace（core/win/cli）
feat(win): EnumWindows + 过滤链，输出与 Alt+Tab 同级
feat(cli): ddir list --json
feat(win): display_uid via QueryDisplayConfig
feat(cli): ddir snapshot --out
test(fixtures): 2026-11-03 本机 18 窗口快照 + 300 噪声窗口
feat(core): layout v0（guillotine + 权重 + 降级）
feat(cli): ddir plan --dry-run
test: plan 输出对拍（固定夹具 → 固定矩形）
```

**Sprint 2（M2a，约 4 个晚上）**

```
feat(win): set_window_rect（SWP_NOACTIVATE，feature=write）
feat(core): lease store（TTL/心跳/撤销栈）
feat(win): 用户所有权（进程树上溯）
feat(cli): claim/release/status（单 Agent）
feat(win): 冷却期（GetLastInputInfo）
test(smoke): 10 次任务零抢焦点回归
```

**Sprint 3（M2b + M3 骨架，约 4 个晚上）**

```
fix(win): 终端 cell 量化 / UWP 双层 / 最大化残留
feat(cli): ddir restore --all + 热键
feat(core): state.json 落盘 + 启动回滚
feat(tray): 原生 Win32 菜单（三档 + 全部还原）
chore: 协议冻结 checklist
```

---

## 6. 风险登记（触发 → 应对）

| 风险 | 触发信号 | 应对 |
|---|---|---|
| auto 关闭丢数据 | dogfood 出现一次"差点丢" | auto 关闭默认关；退化为隐藏 + Efficiency Mode，`close` 只留显式调用 |
| 几何适配失控（App 各异） | 适配表 >10 个特例 | 放弃"精确摆放"，改"分区 + 最大化/最小化"，把精度让给用户 |
| 多屏完全未验证 | R2 开始即打到 150% DPI | R2 第一件事就是双 DPI smoke，不通过不写关闭逻辑 |
| 进度拖太久 | R1 超过 16 周 | 砍 M2.2/M2.5，只发 M0+M1+M2（"只管窗口不管屏和关闭"的最小版） |
| HUD 吃性能 | 1080p >5% GPU | 缩略图降到 15fps、只画当前任务涉及窗口、提供"无 HUD"档 |
| 你嫌吵 | 每天被打扰 >2 次 | 默认档位退回 off，改成"任务开始时手动 `ddir on`" |

## 7. 延后 / 不做

- **延后**：布局预设与记忆（R1 后再评估，可能比多 Agent 更早见效）、macOS、Aya 类动效
- **不做**：虚拟桌面切换、Agent 间 P2P 协商、强杀、全局钩子/DLL 注入/驱动、Electron

## 8. 需要你拍板的两件事

1. **每周能投入多少小时**？上表按 1 人日/周算，实际差多少直接改这张表的日历列。
2. **R1 完成后先自用一个月再往下做，还是直接冲 R2？** 我建议先用一个月——R1 的真实使用会改写 M2.5 的很多假设（尤其是"到底该不该自动关"）。
