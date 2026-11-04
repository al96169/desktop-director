# Desktop Director（ddir）— 窗口编排规矩

> 安装版 v2.0（2026-11-05）。适用任何接入本机的 Agent；不依赖具体 Harness。Windows / macOS 同一套命令。
> 安装方式：把本文件整段贴进你所用的全局指令（`~/.dsh/AGENTS.md`、`CLAUDE.md`、`AGENTS.md` 等）。
> 详细设计见仓库 `prompts/AGENTS.ddir.md`，命令全集见 `ddir help`。

## 什么时候生效

先跑 `ddir mode`：

- 命令不存在 → 忽略本节，按平时方式干活。
- 返回 `off` → 忽略本节。此时 `move`/`hide`/`close`/`claim` 一律返回 `mode_off`。
- 返回 `semi` / `auto` → 遵守下面的规矩。

## 三条基本命令

```
ddir mode                  # off / semi / auto
ddir displays              # 哪些屏归你（managed）；其余是用户的
ddir status                # 我的租约、我负责的软件、焦点令牌、用户是否在动
```

## 平台差异（先看 `ddir status` 的 `caps`）

- **window-id 的写法**：Windows 是 `0x001A2B3C`；macOS 是 `pid:CGWindowNumber`（如 `75098:7449`）。都从 `ddir list` 复制，不要自己拼。
- **macOS 的 hide 是整应用**（`caps.window_hide == "app"`）：`hide` 会把该应用的所有窗口一起隐起来，`release` 一起恢复。想只藏一个窗口就在 macOS 上用最小化或直接不改。
- **`permission_required`**：macOS 需要"系统设置 → 隐私与安全性 → 辅助功能"里勾选 `Ddir`；没授权时所有写操作都返回这个码，只读命令（`list`/`status`）仍可用。
- **`unsupported_on_platform`**：只为真正没实现的能力返回（如 Windows HUD、Linux 后端）；macOS 的托盘/自启/HUD 都已可用，别绕路自建。
- **可视化**：交接或演示时可以让用户看一眼你接管了什么：`ddir hud`（右下角小卡，3 秒，默认）/ `ddir hud --wall`（全屏缩略图墙，6 秒）。它只读、不抢焦点、点一下就穿过去，不要用它替代 `ddir status` 的判断。
- **排障**：先 `ddir doctor`（权限/签名/托盘/自启/提示词是否就位）；它比逐条试错快。

## 开任务时

1. 先 `ddir claim`，只申请这一步需要的 1–3 个窗口（主窗口 + 参考窗口）。
2. 只摆需要的窗口；semi 下其余隐藏，auto 下可交给 `ddir close`（默认配置不会关）。
3. **并排，不叠放**：`claim` 会把**本 Agent 已持有的窗口 + 本次新增**一起做等宽重排（1/2/3 列，间隔 16px）。所以一次 `claim` 把要用的窗口说全，之后每加一个都会重排。
4. 返回 `{lease, assign:[{window,rect,retiled}], pending, preempted}`；`retiled:true` 表示这一列是被重排的旧窗口。
5. **新开的软件常落在主屏**：`claim` 会跨屏匹配窗口并把它拉到托管屏，`release` 再放回原位置。不用先手动搬。
6. 终端用"列×行"表达（约 120×32）；IDE 至少 1200×800。
7. 一次只改一个窗口的几何，改完 `ddir status` 确认，再改下一个。
8. `--rect` 必须加引号：`ddir move --window <window-id> --rect "0,0,1280,918"`（不加会被 shell 按逗号拆参）。
9. 多余的窗口**收起来而不是关掉**：`ddir hide --window <window-id>`（会记一条 `action=hide` 的租约，`release` 能恢复）；`ddir own --app <名字>` 是给软件上"负责人"标记，防止别的 Agent 关它。
10. 返回 `user_active` 时说明用户正在操作：等它空闲，或加 `--force` 并说明理由。

## 用软件时

```
ddir own --app "Code"        # 开始用之前认领（跨调用稳定，按宿主进程识别）
ddir disown --app "Code"     # 干完还回去
```

- `own` 返回 `owned_by_other` → 换实例或换方案，**不要重试**。
- 关闭只能 `ddir close --window <window-id>`：只能关自己 `own` 过的，发关闭请求后等 3 秒（Windows `WM_CLOSE` / macOS AX 关闭按钮）；`close_blocked` 表示有未保存内容，**不要重试**。
- **永远不要** `taskkill` / `Stop-Process` / `kill`。绕过会被记 `unmanaged_kill`。

## 多个 Agent 并存时

- 长任务**每 2 分钟** `ddir heartbeat`（租约 TTL 5 分钟，不续会被别人抢）。
- `claim` 返回 `window_owned_by` → 换窗口或换方案；确认自己优先级更高才 `--priority high` 重试一次，**不要循环**。
- 优先级：`--priority low|normal|high|user`。高优可抢占低优，条件是对方租约 >60 秒且窗口不在前台。
- 需要独占前台（演示、让用户看结果）先 `ddir focus`（120 秒），结束 `ddir focus release`；`focus_denied` 就不要抢。

