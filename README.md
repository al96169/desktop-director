# Desktop Director

> **桌面导播台**：把 Windows 桌面当成演播室，把窗口当成信号源，让多个 Agent 轮流"上播"而互不打架。

| | |
|---|---|
| 产品名 | Desktop Director |
| 中文名 | 桌面导播台 |
| 命令 / 可执行 | `ddir`（`ddir daemon` 常驻，`ddir <cmd>` 是客户端，同一个 exe） |
| 状态目录 | `~/.ddir/`（`mode.txt` / `leases.tsv` / `apps.tsv` / `audit.tsv`） |
| 形态 | v0.1 是**单文件 CLI**（每次调用读写 `~/.ddir`）；常驻 daemon + 管道 / MCP 在 M3 之后 |
| 平台 | **Windows / macOS 已实现，Linux 只有设计**（协议一份，后端各一份；能力差异见 [docs/platforms.md](docs/platforms.md)、macOS 细节见 [docs/macos-backend.md](docs/macos-backend.md)） |
| 文档 | 规划 [plan](docs/plan.md) · 协议 [protocol](docs/protocol.md) · 平台 [platforms](docs/platforms.md) · 决策 [decisions](docs/decisions.md) |

---

## 当前状态（0.7.3，2026-11-04）

| 已完成 | 未完成 |
|---|---|
| Windows 后端（枚举/并排/隐藏/还原） | Linux 后端（只有设计） |
| **macOS 后端**（AX：枚举/并排/隐藏/关闭/空闲，`selftest` 7/7） | macOS 托盘 / HUD / 开机自启 |
| 租约排他 + 文件锁 + 心跳 + 优先级抢占 + 焦点令牌 | 托管屏"借用"与热插拔回滚 |
| 软件认领 + 只关自己 + `auto undo` | 软件所有权到进程级 |
| auto 10s 武装 + 默认 `auto_close=off` | HUD（缩略图墙/暗化） |
| Rust 托盘（三档/还原/日志/自启，Windows） | `unmanaged_kill` 自动降档（默认关） |
| 配置 + 日志 + 演示节拍 + `ddir demo` | |

macOS 后端的实现/权限/差异：见 [docs/macos-backend.md](docs/macos-backend.md)（任务书 [mac-agent-task.md](docs/mac-agent-task.md) 已归档为历史）。
## 一句话

**给屏幕和软件发租约**：谁要用哪块屏、哪个窗口、哪个软件，先向 `ddir` 申请；拿不到就换方案，而不是互相抢。用户永远是最高优先级，且可以物理隔离（把几块屏收回来自己用）。

> 公司电脑上手清单：[docs/company-onboarding.md](docs/company-onboarding.md)
## 快速开始（Windows x64）

```powershell
# 1) 安装（加 PATH、建 ~/.ddir、跑自检）
powershell -ExecutionPolicy Bypass -File dist\install.ps1

# 2) 新开一个终端
ddir mode              # off / semi / auto
ddir list --text       # 过滤到 Alt-Tab 级的窗口列表
ddir selftest          # 平台能力自检（7 项）
ddir tray              # 托盘常驻（右键：模式 / 全部还原 / 窗口列表 / 开机自启）
ddir autostart on      # 开机自启（注册到 HKCU Run）
ddir auto on                # auto 武装（默认 10 秒倒计时；切回 semi/off 即取消）
ddir auto close --app 记事本 # 只关指定目标；不带 --app 会被拒绝
ddir auto undo             # 把刚关掉的拉回来

# 3) 给 Agent 装上规矩（可选）
powershell -ExecutionPolicy Bypass -File dist\install.ps1 -WithPrompt
```

## 快速开始（macOS arm64，13+）

```bash
git clone https://github.com/al96169/desktop-director ~/desktop-director && cd ~/desktop-director
./mac/build.sh          # swiftc -> ~/Applications/Ddir.app（ddir-dev 签名）-> ~/.local/bin/ddir
ddir selftest           # 7 项平台自检（首次需要给 Ddir 授权"辅助功能"）
ddir mode semi
ddir displays           # 哪块屏归 Agent（单屏时按 D15 托管这块屏）
ddir list --text        # 窗口列表；window 形如 75098:7449
ddir claim --needs "a.txt,b.txt" --force   # 等宽并排
ddir release            # 还原
./mac/test.sh           # 15 项验收（只用 TextEdit 和它自己开的窗口）
```

