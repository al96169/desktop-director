# 推广方案 · Desktop Director（ddir）

> 2026-11-06 · 基于当前 0.8.1（Windows）/ 0.11.3（macOS，实验）状态
> 目标：3 个月内拿到 **第一批 300 个真实安装** 和 **10 个愿意在公开场合提到的用户**，而不是单纯刷 star。

## 1. 定位

**一句话**：让多个 AI Agent 在同一台电脑上 **并排干活、互不抢窗口**。

三个候选说法（按场景选）：

| 说法 | 适合 | 风险 |
|---|---|---|
| **"Agent 的窗口管理员"** | 大众、演示视频标题 | 听起来像玩具 |
| **"多 Agent 的桌面导播台"** | 技术社区、深度文章 | 需要解释"导播" |
| **"给 Agent 的窗口租约（lease）"** | 工程受众、HN | 太抽象，先讲痛点再讲它 |

推荐：**对外统一用"Agent 的窗口管理员"，技术文章里再引出 lease 模型。**

## 2. 目标人群（按优先级）

1. **同时开 2–4 个编码 Agent 的人**（Claude Code / Codex / Trae / DSH / Cursor 用户）
   痛点：窗口叠在一起、看不见谁在干什么、Agent 之间抢同一个窗口
2. **要给别人演示 Agent 工作过程的人**（布道师、团队 lead、录课程的人）
   痛点：演示时窗口乱、节奏太快看不清
3. **公司内部工具团队**（要给同事统一装一套"Agent 桌面规范"）
   痛点：每个人窗口乱摆、Agent 互相踩

## 3. 竞争格局与差异

