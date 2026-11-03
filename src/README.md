# src/

Rust workspace，从 **M1** 开始（见 `docs/decisions.md` D11 修订与 `docs/plan.md`）。

| crate | 职责 | 依赖 |
|---|---|---|
| `ddir-core` | 纯逻辑：模型/租约/仲裁/策略/布局/回放。**零 Win32**，CI 可跑 | 无平台依赖 |
| `ddir-win` | Win32 后端：枚举+过滤、几何、DPI、显示器、进程、`WM_CLOSE` | `windows` crate |
| `ddir-hud` | 装饰层 + DWM 缩略图合成层（R4） | Direct2D/GDI |
| `ddir-cli` | bin：CLI、命名管道、托盘、配置 | 以上三者 |

**第一条 commit 应该是**：`ddir list --json` —— 枚举 + 过滤 + 输出与 Alt+Tab 同级的窗口列表，纯只读。

**开发期铁律**：写操作（`SetWindowPos` / `WM_CLOSE`）只在 `feature = "write"` 下编译；默认二进制里没有它们（D13）。