macOS 的权限与平台差异（`hide` 只能整应用、`close` 不退进程、window-id 不是 hwnd）见
[docs/macos-backend.md](docs/macos-backend.md)。

从源码构建 Windows 版（MinGW-w64 + cargo，环境见 `docs/toolchain.md`）：

```cmd
call tools\dev-env.cmd
cargo build --release
target\release\ddir.exe selftest
```

## 配置与日志

配置文件 `~/.ddir/config.ini`（`ddir config` 查看，`ddir config <key> <value>` 修改）：

| key | 取值 | 默认 | 说明 |
|---|---|---|---|
| `auto_close` | `off` / `minimize` / `close` | **off** | auto 档是否动软件窗口：永不关 / 最小化代替关闭 / 允许 `WM_CLOSE` |
| `countdown_seconds` | 0–300 | 10 | `ddir auto on` 的武装倒计时 |
| `presentation` | `instant` / `paced` | **instant** | 操作后立刻上屏（机器速度）/ 入队按节拍上屏（人看得清） |
| `step_ms` | 50–5000 | 400 | `paced` 时每个动作的间隔 |

日志 `~/.ddir/ddir.log`：每条命令一行（时间 + 动作），`ddir log --lines 40` 查看，托盘右键「查看日志」也能打开。超过 2MB 自动轮转成 `ddir.log.1`。
## 演示（paced）与操作/演示分离

- 默认 `presentation=instant`：`claim` 同步摆好窗口，Agent 拿到确定性结果
- `presentation=paced`（或 `claim --present paced`）：几何**立刻算好、租约立刻生效**，但改动进入展示队列，按 `step_ms` 一个个上屏；`claim` 返回 `pending: N`
- `ddir flush`：立即把队列清空（需要确定性时用）
- `ddir demo`：自动开 3 个演示窗口 → 逐个 claim（带节拍）→ 3 秒后自动还原并关闭，演示完不留痕
- 托盘每 150ms 顺带消费队列，所以 paced 下即使没有 `flush` 也会自己播完
## 三档模式

| 档位 | 屏幕 | 窗口 | 软件 |
|---|---|---|---|
| **off** | 不碰 | 不碰 | 不碰 |
| **semi**（默认） | **仅托管屏**（默认除主屏外全部；新插的屏默认归用户） | 只摆自己拥有的窗口，不越界、不抢焦点 | 只关自己 spawn 的进程，其他只隐藏 |
| **auto** | 全部（可留保留屏） | 可摆所有非保护窗口，空闲时抢焦点 | 按配置：`off`（默认，只摆窗口不关）/ `minimize`（最小化代替关闭）/ `close`（先 10s 武装 → 只发 `WM_CLOSE` → 关不掉不强杀 → 可 `auto undo`） |

## 三类资源 · 三条不变量

| 资源 | 谁在用 | 单写者规则（不变量） |
|---|---|---|
| `display` | 用户 / Agent | 屏有 owner；用户屏一个像素都不碰 |
| `window` | 某个 Agent | **I1 单写者**：一个 `hwnd` 同时只有一个几何 lease |
| `app`（进程） | 某个 Agent | **I3 单负责人**：一个进程同时只有一个 owner，别人不能关 |
| 焦点令牌 | 某个 Agent | **I2 单焦点**：同一时刻只有一个"演示者" |

## 架构

```
          ddir CLI / MCP / HTTP
                   │
            ┌──────▼─────────────────────────── ddir daemon ──────────────┐
            │  规则引擎：屏幕托管 · 仲裁 · 租约 · 软件所有权 · 撤销栈     │
            │      │                     │                    │           │
            │  Win32 执行层          快照/审计              HUD 装饰层(可选) │
            │  枚举/几何/显隐        ~/.ddir/*.jsonl        DWM 缩略图       │
            └─────────────────────── 托盘：三档 + 每屏勾选 + 全部还原 ─────┘
```

## 里程碑

