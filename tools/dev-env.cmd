@echo off
rem ddir dev env - MinGW-w64 + Rust (MSYS2, installed at F:\envs\msys64)
rem Usage:  call tools\dev-env.cmd     (in cmd)   |   .\tools\dev-env.cmd  (in powershell: cmd /c)
set "DDIR_MSYS=F:\envs\msys64"
set "PATH=%DDIR_MSYS%\mingw64\bin;%PATH%"
set "CARGO_HOME=F:\envs\cargo"
set "RUSTUP_HOME=F:\envs\rustup"
set "MSYSTEM=MINGW64"
echo [ddir] toolchain root: %DDIR_MSYS%
gcc --version 2>nul | findstr /B "gcc"
cargo --version 2>nul
rustc --version 2>nul
