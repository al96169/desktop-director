# src/

代码从 **M1** 开始。按 `docs/decisions.md` D11，分两段：

| 目录 | 内容 | 语言 |
|---|---|---|
| `proto/` | 协议原型：`claim/own/close/revoke` 状态机 + 假窗口后端（不碰真桌面，可在 CI 跑） | Node 18+，零依赖 |
| `app/` | 正式版：Win32 执行层 + 托盘 + HUD | Rust（`windows` crate） |

`proto/` 的验收标准是 `docs/protocol.md` §8 的 12 条用例全部通过；`app/` 只允许在 `proto/` 冻结后开工。

（M1 的第一个提交应该是 `ddir list --json`：枚举 + 过滤 + 输出与 Alt+Tab 一致的窗口列表，只读。）
