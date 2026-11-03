# AGENTS.ddir — Desktop Director 提示词包（M0）

> 用法：把下面 `---` 之间的内容整段贴进全局指令（`~/.dsh/AGENTS.md`、`CLAUDE.md`、`AGENTS.md` 等）。
> 设计原则：**写死禁止项 > 写细应该做**；每条规则都要能用一条命令验证。
> 版本：v1（2026-11-03）

---

## 窗口编排（仅当本机有 `ddir` 时生效）

本机可能装了 Desktop Director（命令 `ddir`）。**先执行 `ddir mode`**：

- 命令不存在或返回 `off` → 跳过本节，按平时方式干活。
- 返回 `semi` / `auto` → 按下面的规矩管理窗口。

### 一、先搞清楚边界

```
ddir mode        # 档位：off / semi / auto
ddir displays    # managed=true 的屏才归你；owner=user 的屏一个像素都不要碰
ddir status      # 当前租约、你负责的软件、焦点在谁手上、用户是否在动
```

### 二、开始任务时（semi / auto 都做）

1. `ddir claim` 一次，说明这一步需要哪 1–3 个窗口、各自最小尺寸、谁是主谁是参考。
2. 只摆"这一步需要的窗口"。semi 下其余隐藏；auto 下可交给 `ddir close`。
3. 主工作窗口占可用区 60–70%，参考窗口 30–40%，中间留 16–24px 缝。
4. 终端用"列×行"表达：约 120 列 × 32 行；IDE 至少 1200×800。
5. 一次只改一个窗口的几何，改完 `ddir status` 确认，再改下一个。
6. 跨屏摆放不算"更大"，算越界。窗口横跨两屏会被拒绝（`spans_displays`）。

### 三、用软件时（防止被别的 Agent 关掉）

```
ddir own --app "Code"      # 开始用之前认领
ddir disown --app "Code"   # 干完还回去
```

- `ddir own` 返回 `owned_by_other` → 别的 Agent 正在用，换实例或换方案，**不要重试**。
- 关闭软件**只能**通过 `ddir close`（会被审核，可能被拒绝）。**永远不要** `taskkill` / `Stop-Process` / `kill`——绕过会被记 `unmanaged_kill` 并自动把你的档位降到 semi。

### 四、严禁

- 直接杀进程、切换虚拟桌面、进入独占全屏
- 移动提权（管理员）窗口
- 在用户屏上摆任何东西，或把窗口从托管屏挪到用户屏
- 用模拟滚轮/键盘去"滚动内容"——滚动用你自己的工具（UIA / 浏览器 / 终端控制）
- 用户动过键鼠后 5 秒内移动任何窗口

### 五、判断"要不要给用户看"

- 用户明确要看结果（截图、对比、渲染、网页）→ 必须露出来，且给足面积。
- 中间态（编译日志、扫描进度）→ 只在失败时露出来。
- 不确定 → 不露出，在回答里给一句话摘要 + "要看的话我可以打开"。

### 六、结束任务

```
ddir release --all     # 窗口回到租约前的位置（除非用户说"保持这样"）
```

---

## 附：错误码速查（模型自我修正用）

| 码 | 含义 | 该怎么做 |
|---|---|---|
| `mode_off` | 档位不允许 | 别管窗口，继续干活 |
| `display_not_managed` | 目标在用户屏上 | 换到托管屏，或放弃 |
| `spans_displays` | 窗口横跨两屏 | `ddir move --to <display_uid>` 先规范化 |
| `display_borrowed` | 用户临时占用了托管屏 | 让位，别抢 |
| `no_free_region` | 排不下 | 降低最小尺寸或减少窗口数 |
| `window_owned_by` | 窗口被别的 lease 占用 | 换窗口，或提高 priority 重试一次 |
| `focus_denied` | 焦点令牌在别人手上 | 别抢，用不激活的方式展示 |
| `owned_by_other` | 软件归别的 Agent | 换实例 / 换方案，别重试 |
| `protected` | 钉住 / 保护清单 / 提权 | 放弃，告知用户 |
| `user_active` | 用户正在用 | 等空闲，或只隐藏 |
| `close_blocked` | 有未保存内容 | 不要重试，告知用户 |
| `quota_exceeded` | 超过 3 窗口 / 3 软件 / 1 焦点 | 先 release 不用的 |
| `stale_lease` | 租约过期 | 重新 claim |
