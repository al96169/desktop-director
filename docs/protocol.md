# 协议草案 v0.1

> 状态：草案（M1 前冻结第一版）。任何 Agent / Harness 只要会说这几条命令，就能接入。
> 关键现实：**Agent 的上下文推不进通知**，所以状态必须挂在每次调用的返回值里。

## 0. 传输

| 通道 | 用途 |
|---|---|
| 命名管道 `\\.\pipe\ddir` | CLI ↔ daemon，主通道 |
| `127.0.0.1:7717` HTTP（+SSE `/events`） | 跨语言适配器、外部看板、Harness hooks。**只监听 localhost** |
| MCP stdio | 有 MCP 的 Harness，工具名：`ddir_claim` / `ddir_status` / `ddir_own` / `ddir_close` |
| `~/.ddir/state.json` | 落盘、调试、崩溃恢复 |

CLI 子命令与 op 一一对应：`ddir mode|displays|status|claim|release|own|disown|close|undo-close|board|restore`。

## 1. 资源模型

```
display  (uid, gdi, rect, work, dpi, owner: user|agent, borrowed_by_user)
window   (hwnd, app, display, rect, z, visible)      —— 几何面，租约独占
app      (procid, exe, pids, owner: agent|user|idle, pinned, restart)  —— 生命周期面，负责人独占
focus    (holder: agent_id, until)                   —— 全局唯一
```

### 三条不变量（违反即 bug，必须写断言）

| 编号 | 内容 |
|---|---|
| **I1 单写者** | 一个 `hwnd` 同一时刻只能有一个几何 lease |
| **I2 单焦点** | 同一时刻 `focus.holder` 唯一；semi 下恒为 `none` |
| **I3 单负责人** | 一个进程同一时刻只有一个 owner；`close` 只对"自己 / idle(仅 auto)"生效 |

## 2. 屏幕：托管与借用

```jsonc
{ "op": "displays" }
// →
{ "ok": true,
  "managed": [ { "uid": "u_9c11…", "gdi": "\\\\.\\DISPLAY2", "label": "副屏 2560×1440",
                 "dpi": 144, "work": [2560, 0, 2560, 1400], "borrowed_by_user": false } ],
  "user":    [ { "uid": "u_4f2a…", "gdi": "\\\\.\\DISPLAY1", "label": "主屏 1920×1080" } ] }
```

- `owner` 由用户通过托盘设置；**新屏默认 `user`**。
- semi 默认托管 = 除主屏外全部（`mode_defaults.semi = "all_except_primary"`）。
- 用户光标/前台窗口落在托管屏 → 该屏 `borrowed_by_user = true`，Agent 让位；30 分钟无操作归还。
- 取消托管 / 拔线 → 该屏 lease 全部 `display_lost`，窗口回滚（**不关闭**），窗口不清空。

## 3. 窗口：claim / release

```jsonc
// 请求
{ "op": "claim", "agent": "dsh-7f3a", "task": "review-pr-412",
  "priority": "normal",                     // low | normal | high | user
  "needs": [
    { "role": "primary",   "match": { "app": "Code" },   "min": { "w": 1000, "h": 700 } },
    { "role": "reference", "match": { "app": "msedge" }, "min": { "w": 600,  "h": 500 } }
  ],
  "avoid_user_overlap": true, "ttl_s": 900, "wait_s": 0 }

// 成功
{ "ok": true, "lease": "ls_9c1", "mode": "semi",
  "displays_managed": ["u_9c11…"],
  "assign": [
    { "window": "0x001A2B3C", "app": "Code",   "display": "u_9c11…", "rect": [24,24,1104,900],  "z": "normal", "action": "move" },
    { "window": "0x004D5E6F", "app": "msedge", "display": "u_9c11…", "rect": [1144,24,752,900], "z": "normal", "action": "reveal" }
  ],
  "focus": "none", "notes": ["DISPLAY1 归用户，不可摆"] }
```

- `claim` **总是重排**：把本 Agent 已持有的窗口和本次新增窗口一起做等宽并排（side-by-side），不会叠放；`retiled: true` 表示该窗口是被重排的旧窗口。
- `wait_s ≤ 3`，默认 0（**立即返回**）。禁止"持有租约时轮询等待别人"——死锁唯一来源。
- 单次 `needs` 最多 3 项；单 Agent 同时最多 3 个窗口 lease。
- `release`：`{ "op":"release", "lease":"ls_9c1", "restore": true }`，`restore` 默认 true（回到快照）。

## 4. 软件：own / close / undo

```jsonc
{ "op": "own",    "agent": "dsh-7f3a", "app": "Code", "ttl_s": 1800 }
{ "op": "disown", "agent": "dsh-7f3a", "app": "Code" }

// 关闭（dry_run 先预演；auto 之外一律拒绝）
{ "op": "close", "agent": "dsh-7f3a", "target": { "app": "Steam" }, "reason": "free_ram", "dry_run": true }
// 拒绝示例
{ "ok": false, "error": "owned_by_other", "owner_agent": "dsh-91be", "owner_since": "20:29:12",
  "hint": "该软件被另一个 Agent 认领；换实例，或等它 disown" }

{ "op": "undo_close", "batch": "cl_71" }
```

