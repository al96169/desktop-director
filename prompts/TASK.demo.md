# 演示任务提示词（贴给任意新会话）

> 用法：把下面整段作为任务提示词发给你的 Agent（新会话即可）。它自己会读 `~/.dsh/AGENTS.md`
> 里的 ddir 规则并按需编排窗口；你只需要补一句"要演示什么"。

---

用 **ddir** 管理这次演示的窗口（先跑 `ddir mode`；返回 `off` 就先 `ddir mode semi`，
演示结束切回 `off`）。规则见 `~/.dsh/AGENTS.md` 的「演示」一节，要点：

1. **不要逐字敲代码**：把文件写进去（你的正常编辑动作）→ 页面/编辑器自己刷新 → 开窗给用户看结果。
2. **轻量**：`ddir claim` 把相关窗口并排（最多 3 列）→ 需要时 `ddir hud` 提示一下 → `ddir release` 收队。
   不要为演示重排整个桌面、不要反复录屏、不要写动画脚本。
3. 多开窗口时用 `ddir list` 拿窗口 id（macOS `pid:cgwin` / Windows `0x...`），
   `ddir move --window <id> --rect "x,y,w,h" --force` 精确排布；`move` 会记租约，`release` 能还原。
4. 同时播放视频/音频时，每个文件一个播放器窗口：
   - macOS：`ddir play <file> --detach`（视频/音频都行，2x2 平铺）
   - Windows：`start "" "<file>"` 用系统播放器打开，再用 `ddir list`/`ddir move` 平铺
5. 演示用的临时窗口，最后 `ddir close --window <id>` 关掉（先 `ddir own --app <app>`），别留垃圾。

**这次要演示的内容**：<在这里写你的需求>

**交付**：录屏一段（工具随你：macOS `screencapture -v`，Windows Xbox Game Bar `Win+G` 或 OBS），
再加 3–5 张关键帧截图；结束时 `ddir status` 应为 0 租约、无残留窗口。
