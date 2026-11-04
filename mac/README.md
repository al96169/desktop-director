# mac/ — ddir 的 macOS 后端

Swift 6 单文件 CLI（`swiftc` 直接编译，无 SPM / 无第三方依赖），跑在
`~/Applications/Ddir.app` 里以获得并保持辅助功能（TCC）授权。

```bash
./build.sh                # 编译 + 组装 Ddir.app + ddir-dev 签名 + 安装 ~/.local/bin/ddir
./build.sh --no-install   # 只编译到 build/ddir-mac
./test.sh                 # 42 项验收（只动 TextEdit 和它自己开的窗口）
```

| 文件 | 作用 |
|---|---|
| `Sources/Util.swift` | JSON 转义、参数解析、输出 |
| `Sources/Store.swift` | `~/.ddir/` 状态：mode/leases/apps/audit/config/log（与 Windows 同一份 TSV） |
| `Sources/MacWin.swift` | AX/CG 后端：显示器、窗口、移动、隐藏、关闭、空闲、agent 身份 |
| `Sources/Present.swift` | `presentation=instant|paced` 队列（`ddir flush` / 托盘 tick 消费） |
| `Sources/Tray.swift` | 菜单栏托盘（三档/全部还原/auto_close/窗口/托管屏/日志/自启/退出；`--check` 输出菜单 JSON） |
| `Sources/Hud.swift` | HUD：默认右下角轻量小卡；`--wall` 为全屏暗化 + 缩略图墙（ScreenCaptureKit，14+）|
| `Sources/Show.swift` | `ddir stage` 演出编排（节拍、清场、journal、回滚） |
| `Sources/ShowAssets.swift` | 演出素材：HTML 仪表盘/IDE、代码，以及离线兜底的合成片段/环境音 |
| `Sources/ShowMedia.swift` | 真实素材：NASA/STScI 公有领域影像 + CC0 音乐 → 竖屏 Ken Burns 片段（`stage fetch`）|
| `Sources/Player.swift` | `ddir play`：自带 AVPlayer 窗口（无 AppleScript、可被 claim 平铺） |
| `Sources/Web.swift` | `ddir web`：无浏览器 chrome 的 WKWebView 窗口 |
| `Sources/Doctor.swift` | `ddir doctor` 体检 + `ddir prompt`（bundle 内 AGENTS.m0.md 的打印/安装）|
| `Sources/Autostart.swift` | `~/Library/LaunchAgents/com.ddir.mac.tray.plist` 的写/删 + `launchctl bootstrap/bootout` |
| `Sources/Commands.swift` | 命令实现（JSON 与 `src/main.rs` 对齐） |
| `Sources/main.swift` | 命令分发 |
| `Info.plist` | bundle id `com.ddir.mac`（**不能改**，TCC 授权挂在它和签名上） |

设计、平台事实、与 Windows 的差异：见 [`../docs/macos-backend.md`](../docs/macos-backend.md)。
