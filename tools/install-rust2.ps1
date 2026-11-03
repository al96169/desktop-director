# install-rust2.ps1 - Rust (GNU host) into F:\envs\rust using curl; no admin
$ErrorActionPreference = 'Stop'
$root = 'F:\envs\rust'
$log  = 'F:\desktop-director\.install-rust.log'
function Log($m) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; $line; $line | Add-Content -Path $log -Encoding UTF8 }
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Log "start (curl)"

$rustupExe = Join-Path $root 'rustup-init.exe'
if (-not (Test-Path $rustupExe) -or (Get-Item $rustupExe).Length -lt 10MB) {
  Log "downloading rustup-init.exe via curl"
  & curl.exe -L --fail -o $rustupExe 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe'
  if ($LASTEXITCODE -ne 0) { throw "curl failed: $LASTEXITCODE" }
}
Log ("rustup-init size: " + [math]::Round((Get-Item $rustupExe).Length/1MB,1) + " MB")

$env:RUSTUP_HOME = Join-Path $root 'rustup'
$env:CARGO_HOME  = Join-Path $root 'cargo'
$env:PATH = 'F:\envs\msys64\mingw64\bin;' + $env:PATH
Log "running rustup-init (GNU host, minimal)"
& $rustupExe -y --profile minimal --default-host x86_64-pc-windows-gnu --default-toolchain stable 2>&1 | ForEach-Object { Log ("  " + $_) }

$cargo = Join-Path $env:CARGO_HOME 'bin\cargo.exe'
$rustc = Join-Path $env:CARGO_HOME 'bin\rustc.exe'
Log ("cargo: " + (& $cargo --version 2>&1))
Log ("rustc: " + (& $rustc --version 2>&1))

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
  & $cargo build --release 2>&1 | ForEach-Object { Log ("  build: " + $_) }
  $exePath = Join-Path $h 'target\release\hello.exe'
  if (Test-Path $exePath) { Log ("OK exe " + (Get-Item $exePath).Length + " bytes") } else { Log "BUILD FAILED" }
} finally { Pop-Location }
Log "done"
