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

## Gate G0 判定

| 条件 | 结果 |
|---|---|
| ≥3/5 任务"窗口行为不招人烦" | 2/2 通过（样本偏少） |
| 能复现"该藏的藏了" | ❌ **未验证**：两次测试都没有"该隐藏窗口"的场景 |
| 不碰用户窗口 | ✅ 通过（T1 主动避让） |
| 不越权关闭 | ✅ 通过（未出现关闭行为） |

**结论**：G0 **部分通过**。还缺一个"多窗口 + 该隐藏"的真实任务（例如：让 Agent 跑一个会弹多个窗口的任务，看它是否只保留需要的一个）。

## 未验证 / 待办

- Trae CN：规则文件已写入 `~/.trae-cn/user_rules/`，但**无法脚本驱动其聊天**，需要人工开新会话验证（可能需重启 Trae 让规则生效）。
- 单屏策略：托管屏 = 唯一屏（否则 semi 无事可做），见 decisions D15。
- 参考实现不支持 `close`/`own` 的完整语义，`auto` 档位无效。