| 项目 | 做法 | 与 ddir 的关系 |
|---|---|---|
| [Claudes](https://github.com/paulallington/Claudes) | 一个 App 里多列 Claude Code 终端 | 解决"看多个会话"，不解决**跨 App 的真实窗口** |
| [swarm](https://github.com/valewnrt/swarm) | 终端优先的 agent 开发环境 | 同上，工作区被限制在终端内 |
| [paneflow](https://github.com/arthurdev44/paneflow) | 终端分栏跑 Claude/Codex | 同上 |
| [windows-use](https://pypi.org/project/windows-use/) | 让 Agent 控制 Windows GUI | 是"Agent 操作电脑"，不是"多 Agent 协调" |
| **ddir** | **OS 级窗口 + 软件租约 + 任意 Harness** | 差异点：真实窗口、跨 App、多 Agent 仲裁 |

**我们的独特性只有一句**：别人把 Agent 关进一个 App 里，我们让 Agent 用**你本来就有的窗口**，并且规定**谁能动谁**。

## 4. 现有可用的推广资产

- 79 秒演示视频：`demo/webdev/webdev-demo-windows.mp4`（终端 → HMR → 三列页面 → 4 媒体窗口）
- 一条命令的演示包：`desktop-director-demo-0.8.0-win64.zip` + `run-demo.ps1`
- 跨平台提示词 v2.0（贴进任意 Harness 就生效）
- 文档：协议、决策记录（D1–D30）、公司上手清单、mac 任务书
- 安全叙事：默认 `mode=off`、`auto_close=off`、租约可撤销、`unmanaged_kill` 审计

## 5. 分发（比内容更关键）

| 渠道 | 动作 | 为什么 |
|---|---|---|
| **Gitee 镜像** | 同步仓库 + releases zip | 国内 GitHub 经常不可达，这是最大流失点 |
| **Scoop bucket** | `scoop install ddir` | Windows 开发者标准安装方式 |
| **winget** | 提交 manifest | 公司机器免管理员安装 |
| **Homebrew tap** | `brew install al96169/ddir/ddir` | macOS 用户 |
| **npm 包装** | `npx ddir` 下载对应平台二进制 | 前端/Agent 用户最顺手 |
| **GitHub Topics** | `ai-agents` `window-manager` `multi-agent` `desktop-automation` | 自然流量 |
| **awesome 列表** | awesome-ai-agents / awesome-claude-code PR | 长期曝光 |

短期（本周）最划算：**Gitee 镜像 + Scoop bucket + 英文 README 摘要**。

## 6. 内容计划（30 天）

### 第 1 周：把"看懂"成本降到 1 分钟

- 英文 README 顶部加 3 行 + GIF（当前全中文，海外用户直接走）
- 录 20 秒竖屏 GIF：两个 Agent 抢同一个窗口 → 一个被拒 → 并排
- 写一篇 **问题文**：《为什么多个 AI Agent 会互相抢窗口》
  - 平台：掘金 + V2EX + 即刻 + 知乎
  - 结构：真实翻车 → 为什么 terminal 方案不够 → lease 模型 → 30 秒 demo
- 发布演示包，配一句"下载解压，一条命令看效果"

### 第 2 周：技术深度

- 文章《给窗口发租约：多 Agent 桌面协调的三个不变量》（I1/I2/I3、抢占条件、TTL、审计）
  - 平台：HN（Show HN）、Reddit r/ClaudeAI、r/LocalLLaMA
- 把 `docs/decisions.md` 里 5 条最有争议的决策单独发一条 thread（为什么默认不关窗口、为什么不做虚拟桌面）
- 在 3 个 issue 里认真回答"能不能支持 Linux"

### 第 3 周：场景化

- 视频 2：《三个 Agent 同时改一个前端项目》（真实三列 + 谁在动）
- 视频 3：《给同事演示 Agent 干活，不乱、不丢字》（演示节拍 + `ddir demo`）
- 找 3–5 个中文 AI 编码 UP 主/博主，给演示包 + 一段现成脚本，请他们"随手拍"

### 第 4 周：企业向

- 一页 PDF/网页：《团队统一 Agent 桌面规范》—— 安装、模式、权限、审计、回滚
- 定向发到 3 个开发者群（不群发，逐个问"要不要试"）
- 收集前 10 个真实用户，做 15 分钟访谈，换"致谢名单"

## 7. 发布日 SOP

1. 提前 3 天：仓库加 LICENSE、CONTRIBUTING、issue 模板、roadmap、英文摘要
2. 当天上午：Gitee 镜像同步 + 发布 zip + 置顶 demo 视频
3. 顺序：即刻（中文、图）→ V2EX（技术、链接）→ 掘金（文章）→ HN（英文、Show HN）
4. 每条都带**同一句定位**和**同一个 20 秒 GIF**
5. 当天盯 issue，2 小时内回复；把常见问题补进 README

## 8. 指标

| 指标 | 怎么看 | 30 天目标 |
|---|---|---|
| 安装量 | release zip 下载数（GitHub API + Gitee 计数） | 300 |
| 真实使用 | 用户主动贴 `ddir log` 的 issue/私信 | 10 |
| 演示视频完播 | B 站后台 / X 分析 | 40% |
| Star | GitHub | 200（不作为主指标） |
| 公司试用 | 私信/邮件 | 3 家 |

## 9. 风险与红线

- **GitHub 不可达**：所有中文渠道一律给 Gitee 链接，GitHub 只作备份
- **SmartScreen / Gatekeeper 警告**：文案提前写"未签名，点更多信息→仍要运行"，别让用户以为中毒
- **"Agent 控制我的电脑"恐惧**：所有物料第一屏先写"默认不关窗口、可一键还原、全程审计"
- **不要吹 Linux**：现在没有，别在标题里暗示跨平台全支持
- **不要刷 star**：会毁掉 HN/Reddit 的唯一一次机会

## 10. 推广前值得先补的产品改动（按性价比）

1. **英文 README + 20 秒 GIF**（半天，决定海外转化）
2. **Gitee 镜像 + release zip**（半天，决定国内能不能下）
3. **Scoop bucket / winget manifest**（1 天，决定"顺手装"）
4. **exe 嵌入图标 + 签名**（半天到 1 天，决定第一印象）
5. **`ddir doctor` 里加"提示词是否装好"检查**（半天，减少"装了没效果"的差评）