| # | 里程碑 | 状态 |
|---|---|---|
| M0 | 提示词包（`prompts/AGENTS.m0.md`），零安装验证观感 | ✅ **Gate G0 通过**：4/4 任务（DSH×2、Trae×1、隐藏场景×1），见 `docs/m0-observations.md` |
| M1 | 只读：枚举/过滤/显示器/`ddir plan --dry-run` | ✅ **Rust 0.1.0**（338KB 单 exe）：`list/displays/status/plan/selftest` |
| M2 | semi 可写：窗口租约 + 用户所有权 + 撤销 | ✅ `claim/move/hide/show/close/release/own`，`release` 像素级还原，`user_active` 冷却 |
| M2.2 | 屏幕托管：`display_uid` + 托盘勾选 + 借用/热插拔 | 未开始（当前单屏 + 静态托管策略） |
| M2.5 | auto 处决：武装倒计时 + `WM_CLOSE` 管道 + `undo-close` | ✅ 骨架：`ddir auto on/plan/close/undo`，30s 倒计时、只发 `WM_CLOSE`、记录重启路径与位置、`undo` 拉回 |
| M3 | 托盘三档 | ✅ **Rust 原生托盘**（`ddir tray`）：三档切换 / 全部还原 / 窗口列表 / 开机自启 / 单实例，7.8MB 内存 |
| M4 | HUD 装饰层（缩略图墙 / 暗化 / 入场动画） | 未开始 |
| M5 | 多 Agent 仲裁 | ✅ 租约排他 + 文件锁 + 心跳 + 优先级抢占 + 焦点令牌 + `unmanaged_kill` 检测；仅"软件所有权到进程级"未做 |
| M6 | auto × 多 Agent：关闭保护 + `unmanaged_kill` 检测降档 | 未开始 |

> 执行顺序、任务拆分、人日/日历估算与每档 Gate 见 **[docs/plan.md](docs/plan.md)**。
> 建议顺序 `M1 → M2 → M3(最小托盘) → M2.2 → M2.5 → M5 → M6`；R1 到手即"日常可用的半自动"。

## 目录

```
desktop-director/
├─ prompts/AGENTS.m0.md      # M0 安装版（贴进 AGENTS.md / Trae user_rules）
├─ prompts/AGENTS.ddir.md    # M0 详细版（含错误码与理由）
├─ src/                     # Rust 0.1.0（main.rs / win.rs / store.rs）
├─ dist/                    # 可直接用的发布包（ddir.exe + install.ps1 + 提示词 + zip）
├─ tools/ddir-tray.ps1      # 托盘预览版（PowerShell，已被 `ddir tray` 取代）
├─ tools/ddir.ps1|.cmd       # 早期 PowerShell 参考实现（保留作行为对照）
├─ tools/dev-env.cmd          # 开发环境（MinGW-w64 + cargo，见 docs/toolchain.md）
├─ docs/plan.md             # 开发规划：发布节奏、Gate、任务拆分、估时、风险
├─ docs/protocol.md         # 协议草案（两类资源、错误码、不变量、验收用例）
├─ docs/decisions.md        # 已定决策（ADR 简版），避免反复讨论
├─ docs/m0-observations.md  # M0 真实会话测试记录
└─ src/                     # Rust workspace（core / win / mac / linux / hud / cli）
```

## 快速开始（M0）

1. 打开 `prompts/AGENTS.ddir.md`，整段贴进 `~/.dsh/AGENTS.md`（或项目里的 `AGENTS.md`）。
2. 在没有 `ddir` 的机器上它自动跳过（提示词第一条就是"若 `ddir mode` 失败则忽略本节"）。
3. 观察 5 个真实任务：看报错 / 对比网页 / 改代码 / 跑脚本 / 生成图表——重点看**它有没有把不该出现的窗口弄出来**。

## 非目标（明确不做）

- 不做窗口管理器替代品（不接管标题栏、不做贴边吸附）
- 不做虚拟桌面切换（别的桌面上的窗口拿不到 DWM 缩略图，HUD 会失效）
- 不做 Agent 间 P2P 协商（由中央仲裁器替代）
- 不做全局键鼠钩子 / DLL 注入 / 驱动（杀软红线，且没必要）
- 默认不强杀进程（只 `WM_CLOSE`）
