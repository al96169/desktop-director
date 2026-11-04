# web-dev demo（跨平台脚本）

一个"Agent 做网页开发"的演示：**终端里初始化 Vue 项目 → 写组件 → Playwright 驱动 Edge 开多个页面 →
浏览设计稿 → Finder 看文件 → 预览设计图 → HUD 收尾**。

和 `ddir stage`（Swift，macOS 专属）不同，这套演示是**一个脚本**：窗口决策全部走 `ddir` 的跨平台命令
（`mode/list/move/own/close/release/hud`），只有"怎么打开一个 App"这一步按平台分支。所以同一份
playbook 在 Windows 上也能跑。

## 运行

```bash
# 依赖：node/npm、python3、ddir、Microsoft Edge、VS Code
python3 demo/webdev/run.py            # 完整跑一遍，结束自动收队
python3 demo/webdev/run.py --keep     # 留现场（手动 ddir release + 关窗）
python3 demo/webdev/run.py --fast     # 冒烟
python3 demo/webdev/run.py --clean    # 先删旧的工作副本
```

工作目录：`~/ddir-webdev-demo`（可用 `DDIR_WEBDEV_DIR` 覆盖），日志 `webdev-demo.log`。

## 节拍

| # | 内容 | 谁在动 |
|---|---|---|
| 1 | `npm create vite@latest shop-web -- --template vue-ts` + `npm install` + `npm run dev` | 终端 |
| 2 | 打开 storefront（占位 banner） | Playwright + Edge |
| 3 | 写入 `src/components/FeatureBanner.vue` → Vite HMR 页面实时更新 | 脚本（Agent 的文件写入）|
| 4 | VS Code 打开这个组件，和页面并排 | ddir `move` |
| 5 | Playwright 再开 `/products`、`/about` → 三列 | ddir `move` |
| 6 | 设计稿页面 + Finder 的 `src` 目录 + Preview 看 mockup | ddir `move` |
| 7 | `ddir hud --wall` 缩略图墙，收尾 `ddir release` | ddir |

## 平台差异（都收在 `run.py` 底部几个 helper 里）

| 动作 | macOS（已实测） | Windows（代码已写，未实机验证） |
|---|---|---|
| 终端 | AppleScript `do script` 开新窗（`open -a` 会重放旧会话）| `cmd /c start powershell -NoExit …` |
| VS Code | `code --new-window` | 同（`code.cmd`） |
| 文件夹 | `open <dir>` | `explorer <dir>` |
| 看图 | `open -a Preview a.png b.png` | `os.startfile` |
| Playwright | `channel: 'msedge'`（用系统 Edge，不下载 Chromium）| 同 |

## 已知点

- **不做逐字输入**：VS Code（Electron）会丢 `CGEvent`/剪贴板合成的按键，所以"写代码"是真实的文件写入 +
  HMR，然后打开编辑器展示结果——这也是 Agent 实际的工作方式。
- Windows 的 `SendKeys` 分支仅按文档写好，需要在一台 Windows 机器上跑一次确认（`ddir` 的 Windows 后端命令名一致）。
- Edge 的"翻译此页"气泡：用 `--disable-translate --disable-features=Translate,TranslateUI --lang=en-US` 压掉。

## 文件

| 路径 | 作用 |
|---|---|
| `run.py` | 播放脚本（跨平台）；所有窗口决策走 `ddir` |
| `app/` | 覆盖到 Vite 模板里的文件：`App.vue`、`ProductCard.vue`、占位 `FeatureBanner.vue`、`style.css`、`public/design-refs.html` + 3 张 mockup |
| `typed/FeatureBanner.vue` | 演示中被写入的最终组件（HMR 的 payoff） |
| `pw/open.js` | Playwright：每个 URL 一个窗口（系统 Edge，`channel: msedge`） |
