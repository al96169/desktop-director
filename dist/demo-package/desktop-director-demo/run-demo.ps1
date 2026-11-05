# ddir web-dev demo — one-command runner (Windows)
# Usage:
#   powershell -ExecutionPolicy Bypass -File run-demo.ps1            # full run, ~90 s
#   powershell -ExecutionPolicy Bypass -File run-demo.ps1 -Fast      # smoke test, ~40 s
#   powershell -ExecutionPolicy Bypass -File run-demo.ps1 -Keep      # leave the stage up
param(
    [switch]$Fast,
    [switch]$Keep
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Ok($m)   { Write-Host "  OK    $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  FAIL  $m" -ForegroundColor Red; exit 1 }

Write-Host "== ddir web-dev demo bootstrap" -ForegroundColor Cyan
Write-Host "== folder: $here"

# 1. prerequisites -----------------------------------------------------------
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { Die "python not found. Install Python 3.9+ (winget install Python.Python.3.12) and reopen the terminal." }
Ok "python  $python"

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { Die "node not found. Install Node.js 20+ (winget install OpenJS.NodeJS.LTS) and reopen the terminal." }
Ok "node    $node"

$npm = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
if (-not $npm) { $npm = (Get-Command npm -ErrorAction SilentlyContinue).Source }
if (-not $npm) { Die "npm not found (should ship with Node.js)." }
Ok "npm     $npm"

$edge = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { Die "Microsoft Edge not found. Install Edge (winget install Microsoft.Edge)." }
Ok "edge    $edge"

$code = (Get-Command code -ErrorAction SilentlyContinue).Source
if (-not $code) { Warn "VS Code not found; the code column will be missing (winget install Microsoft.VisualStudioCode)." }
else { Ok "code    $code" }

# 2. ddir --------------------------------------------------------------------
$ddir = (Get-Command ddir -ErrorAction SilentlyContinue).Source
if (-not $ddir) {
    # use the bundled binary directly: no copy, no PATH change, no file locks
    $ddir = Join-Path $here 'ddir.exe'
    Warn "ddir not on PATH; using the bundled ddir.exe for this run"
}
Ok "ddir    $ddir"
& $ddir version
& $ddir doctor
& $ddir mode semi | Out-Null

# 3. demo --------------------------------------------------------------------
$argsList = @()
if ($Fast) { $argsList += '--fast' }
if ($Keep) { $argsList += '--keep' }
Write-Host "== running: python demo\run.py $($argsList -join ' ')" -ForegroundColor Cyan
$env:DDIR_BIN = $ddir
Push-Location $here
try {
    & $python 'demo\run.py' @argsList
} finally {
    Pop-Location
}

Write-Host "== done. log: %USERPROFILE%\ddir-webdev-demo\webdev-demo.log" -ForegroundColor Cyan
& $ddir status