### 关闭许可矩阵（`close` 的唯一裁决，Agent 说什么都不能越过）

| 目标 owner | semi | auto |
|---|---|---|
| 自己 | ✅ | ✅ |
| 别的 Agent | ❌ `owned_by_other` | ❌ `owned_by_other` |
| user（30 分钟内操作过） | ❌ `user_active` | ❌ `user_active` |
| idle（30 分钟没动 / 无主） | ❌ | ✅（过武装清单 + 每轮 ≤3） |
| pinned / 保护清单 / 提权 / 系统关键 | ❌ | ❌ `protected` |

### 处决三段式

1. **武装**：`ddir auto on` → 三栏清单（将关闭 / 将保护 / 不确定）+ 30s 倒计时（用户输入即暂停）+ 取消/保护入口。
2. **处决**：每轮 ≤3 个，`PostMessage(WM_CLOSE)` → 等 8s → 没退 = `close_blocked`，不重试、不强杀。
3. **撤销**：关闭前记 `restart{cmd,args,cwd,rect}`，`ddir undo-close` 重启还原；记录留 24h。

## 4.5 平台能力（`status` / `mode` 返回）

```jsonc
{
  "platform": "windows|macos|linux-x11|linux-wayland-hyprland|linux-wayland-kwin|linux-wayland-other",
  "caps": {
    "window_move": true,
    "window_hide": "window|app|false",
    "window_close": true,
    "focus_control": true,
    "display_enumerate": true,
    "thumbnail": true,
    "idle_signal": "input|cursor|none",
    "accessibility": true,
    "screen_recording": true
  }
}
```

- `window_hide` 是枚举而不是布尔：macOS 只能"整应用隐藏"（`app`），Windows 可以单窗口（`window`），Wayland 多半是 `false`
- 写操作在不支持时返回 `unsupported_on_platform` / `permission_required`（macOS TCC）/ `compositor_unsupported`（Wayland 合成器未实现）
- 详见 `docs/platforms.md` 的能力矩阵
## 5. 状态（每次工具调用都带一次）

```jsonc
{ "ok": true, "mode": "auto", "you": "dsh-7f3a",
  "leases": 2, "owns": ["proc_9182"], "focus_holder": "dsh-7f3a",
  "user_active": false, "user_idle_s": 412, "screen_busy": 0.62,
  "recently_closed": 1, "undo_available": true }
```

## 6. 错误码

`mode_off` · `display_not_managed` · `spans_displays` · `display_borrowed` · `display_lost` ·
`no_free_region` · `window_owned_by` · `focus_denied` · `quota_exceeded` ·
`owned_by_other` · `protected` · `user_active` · `close_blocked` · `restart_partial` ·
`needs_user_consent` · `uipi_denied` · `app_refuses_resize` · `stale_lease` · `unmanaged_kill` · `unsupported_on_platform` · `permission_required` · `compositor_unsupported`

## 7. 仲裁规则

1. 可用区域 = 托管屏工作区 − 用户保护窗口 − 托盘预留；用户屏与借用屏整块排除。
2. 单屏内 guillotine 切割 + 权重（primary 2 : reference 1）；默认不跨屏。
3. 排他 + 先到先得 + 老化（等待 > 5 分钟提半级）。
4. 非阻塞；`wait_s ≤ 3`。
5. 抢占矩阵 `user > high > normal > low`；不抢前台窗口、不抢未过期租约。
6. **抢占只回滚几何，绝不关闭。**
7. 稳定 tie-break：`agent_id` 哈希 + 单调序号（防抖动）。
8. 配额：3 窗口 lease / 3 软件 owner / 1 焦点令牌。

## 8. 验收用例（M5 的 Definition of Done）

| 用例 | 期望 |
|---|---|
| 3 Agent 同时 claim 同一窗口 | 1 成功 2 收 `window_owned_by`，无抖动 |
| 3 Agent claim 不同窗口 | 矩形两两交集面积 = 0 |
| A 关闭 B 已 own 的软件 | 收 `owned_by_other`，B 的软件存活 |
| 关闭标题带 `*` 的文档 | `close_blocked`，进程存活，有审计 |
| 用户按任意键 | 所有 lease `yielded`，5 分钟不自动恢复 |
| 心跳停 90s | 租约过期 → 窗口回滚 |
| claim 用户屏上的窗口 | `display_not_managed`，零像素位移 |
| 窗口横跨两屏 | `spans_displays`，不执行移动 |
| 用户在托管屏点一下 | `borrowed_by_user`，30 分钟内不让位回来 |
| 拔掉托管屏 | 该屏 lease 全 `display_lost`，窗口回滚，无丢失 |
| 150%/100% DPI 各一屏 | 各屏内像素误差 ≤ 1px |
| 100 次随机 claim/own/close 回放 | 无死锁、无 owner 泄漏、状态收敛 |

## 9. 版本与兼容

- 协议 `X.Y`；daemon 返回 `proto` 字段，客户端不匹配时降级到基础 op。
- 新增 op 只为增量；**错误码只增不改**（Agent 的提示词里写死了处理方式）。
