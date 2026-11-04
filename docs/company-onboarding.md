# 公司电脑 10 分钟上手（Windows）

## 1. 装（不需要管理员）

```powershell
# 解压 desktop-director-0.7.0-win64.zip 到任意目录，然后：
powershell -ExecutionPolicy Bypass -File install.ps1
# 会做：复制 ddir.exe 到 %LOCALAPPDATA%\ddir\bin、加用户 PATH、建 ~/.ddir、设 semi、跑自检
```

如果 Windows 弹 "已保护你的电脑"（SmartScreen，因为没签名）：点「更多信息」→「仍要运行」。

## 2. 开一个新终端，验收

```powershell
ddir version      # 0.7.0
ddir selftest     # 7/7 PASS
ddir mode         # semi
ddir list --text  # 应该和 Alt+Tab 看到的窗口差不多
```

## 3. 给 Agent 装规矩（可选但推荐）

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -WithPrompt
```

或者手动把 `AGENTS.m0.md` 的内容贴进你所用 Harness 的全局指令（DSH / Trae / Claude Code / Codex 都可以）。装完让 Agent 复述一句"多条窗口要并排"来确认它读到了。

## 4. 日常用法

```powershell
ddir mode semi              # 默认；只摆自己窗口、不抢焦点
ddir tray                   # 托盘常驻（右键：模式/还原/日志/自启）
ddir autostart on           # 开机自启
ddir log --lines 50         # 出问题先看日志
```

- 长任务：让 Agent 每 2 分钟 `ddir heartbeat`（租约 5 分钟）
- 想演示：`ddir config presentation paced` + `ddir config step_ms 700` + `ddir demo`
- 不想它动窗口：`ddir mode off`

## 5. 安全默认值（确认一下）

| 配置 | 默认 | 含义 |
|---|---|---|
| `auto_close` | `off` | 全自动也不关任何软件 |
| `presentation` | `instant` | Agent 操作是瞬时的 |
| `mode` | `semi` | 不抢焦点、不碰用户屏 |
| `downgrade_on_unmanaged_kill` | `false` | 越权关窗口只记录，不自动降档 |

## 6. 出问题怎么办

| 现象 | 处理 |
|---|---|
| `ddir` 找不到 | 开新终端（PATH 只对新进程生效） |
| claim 返回 `user_active` | 你在动键鼠；等 5 秒或加 `--force` |
| claim 返回 `window_owned_by` | 别的 Agent 在用；换窗口，别重试 |
| 窗口没还原 | `ddir release --all`；托盘「全部还原」 |
| 行为异常 | 先 `ddir doctor`（9 项体检），再 `ddir log --lines 80` |

## 7. 回滚

- 停托盘：托盘右键「退出」
- 取消自启：`ddir autostart off`
- 卸载：删 `%LOCALAPPDATA%\ddir`、从用户 PATH 去掉该目录、删 `~\.ddir`