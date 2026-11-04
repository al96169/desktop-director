# AGENTS.ddir — 提示词包说明（规则真源是 AGENTS.m0.md）

> 这份文件只解释"为什么这么写"，**规则本身以 `prompts/AGENTS.m0.md` 为唯一真源**。
> 安装时贴 `AGENTS.m0.md`，不要贴这份。版本 v1.7（2026-11-04）。

## 为什么把规则写成现在这样

| 规则 | 为什么 | 代码里对应的行为 |
|---|---|---|
| 先跑 `ddir mode`，`off` 就整节跳过 | 没装/关掉时提示词必须无副作用 | `move`/`hide`/`close`/`claim` 在 off 档统一返回 `mode_off` |
| 一次 claim 说全 1–3 个窗口 | 每次 claim 都会重排**本 Agent 已持有的窗口**，分批 claim 会让旧窗口反复移动 | `claim` 返回 `assign[].retiled`，超过 3 个返回 `quota_exceeded` |
| 并排、不叠放 | 用户实测反馈：新窗口压住旧窗口，内容被遮 | 等宽列布局（1=满宽 / 2=各半 / 3=各 1/3，间隔 16px） |
| 新窗口落在主屏也要能摆 | 新开的软件默认落在主屏，而 semi 只托管副屏 | `claim` 跨屏匹配窗口并拉到托管屏；`release` 放回原位 |
| `hide` 而不是关掉 | 关闭是唯一会丢数据的动作 | `hide` 记 `action=hide` 租约；`release` 恢复显示 |
| 关闭必须先 `own` + 只发 `WM_CLOSE` | 未保存内容检测只能靠"关不掉"来发现 | `close` 等 3 秒 → `close_blocked`，不重试不强杀 |
| 永远不要 taskkill | 同权限下拦不住，只能事后发现 | 托盘每 3 秒比对窗口集合 → `unmanaged_kill` 审计 |
| 长任务每 2 分钟 heartbeat | 租约 TTL 300 秒，长任务中途会被别人抢 | `ddir heartbeat` 续期租约与软件认领 |
| `--priority high` 只能重试一次 | 抢占条件严格（对方 >60s 且窗口不在前台），循环重试只会互相抖 | 抢占写 `preempt` 审计，返回 `preempted` |
| 焦点令牌 | z-order/前台只有一个，不能靠抢 | `ddir focus` 120s，冲突返回 `focus_denied` |
| auto 默认不关窗口 | 关软件是最高风险动作，默认必须安全 | `auto_close=off`；`close` 返回 `auto_close_disabled` |
| 出问题看日志 | Agent 无法把日志推给用户 | `~/.ddir/ddir.log`，`ddir log --lines N` |

## 与代码同步的检查清单

改行为时，这三处必须一起改：

1. `prompts/AGENTS.m0.md`（Agent 看的规则）
2. `ddir help` 的命令说明
3. `README.md` 的对应章节

`ddir selftest` 只验证平台能力，不验证提示词与实现一致——一致性靠 review。

## 安装位置

- 全局指令：各 Harness 的 `AGENTS.md` / `CLAUDE.md` / 用户规则（内容 = `AGENTS.m0.md`）
- 项目级兜底：仓库根 `AGENTS.md`
- 测试环境：独立 `DSH_HOME`（见 `docs/m0-observations.md`）
