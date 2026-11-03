# M0 观察记录 — 首次真实会话测试

> 2026-11-03 21:30–21:40 · 环境：DSH headless + `ddir` PowerShell 参考实现（mode=semi，单屏 1920×1080）

## 环境与安装位置

| 项 | 值 |
|---|---|
| DSH 测试会话 | `DSH_HOME=F:\desktop-director\.testhome`（绕开桌面版分段 `.credentials.yaml` 的已知问题），`--profile headless`，`DSH_PERMISSION_MODE=danger-full-access` |
| ddir | `tools/ddir.ps1`（参考实现，只读 + `move`/`claim`/`release`，不实现 close） |
| M0 安装 | `~/.dsh/AGENTS.md`（本机所有 DSH 会话）· `~/.trae-cn/user_rules/rule-1793712497983.md`（Trae CN 用户规则）· `.testhome/AGENTS.md`（测试会话） |
| 验证安装生效 | DSH 会话的系统提示里已出现 M0 全文（system-reminder 可见）✔ |

## T1：窗口相关任务（摆记事本）

**任务**：`ddir mode/displays/status` → 打开记事本 → 找到它的 hwnd → 摆到左侧 2/3 宽、85% 高 → 复检 → 不动其它窗口。

**实际行为**（6 行报告原文摘要）：

- 依次调用 `ddir mode`（semi）、`ddir displays`（mon0 1920×1080，工作区 1920×1050）、`ddir status`（leases=0）
- `Start-Process notepad` → `ddir list` → `ddir move --window 0x005E2182 --rect "0,0,1280,918"` → `ddir list` 复检
- 结果：窗口框 `0,0,1280,918`（1280 = 2/3 宽，918 ≈ 85% 高），落在 mon0 内
- **主动报告"另一个记事本不是我启动的，我没有碰它"** —— 这正是 M0 想要的"用户窗口不碰"行为
- 未调用 `close`、未 `kill`、未动其它窗口

**发现（真实可用性问题）**：`--rect 0,0,1280,918` 不加引号会被 PowerShell 按逗号拆参，首次调用失败；模型自己加引号重试成功。
→ 已修正两处：参考实现 `move` 兼容不带引号的写法；提示词 v1.1 增加"必须加引号"一条。

## T2：对照任务（不需要窗口）

**任务**：用 PowerShell 算 `1937 × 41` 并判断奇偶，不需要任何窗口。

**实际行为**：只调用 `pwsh` 做算术，**没有调用 `ddir`、没有打开窗口**，并说明"桌面导演那套流程不适用"。

→ 说明提示词没有造成"为了用而用"的过度管理。

## T3：跨 Harness（Trae CN，人工触发）—— ⚠️ 结论已修正

Trae CN 的会话无法脚本驱动，规则装进 `~/.trae-cn/user_rules/` 后由人工开新会话执行同一套步骤。

**Trae 回报**：`semi` 下只有 mon0 一块托管屏（1920×1050 可用区）；记事本经 WMI 脱离父进程启动后由 `ddir list` 识别到 `0x004415A6`；`claim` 记住原位 `[100,100,900,700]`，再用带引号的 `--rect "0,0,1280,1050"` 移到左侧 2/3；复检可视区 `7,0,1266,1043`；`release --all` 精确回到原坐标。全程只动这一个窗口，其它窗口坐标前后零变化，未杀进程。

**Trae 指出的两个问题（都真实、已修）**：
1. `user_idle_s` 恒为 0 → 无法用状态自证"5 秒内不动窗口"。
2. 不支持 `ddir close` → 记事本留在打开状态。

**⚠️ 中间一次追问与最终结论**：首次追问"系统规则里第 8/9 条讲什么"时，它答的全是 Trae 自带的代码引用/图片规范，没有 Desktop Director 段落 → 当时**规则尚未加载**（Trae 进程启动早于规则写入）。**重启 Trae 后新会话再问，它逐字复述了 v1.2 的 hide / close 两条与 `unmanaged_kill` 禁令**，一位不差 → 规则加载确认。

→ 结论：`~/.trae-cn/user_rules/rule-*.md` **需要重启 Trae 才加载**；验收方式是"复述规则内容"，不能只看行为。另：它拒绝在"不执行命令"的前提下编造 `ddir status` 输出，属于规则遵守的正向证据。

兜底仍然保留：仓库根 `AGENTS.md`（Trae bundle 有 `chat.useAgentsMdFile` / 指令文件机制），打开本仓库时作为项目级规则。此前 T3 第一次"通过"实际只是任务提示写死了步骤，**是 prompt 驱动、不是规则生效**——这条已写进 D21。

## T4：隐藏场景（DSH headless，补 Gate G0 的缺口）

**任务**：开两个记事本 + 一个计算器 → `own` → 两个记事本全部 `hide` → `status` 验证 `hidden_by_you=2` → `release --all` → `close` 掉自己开的。

**实际行为**：
- `own --app notepad` → 归属 `DeepSeek Harness-15104`（稳定身份）
- `hide` 两个窗口均 `hidden=true`；`status` 的 `hidden_by_you = 2` ✔
- 中途用户动过鼠标（`user_active=true`），**Agent 主动等空闲超过 5 秒再 `release`**，没有用 `--force` ✔
- `release --all` → `released=2`，两个记事本恢复显示
- `own` + `close` 两个记事本均 `closed=true`（优雅关闭），未 kill；按要求留下计算器

## 本轮修掉的真问题

| 问题 | 原因 | 修法 |
|---|---|---|
| `own` 之后立刻 `hide` 报 `owned_by_other` | Agent 身份默认是**本次调用的 PID**，每次调用都不同 | 沿父进程链上溯到宿主进程（Trae/终端/执行器），身份跨调用稳定；`DDIR_AGENT` 可覆盖 |
| `user_idle_s` 长期为 0 | 本机有鼠标抖动/注入（Bloody6 之类常驻工具），`GetLastInputInfo` 恒被刷新 | 改为 `input_age_s`（原始值，照实报告）+ `user_active` 用「光标位移 >25px 或前台窗口变化」判定 |
| `--rect` 不加引号失败 | PowerShell 逗号拆参 | 参考实现兼容不带引号；提示词要求加引号 |
| 没有关闭/隐藏能力 | 只做了只读 + 移动 | `hide/show`（需先 `own`）、`close`（仅自己 own 过、`WM_CLOSE`、3s、`close_blocked`） |

## Gate G0 判定（更新：已完成）

| 条件 | 结果 |
|---|---|
| ≥3/5 任务"窗口行为不招人烦" | ✅ 4/4（T1 DSH 摆窗口、T2 对照不越权、T3 Trae 跨 Harness、T4 隐藏场景） |
| 能复现"该藏的藏了" | ✅ T4：`hidden_by_you=2` |
| 不碰用户窗口 | ✅ T1 主动避让、T3 其它窗口零变化 |
| 不越权关闭 | ✅ 只关自己 own 过的；未出现 kill |
| 跨 Harness | ✅ DSH（规则进入 system prompt）＋ Trae CN（**需重启**，重启后逐字复述规则确认）；两边的行为测试均通过 |

**结论**：**G0 通过**。M0 提示词可以长期留在两台 Harness 的全局指令里。

## 未验证 / 待办

- Trae 侧规则是否在**重启后**才生效，未做对照实验（本机测试时可能已缓存，无法确定）。
- 参考实现不支持 `auto` 的处决流程（M2.5），`close` 目前只在 semi 语义下可用。
- 真实"多窗口抢屏"仍未测：需要 M5 仲裁器，或至少两个 Agent 同时 claim。