## auto 档额外规矩

- **auto 默认不关任何窗口**（`auto_close=off`）。要动窗口必须用户先在配置里改成 `minimize` 或 `close`，否则 `auto close` 返回 `auto_close_disabled`。
- 需要关闭时先武装：`ddir auto on`（默认 10 秒倒计时，期间用户切回 semi/off 即取消）；未武装返回 `needs_user_consent`。
- `ddir auto close` 不带 `--app` 会被拒（`needs_explicit_target`）；优先 `ddir auto close --app <名字>`。
- 关错了用 `ddir auto undo` 拉回来（位置也会还原）。

## 配置与日志

- `ddir config` 查看；`ddir config <key> <value>` 修改。常用：`auto_close`、`presentation`、`step_ms`、`countdown_seconds`、`managed_displays`。
- 演示节奏：`ddir config presentation paced` + `ddir config step_ms 700`；Agent 日常保持 `instant`。
- 出问题先看日志：`ddir log --lines 50`（`~/.ddir/ddir.log`）。

## 严禁

- 直接杀进程、切虚拟桌面、进独占全屏
- 移动提权（管理员）窗口
- 在用户屏上摆东西，或把窗口从托管屏挪到用户屏
- 用模拟滚轮/键盘去"滚动内容"（滚动用你自己的工具：UIA / 浏览器 / 终端）
- 用户动过键鼠后立刻搬窗口（等 `user_active=false`）

## 演示（给用户看，不是表演）

演示的目的是**让用户看见结果**，不是炫技。默认按这个来，别做重：

- **不要逐字敲代码**。模拟键盘在 VS Code / 浏览器里会丢字（Electron 和输入法都不吃合成按键），
  又慢又费 token。正确做法：把文件写进去（本来就是你的编辑动作）→ 页面 / 编辑器自己刷新 →
  开窗并排给用户看结果。
- **预算：几秒、几条命令**。默认只做三步：`ddir claim` 把相关窗口并排 →（可选）`ddir hud` 提示一下 →
  `ddir release` 收队。不要为演示重排整个桌面、不要反复录屏、不要写动画脚本。
- **优先复用现成的**，不要每次现编流程：
  - macOS：`ddir stage run`（科幻风，一条命令，自带回滚）
  - 跨平台：`python3 demo/webdev/run.py`（终端初始化 Vue → 写组件 → Playwright/Edge 多页 →
    设计稿 → 文件位置 → 看图；`--fast` 冒烟、`--keep` 留现场）
- 用户没要求时**不必专门准备演示**：任务本身有可见成果（页面、界面、报告）时，
  顺手 `claim` 出来让用户看一眼就够。
- 演示完 `ddir release`；演示用的窗口 `ddir close` 掉，别留垃圾。
- **媒体播放**：`ddir play <file> [--detach]`（视频/音频都行，可同时开多个、各自平铺）。
  `play` 会前台运行到窗口关闭；脚本里要开多个就用 `--detach`。
- **`move` 会记租约**：`ddir move --force` 之后 `ddir release` 能还原（不要用完 move 就忘了收队）。
- 演示前确认 `ddir mode` 不是 `off`（off 时写操作一律被拒）；演完切回 `off`。

## 判断"要不要给用户看"

- 用户要看结果（截图、对比、渲染、网页）→ 必须露出来，给足面积
- 中间态（编译日志、扫描进度）→ 只在失败时露出
- 不确定 → 不露出，给一句话摘要 + "要看的话我可以打开"

## 结束任务

```
ddir release              # 还原我的租约（位置与隐藏都会恢复）
```

## 错误码速查

| 码 | 含义 | 该怎么做 |
|---|---|---|
| `mode_off` | 当前档位不允许 | 先 `ddir mode semi`，或别管窗口 |
| `display_not_managed` | 目标在用户屏 / 没有托管屏 | 换到托管屏，或 `ddir displays --manage <uid>` |
| `spans_displays` | 窗口横跨两屏 | 先挪到单屏 |
| `no_free_region` | 排不下 | 降低最小尺寸或减少窗口数 |
| `window_owned_by` | 窗口被别的租约占用 | 换窗口，或 `--priority high` 重试一次 |
| `focus_denied` | 焦点令牌在别人手上 | 别抢 |
| `owned_by_other` | 软件归别的 Agent | 换实例 / 换方案 |
| `user_active` | 用户正在用 | 等空闲，或 `--force` |
| `close_blocked` | 有未保存内容 | 不要重试 |
| `quota_exceeded` | 超过 3 个窗口 | 先 `release` |
| `stale_lease` | 租约过期 | 重新 `claim` + `heartbeat` |
| `auto_close_disabled` | 配置禁止自动关窗 | 不要尝试关闭 |
| `needs_user_consent` | 需要先武装 | 让用户 `ddir auto on` |
| `needs_explicit_target` | 不允许自动挑目标 | 用 `--app` 指定 |
