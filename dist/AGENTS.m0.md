# Desktop Director（ddir）— 窗口编排规矩

> 安装版（v1.2，2026-11-03，跨 Harness 实测后修订）。适用于任何接入本机的 Agent。
> 完整版与设计见 `F:\desktop-director\prompts\AGENTS.ddir.md`。

## 什么时候生效

**先跑 `ddir mode`**：
- 命令不存在、或返回 `off` → 忽略本节，按平时方式干活。
- 返回 `semi` / `auto` → 遵守下面的规矩。

## 三条基本命令

```
ddir mode        # off / semi / auto
ddir displays    # managed=true 的屏才归你；owner=user 的屏一个像素都不要碰
ddir status      # 租约、你负责的软件、用户是否在动
```

## 开任务时

1. 先 `ddir claim`，只申请这一步需要的 1–3 个窗口（主窗口 + 参考窗口），说明最小尺寸。
2. 只摆需要的窗口。semi 下其余隐藏；auto 下可交给 `ddir close`。
3. 主窗口占可用区 60–70%，参考窗口 30–40%，中间留 16–24px 缝。
4. 终端用"列×行"表达（约 120×32）；IDE 至少 1200×800。
5. 一次改一个窗口，改完 `ddir status` 确认，再改下一个。
6. 跨屏摆放不算"更大"，算越界；横跨两屏会被拒绝（`spans_displays`）。
7. 用 `--rect` 时**一定加引号**：`ddir move --window 0x... --rect "0,0,1280,918"`；不加引号会被 PowerShell 按逗号拆成 4 个参数。
8. 多余的窗口**收起来而不是关掉**：先 `ddir own --app <名字>`，再 `ddir hide --window <hwnd>`；任务结束 `ddir release --all` 会把隐藏与位置一起还原。
9. 如果 `claim` / `move` 返回 `user_active`，说明用户正在操作：等它空闲，或加 `--force`（并说明理由）。

## 用软件时（防止被别的 Agent 关掉）

```
ddir own --app "Code"      # 开始用之前认领
ddir disown --app "Code"   # 干完还回去
```

- 返回 `owned_by_other` → 别的 Agent 正在用，换实例或换方案，**不要重试**。
- 关闭软件**只能**通过 `ddir close --window <hwnd>`：只能关自己 `own` 过的（否则 `not_owned`），只发 `WM_CLOSE`、等 3 秒；返回 `close_blocked` 说明有未保存内容，**不要重试**。
- **永远不要** `taskkill` / `Stop-Process` / `kill`（绕过会被记 `unmanaged_kill` 并降档）。

## 严禁

- 直接杀进程、切虚拟桌面、进独占全屏
- 移动提权（管理员）窗口
- 在用户屏上摆东西，或把窗口从托管屏挪到用户屏
- 用模拟滚轮/键盘去"滚动内容"（滚动用你自己的工具：UIA / 浏览器 / 终端）
- 用户动过键鼠后 5 秒内移动窗口

## 判断"要不要给用户看"

- 用户要看结果（截图、对比、渲染、网页）→ 必须露出来，给足面积
- 中间态（编译日志、扫描进度）→ 只在失败时露出
- 不确定 → 不露出，给一句话摘要 + "要看的话我可以打开"

## 结束任务

```
ddir release --all     # 还原到 claim 前的位置（除非用户说"保持这样"）
```

## 错误码速查

| 码 | 含义 | 该怎么做 |
|---|---|---|
| `mode_off` | 档位不允许 | 别管窗口，继续干活 |
| `display_not_managed` | 目标在用户屏 | 换到托管屏，或放弃 |
| `spans_displays` | 窗口横跨两屏 | 先 `ddir move --to <display_uid>` |
| `display_borrowed` | 用户临时占用托管屏 | 让位，别抢 |
| `no_free_region` | 排不下 | 降低最小尺寸或减少窗口数 |
| `window_owned_by` | 窗口被别的租约占用 | 换窗口，或提高优先级重试一次 |
| `focus_denied` | 焦点令牌在别人手上 | 别抢，用不激活的方式展示 |
| `owned_by_other` | 软件归别的 Agent | 换实例 / 换方案，别重试 |
| `protected` | 钉住 / 保护清单 / 提权 | 放弃，告知用户 |
| `user_active` | 用户正在用 | 等空闲，或只隐藏 |
| `close_blocked` | 有未保存内容 | 不要重试，告知用户 |
| `quota_exceeded` | 超过 3 窗口 / 3 软件 / 1 焦点 | 先 release 不用的 |
| `stale_lease` | 租约过期 | 重新 claim |
