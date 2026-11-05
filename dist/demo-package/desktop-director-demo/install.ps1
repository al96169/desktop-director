# install.ps1 - install ddir (Windows) and optionally wire the agent prompt.
# Usage:  powershell -ExecutionPolicy Bypass -File install.ps1 [-WithPrompt] [-Mode semi]
param(
    [switch]$WithPrompt,
    [ValidateSet('off', 'semi', 'auto')] [string]$Mode = 'semi'
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'ddir\bin'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-Item (Join-Path $here 'ddir.exe') $dest -Force
@"
@echo off
"%~dp0ddir.exe" %*
"@ | Set-Content -Path (Join-Path $dest 'ddir.cmd') -Encoding ASCII

# user PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$parts = $userPath -split ';' | Where-Object { $_ }
if ($parts -notcontains $dest) {
    [Environment]::SetEnvironmentVariable('Path', (($parts + $dest) -join ';'), 'User')
    Write-Host "[ddir] added $dest to user PATH (open a new terminal to pick it up)"
}

# state dir + mode
$home_dir = Join-Path $env:USERPROFILE '.ddir'
New-Item -ItemType Directory -Force -Path $home_dir | Out-Null
Set-Content -Path (Join-Path $home_dir 'mode.txt') -Value $Mode -Encoding ASCII -NoNewline
Write-Host "[ddir] mode = $Mode"

# verify
& (Join-Path $dest 'ddir.exe') version
& (Join-Path $dest 'ddir.exe') selftest | Select-Object -Last 3

if ($WithPrompt) {
    $agents = Join-Path $env:USERPROFILE '.dsh\AGENTS.md'
    $prompt = Join-Path $here 'AGENTS.m0.md'
    if ((Test-Path $prompt) -and -not (Test-Path $agents)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $agents) | Out-Null
        Copy-Item $prompt $agents
        Write-Host "[ddir] installed prompt to $agents"
    } elseif (Test-Path $agents) {
        Write-Host "[ddir] $agents already exists - merge AGENTS.m0.md manually"
    }
}

Write-Host ""
Write-Host "done. try:  ddir mode ; ddir list --text ; ddir selftest"
