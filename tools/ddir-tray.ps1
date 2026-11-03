# ddir tray (preview) - WinForms NotifyIcon that drives ddir.exe.
# This is the M3 preview; the shipped tray will be a native Rust binary.
param(
    [string]$Exe = "F:\desktop-director\target\release\ddir.exe",
    [string]$LogFile = "$env:USERPROFILE\.ddir\tray.log"
)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
function Log($m) { "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m | Add-Content -Path $LogFile -Encoding UTF8 }
Log "tray starting (pid $PID), exe=$Exe"

function D([string[]]$argv) {
    try { return (& $Exe @argv 2>$null) -join "`n" } catch { Log ("ddir failed: " + $_.Exception.Message); return "" }
}
function Status {
    $j = D @('status')
    try { return $j | ConvertFrom-Json } catch { return $null }
}

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.SystemIcons]::Application
$ni.Visible = $true
$ni.Text = "ddir - starting"

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miStatus = New-Object System.Windows.Forms.ToolStripMenuItem
$miStatus.Enabled = $false

$miMode = New-Object System.Windows.Forms.ToolStripMenuItem "模式"
$miOff = New-Object System.Windows.Forms.ToolStripMenuItem "off"
$miSemi = New-Object System.Windows.Forms.ToolStripMenuItem "semi"
$miAuto = New-Object System.Windows.Forms.ToolStripMenuItem "auto"
$miMode.DropDownItems.AddRange(@($miOff, $miSemi, $miAuto))

$miRelease = New-Object System.Windows.Forms.ToolStripMenuItem "全部还原"
$miList = New-Object System.Windows.Forms.ToolStripMenuItem "窗口列表（前 8 个）"
$miOpen = New-Object System.Windows.Forms.ToolStripMenuItem "打开项目目录"
$miExit = New-Object System.Windows.Forms.ToolStripMenuItem "退出"
$sep1 = New-Object System.Windows.Forms.ToolStripSeparator
$sep2 = New-Object System.Windows.Forms.ToolStripSeparator

$menu.Items.AddRange(@($miStatus, $sep1, $miMode, $miRelease, $miList, $miOpen, $sep2, $miExit))
$ni.ContextMenuStrip = $menu

$script:lastMode = ""
function Refresh {
    $s = Status
    if (-not $s) { $ni.Text = "ddir - unavailable"; return }
    $script:lastMode = $s.mode
    $ni.Text = "ddir - $($s.mode) - $($s.leases) lease(s)"
    $miStatus.Text = "状态：$($s.mode)   leases=$($s.leases)   you=$($s.you)"
    $miOff.Checked = ($s.mode -eq "off")
    $miSemi.Checked = ($s.mode -eq "semi")
    $miAuto.Checked = ($s.mode -eq "auto")
}

$setMode = {
    param($m)
    D @('mode', $m) | Out-Null
    Log "set mode $m"
    Refresh
    $ni.ShowBalloonTip(1500, "ddir", "模式已切换：$m", [System.Windows.Forms.ToolTipIcon]::Info)
}
$miOff.add_Click({ & $setMode "off" })
$miSemi.add_Click({ & $setMode "semi" })
$miAuto.add_Click({ & $setMode "auto" })

$miRelease.add_Click({
    $r = D @('release')
    Log "release: $r"
    Refresh
    $ni.ShowBalloonTip(2000, "ddir", "已还原：$r", [System.Windows.Forms.ToolTipIcon]::Info)
})

$miList.add_Click({
    $rows = (D @('list')) | ConvertFrom-Json
    $txt = ($rows.windows | Select-Object -First 8 | ForEach-Object { "{0}  {1,-28} {2}" -f $_.hwnd, $_.app, ($_.win -join ',') }) -join "`r`n"
    [System.Windows.Forms.MessageBox]::Show($txt, "ddir - 窗口（前 8 个）") | Out-Null
})

$miOpen.add_Click({ Start-Process explorer.exe "F:\desktop-director" | Out-Null })

$miExit.add_Click({
    Log "exit requested"
    $ni.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$ni.add_MouseDoubleClick({
    Refresh
    $ni.ShowBalloonTip(2000, "ddir", $miStatus.Text, [System.Windows.Forms.ToolTipIcon]::Info)
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.add_Tick({ Refresh })
$timer.Start()

Refresh
Log "tray ready: $($ni.Text)"
$ni.ShowBalloonTip(5000, "ddir（桌面导播台）", "托盘已就绪：右键切换 off/semi/auto、全部还原、看窗口列表。当前 $($ni.Text)", [System.Windows.Forms.ToolTipIcon]::Info)
[System.Windows.Forms.Application]::Run()
Log "tray exited"
