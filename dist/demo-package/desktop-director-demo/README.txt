Desktop Director — web-dev demo (Windows)
=========================================

一个 90 秒的"Agent 做网页开发"演示：终端初始化 Vue 项目 → 写组件触发 HMR →
Playwright/Edge 开三列页面 → VS Code 并排 → 设计稿 + Explorer + Photos → 4 个媒体窗口 2x2。

前置条件
--------
- Windows 10/11 x64
- Python 3.9+      （没有：winget install Python.Python.3.12，装完开新终端）
- Node.js 20+      （没有：winget install OpenJS.NodeJS.LTS）
- Microsoft Edge   （系统自带）
- VS Code          （可选；没有就少一列代码）
- 能访问 npm registry（第一次要 npm install + playwright-core）

第一次运行
----------
1) 解压整个 desktop-director-demo 文件夹到任意位置（不要放在中文/带空格的路径下更稳）
2) 打开 PowerShell，进入该文件夹：
     cd <解压目录>\desktop-director-demo
3) 先冒烟（约 40 秒，验证环境）：
     powershell -ExecutionPolicy Bypass -File run-demo.ps1 -Fast
4) 再完整跑一遍（约 90 秒）：
     powershell -ExecutionPolicy Bypass -File run-demo.ps1

脚本会自动：检查依赖 → 没装 ddir 就本地安装 → ddir doctor → mode semi →
跑 demo → 结束时 release + 关闭演示窗口 + mode off。

录制
----
- 最简单：Win + G 打开 Xbox Game Bar → 点录制（Win + Alt + R）
- 或用 ffmpeg（本机没有 OBS 时的方案）：
    npm i ffmpeg-static
    node -e "console.log(require('ffmpeg-static'))"   # 得到 ffmpeg.exe 路径
    ffmpeg -f gdigrab -framerate 30 -i desktop -t 110 -c:v libx264 -pix_fmt yuv420p demo.mp4

排障
----
- "python not found" / "node not found"：装完要**开新终端**（PATH 只对新进程生效）
- create-vite 报 "Operation cancelled"：本包已带 --no-interactive --no-immediate --overwrite，不会发生
- 窗口没动 / 全部 mode_off：演示前 ddir mode semi
- 页面打不开：看 %USERPROFILE%\ddir-webdev-demo\vite.log
- 中文乱码：本包已强制 UTF-8；若仍乱码，chcp 65001 后再运行
- npm 慢/失败：确认公司网络能访问 registry.npmjs.org（需要代理就设 npm config set proxy）

演示完的现场
------------
- ddir status 应为 leases=0、mode=off
- 演示窗口由 rollback 关闭；工作副本留在 %USERPROFILE%\ddir-webdev-demo
- 想留现场：run-demo.ps1 -Keep（之后手动 ddir release）
