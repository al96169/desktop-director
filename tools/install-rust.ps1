# install-rust.ps1 - user-space Rust (GNU toolchain) + portable MinGW, no admin required
$ErrorActionPreference = 'Stop'
$root = 'F:\envs\rust'
$log  = 'F:\desktop-director\.install-rust.log'
New-Item -ItemType Directory -Force -Path $root | Out-Null
function Log($m) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; $line; $line | Add-Content -Path $log -Encoding UTF8 }

Log "start"
$ProgressPreference = 'SilentlyContinue'

# 1) rustup-init
$rustupExe = Join-Path $root 'rustup-init.exe'
if (-not (Test-Path $rustupExe)) {
  Log "downloading rustup-init.exe"
  Invoke-WebRequest -Uri 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe' -OutFile $rustupExe -TimeoutSec 300 -UseBasicParsing
}
Log ("rustup-init size: " + (Get-Item $rustupExe).Length)

# 2) MinGW (winlibs portable zip)
$mingwRoot = Join-Path $root 'mingw64'
if (-not (Test-Path (Join-Path $mingwRoot 'bin\gcc.exe'))) {
  Log "querying winlibs latest release"
  $api = 'https://api.github.com/repos/brechtsanders/winlibs_mingw/releases/latest'
  $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'ddir-installer' } -TimeoutSec 120
  $asset = $rel.assets | Where-Object { $_.name -match 'x86_64-posix-seh' -and $_.name -match 'gcc' -and $_.name -like '*.zip' } | Select-Object -First 1
  if (-not $asset) { throw "no suitable winlibs asset in $($rel.tag_name)" }
  Log ("asset: " + $asset.name + " (" + [math]::Round($asset.size/1MB,1) + " MB)")
  $zip = Join-Path $root $asset.name
  if (-not (Test-Path $zip)) {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -TimeoutSec 900 -UseBasicParsing
  }
  Log "extracting"
  $tmp = Join-Path $root '_extract'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  & tar.exe -xf $zip -C $tmp
  $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
  Move-Item $inner.FullName $mingwRoot
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path (Join-Path $mingwRoot 'bin\gcc.exe'))) { throw "mingw gcc not found under $mingwRoot" }
Log "mingw ok"

# 3) rustup init (user space)
$env:RUSTUP_HOME = Join-Path $root 'rustup'
$env:CARGO_HOME  = Join-Path $root 'cargo'
$env:PATH = (Join-Path $mingwRoot 'bin') + ';' + $env:PATH
Log "running rustup-init"
& $rustupExe -y --profile minimal --default-host x86_64-pc-windows-gnu --default-toolchain stable 2>&1 | ForEach-Object { Log ("  " + $_) }
Log "cargo version: " + (& (Join-Path $env:CARGO_HOME 'bin\cargo.exe') --version 2>&1)
Log "rustc version: " + (& (Join-Path $env:CARGO_HOME 'bin\rustc.exe') --version 2>&1)

# 4) hello world build check
$h = Join-Path $root 'hello'
if (Test-Path $h) { Remove-Item $h -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $h 'src') | Out-Null
@'
fn main() { println!("hello from ddir toolchain"); }
'@ | Set-Content -Path (Join-Path $h 'src\main.rs') -Encoding ASCII
@'
[package]
name = "hello"
version = "0.1.0"
edition = "2021"
'@ | Set-Content -Path (Join-Path $h 'Cargo.toml') -Encoding ASCII
Push-Location $h
try {
  $out = & (Join-Path $env:CARGO_HOME 'bin\cargo.exe') build --release 2>&1
  $out | ForEach-Object { Log ("  build: " + $_) }
  Log ("exe: " + (Get-Item (Join-Path $h 'target\release\hello.exe')).Length + " bytes")
} finally { Pop-Location }
Log "done"
