# 开发工具链（2026-11-03 装好，无需管理员权限）

## 现状

| 组件 | 版本 | 位置 |
|---|---|---|
| gcc (MinGW-w64) | 16.2.0 (Rev6, MSYS2) | `F:\envs\msys64\mingw64\bin\gcc.exe` |
| cargo | 1.99.1 (MSYS2 build) | `F:\envs\msys64\mingw64\bin\cargo.exe` |
| rustc | 1.99.1 | 同上 |
| bash / pacman | MSYS2 | `F:\envs\msys64\usr\bin\bash.exe` |

验证过：`cargo build --release` 能产出 1.2MB 的 Windows GNU exe 并运行。

## 用法

```cmd
:: cmd
call F:\desktop-director\tools\dev-env.cmd
cargo build
```

```powershell
# PowerShell
cmd /c "F:\desktop-director\tools\dev-env.cmd"
```

`tools\dev-env.cmd` 只做三件事：把 `mingw64\bin` 加进 PATH、把 `CARGO_HOME`/`RUSTUP_HOME` 指到 `F:\envs`、打印版本。

## 为什么不走官方 rustup

- `static.rust-lang.org` 在本机被限速到 **30 KB/s**（实测：前 3MB 有 2.6 MB/s，之后骤降），rustup-init 14.8MB 下不完
- GitHub release 直连 **0 KB/s**（winlibs 的 MinGW zip 完全拉不下来）
- 清华 TUNA / 中科大镜像 **4–5 MB/s**，MSYS2 + pacman 是最稳的路径

## 重装/修复

```powershell
# MSYS2 与 gcc
powershell -File F:\desktop-director\tools\install-mingw.ps1
# 或手动
F:\envs\msys64\usr\bin\bash.exe -lc "pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-rust"
```

镜像配置在 `F:\envs\msys64\etc\pacman.d\mirrorlist.mingw`（TUNA 优先）。

## 已知限制

- 这是 **GNU 工具链**（不是 MSVC）。链 Windows 系统库没问题；要求 MSVC ABI 的第三方 crate（很少）可能需要换 MSVC 工具链 + VS Build Tools
- MSYS2 的 Rust 版本由 pacman 决定，可能略滞后于官方 stable
- 交叉编译 macOS/Linux 不在本机做，各平台在本机原生构建（见 `docs/platforms.md`）
