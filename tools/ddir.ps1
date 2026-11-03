#requires -Version 5.1
<#
  ddir — Desktop Director 参考实现（M1 行为参考 / M0 测试台）

  为什么是 PowerShell：本机没有 Rust / gcc / .NET SDK 工具链（2026-11-03 侦察），
  而 M0 要真实会话测试就必须先有一个可调用的 ddir。本文件实现协议里"只读 + 摆窗口"
  那一小部分，行为与 docs/protocol.md 对齐；Rust 正式版就绪后整体替换。

  能力：
    mode / displays / list / status / plan --dry-run / claim / move / release
    own / disown / close(拒绝) / board
  安全：
    只写 SetWindowPos（NOACTIVATE），不关闭、不杀进程、不切桌面；
    每次 claim 前快照，release 还原。
#>

[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string] $Command = "help",
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Rest
)

$ErrorActionPreference = "Stop"
$Home_ = if ($env:DDIR_HOME) { $env:DDIR_HOME } else { Join-Path $env:USERPROFILE ".ddir" }
$ModeFile = Join-Path $Home_ "mode.txt"
$StateFile = Join-Path $Home_ "state.json"
$AppsFile = Join-Path $Home_ "apps.json"
$AuditFile = Join-Path $Home_ "audit.jsonl"
New-Item -ItemType Directory -Force -Path $Home_ | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class DDIR {
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  public delegate bool MonitorEnumProc(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr data);

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc cb, IntPtr data);
  [DllImport("user32.dll")] public static extern bool GetMonitorInfoW(IntPtr hMon, ref MONITORINFO mi);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtrW(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("kernel32.dll")] public static extern uint GetTickCount();
  public struct POINT { public int X, Y; }
  public const uint WM_CLOSE = 0x0010;
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO li);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int sz);
  [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] public static extern int DwmGetRect(IntPtr h, int attr, out RECT r, int sz);

  public struct RECT { public int Left, Top, Right, Bottom; }
  public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
  public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

  public const int GWL_EXSTYLE = -20;
  public const int WS_EX_TOOLWINDOW = 0x00000080;
  public const uint GA_ROOTOWNER = 3;
  public const int DWMWA_CLOAKED = 14;
  public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
  public const uint SWP_NOZORDER = 0x0004;
  public const uint SWP_NOACTIVATE = 0x0010;
  public const uint SWP_SHOWWINDOW = 0x0040;
  public const int SW_RESTORE = 9;

  public static List<IntPtr> TopLevel() {
    var list = new List<IntPtr>();
    EnumWindows((h, l) => { list.Add(h); return true; }, IntPtr.Zero);
    return list;
  }
  public static List<IntPtr> Monitors() {
    var list = new List<IntPtr>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m, dc, r, d) => { list.Add(m); return true; }, IntPtr.Zero);
    return list;
  }
  public static RECT WinRect(IntPtr h) {
    RECT r;
    GetWindowRect(h, out r);
    return r;
  }
  public static RECT Frame(IntPtr h) {
    RECT r;
    if (DwmGetRect(h, DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(RECT))) != 0) {
      GetWindowRect(h, out r);
    }
    return r;
  }
  public static bool Cloaked(IntPtr h) {
    int v;
    if (DwmGetWindowAttribute(h, DWMWA_CLOAKED, out v, sizeof(int)) != 0) return false;
    return v != 0;
  }
  public static bool ToolWindow(IntPtr h) {
    long ex = GetWindowLongPtrW(h, GWL_EXSTYLE).ToInt64();
    return (ex & WS_EX_TOOLWINDOW) != 0;
  }
  public static int IdleSeconds() {
    var li = new LASTINPUTINFO();
    li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
    if (!GetLastInputInfo(ref li)) return -1;
    return (int)((GetTickCount() - li.dwTime) / 1000);
  }
  public static int[] Cursor() {
    POINT p;
    if (!GetCursorPos(out p)) return new int[] { -1, -1 };
    return new int[] { p.X, p.Y };
  }
  public static bool CloseGraceful(IntPtr h) {
    return PostMessageW(h, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
  }
}
"@ -ErrorAction Stop

# ---------- helpers ----------
function Write-Json($obj) {
  $obj | ConvertTo-Json -Depth 8 -Compress
}
function Write-Audit([string]$op, $payload) {
  $rec = [pscustomobject]@{ ts = (Get-Date).ToString("o"); op = $op; agent = $script:Agent; data = $payload }
  ($rec | ConvertTo-Json -Depth 6 -Compress) | Add-Content -Path $AuditFile -Encoding UTF8
}
function Get-Mode {
  if (Test-Path $ModeFile) { (Get-Content $ModeFile -Raw).Trim() } else { "off" }
}
function Set-Mode([string]$m) {
  if ($m -notin @("off", "semi", "auto")) { throw "mode must be off|semi|auto" }
  Set-Content -Path $ModeFile -Value $m -Encoding ASCII -NoNewline
}
function Get-State {
  if (Test-Path $StateFile) { Get-Content $StateFile -Raw | ConvertFrom-Json } else { $null }
}
function Save-State($s) { $s | ConvertTo-Json -Depth 8 | Set-Content -Path $StateFile -Encoding UTF8 }
function Get-Apps {
  if (Test-Path $AppsFile) { Get-Content $AppsFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
}
function Save-Apps($a) { $a | ConvertTo-Json -Depth 6 | Set-Content -Path $AppsFile -Encoding UTF8 }
$ActivityFile = Join-Path $Home_ "activity.json"
function Get-Activity {
  $age = [DDIR]::IdleSeconds()
  $cur = [DDIR]::Cursor()
  $fg = $null
  foreach ($w in Get-Windows) { if ($w.foreground) { $fg = $w; break } }
  $prev = $null
  if (Test-Path $ActivityFile) { try { $prev = Get-Content $ActivityFile -Raw | ConvertFrom-Json } catch { } }
  $moved = 0
  if ($prev -and $prev.cursor) { $moved = [Math]::Abs([int]$cur[0] - [int]$prev.cursor[0]) + [Math]::Abs([int]$cur[1] - [int]$prev.cursor[1]) }
  $fgChanged = [bool]($prev -and $prev.fg -and $fg -and ($prev.fg -ne $fg.hwnd))
  # 本机有鼠标抖动/注入（Bloody6 之类），原始 input_age 长期为 0，不能单独作为活跃信号
  $active = ($moved -gt 25) -or $fgChanged
  $rec = [pscustomobject]@{ ts = (Get-Date).ToString("o"); cursor = $cur; fg = $(if ($fg) { $fg.hwnd } else { $null }) }
  ($rec | ConvertTo-Json -Compress) | Set-Content -Path $ActivityFile -Encoding UTF8
  [pscustomobject]@{
    input_age_s = $age
    cursor_moved_px = $moved
    foreground_changed = $fgChanged
    user_active = $active
    signal = "cursor+foreground (raw input_age unreliable on this box)"
  }
}

function Get-AgentId {
  if ($env:DDIR_AGENT) { return $env:DDIR_AGENT }
  # 身份必须跨多次调用稳定：往上找"宿主进程"（Trae/终端/执行器），而不是每次都用本次 powershell 的 PID
  $curPid = $PID
  $curName = "powershell"
  for ($k = 0; $k -lt 10; $k++) {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$curPid" -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)" -ErrorAction SilentlyContinue
    if (-not $parent) { break }
    if ($parent.Name -match '^(explorer|services|svchost|wininit|winlogon|RuntimeBroker)\.exe$') { break }
    $curPid = $parent.ProcessId
    $curName = $parent.Name
  }
  $base = [System.IO.Path]::GetFileNameWithoutExtension($curName)
  return ("{0}-{1}" -f $base, $curPid)
}
$script:Agent = Get-AgentId
$ExcludeClasses = @("Progman", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow",
  "ApplicationFrameInputSinkWindow", "MSCTFIME UI", "IME", "SoPY_Hint", "Sogou_TSF_UI", "Default IME",
  "NVIDIA GeForce Overlay DT", "CEF-OSC-WIDGET", "ForegroundStaging", "MultitaskingViewFrame")

function Get-Displays {
  $out = @()
  $i = 0
  foreach ($m in [DDIR]::Monitors()) {
    $mi = New-Object DDIR+MONITORINFO
    $mi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mi)
    if (-not [DDIR]::GetMonitorInfoW($m, [ref]$mi)) { continue }
    $rc = $mi.rcMonitor
    $wk = $mi.rcWork
    $rcL = [int]$rc.Left; $rcT = [int]$rc.Top; $rcR = [int]$rc.Right; $rcB = [int]$rc.Bottom
    $wkL = [int]$wk.Left; $wkT = [int]$wk.Top; $wkR = [int]$wk.Right; $wkB = [int]$wk.Bottom
    $rcW = $rcR - $rcL
    $rcH = $rcB - $rcT
    $wkW = $wkR - $wkL
    $wkH = $wkB - $wkT
    $out += [pscustomobject]@{
      uid     = "mon$i"
      gdi     = ('DISPLAY{0}' -f ($i + 1))
      label   = ('{0}x{1} @ {2},{3}' -f $rcW, $rcH, $rcL, $rcT)
      primary = (([int]$mi.dwFlags -band 1) -ne 0)
      monitor = @($rcL, $rcT, $rcW, $rcH)
      work    = @($wkL, $wkT, $wkW, $wkH)
    }
    $i++
  }
  if ($out.Count -gt 0) {
    if (-not ($out | Where-Object { $_.primary })) { $out[0].primary = $true }
  }
  # policy: >=2 displays -> manage all but primary; single display -> manage it (otherwise semi has nothing to do)
  $single = ($out.Count -le 1)
  foreach ($d in $out) {
    $d | Add-Member -NotePropertyName managed -NotePropertyValue ($single -or (-not $d.primary)) -Force
  }
  $out
}
function Get-Windows {
  $displays = Get-Displays
  $rows = @()
  foreach ($h in [DDIR]::TopLevel()) {
    if (-not [DDIR]::IsWindowVisible($h)) { continue }
    if ([DDIR]::ToolWindow($h)) { continue }
    if ([DDIR]::GetAncestor($h, [DDIR]::GA_ROOTOWNER) -ne $h) { continue }
    if ([DDIR]::Cloaked($h)) { continue }
    $sb = New-Object System.Text.StringBuilder 512
    [void][DDIR]::GetWindowTextW($h, $sb, 512)
    $title = $sb.ToString()
    if ([string]::IsNullOrWhiteSpace($title)) { continue }
    $cn = New-Object System.Text.StringBuilder 256
    [void][DDIR]::GetClassNameW($h, $cn, 256)
    $cls = $cn.ToString()
    if ($ExcludeClasses -contains $cls) { continue }
    $procId = [uint32]0
    [void][DDIR]::GetWindowThreadProcessId($h, [ref]$procId)
    $procName = "?"
    try { $procName = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }
    $r = [DDIR]::Frame($h)
    $wr = [DDIR]::WinRect($h)
    $wrL = [int]$wr.Left; $wrT = [int]$wr.Top; $wrR = [int]$wr.Right; $wrB = [int]$wr.Bottom
    $wrW = $wrR - $wrL; $wrH = $wrB - $wrT
    $cx = [int](($r.Left + $r.Right) / 2)
    $cy = [int](($r.Top + $r.Bottom) / 2)
    $disp = $null
    foreach ($d in $displays) {
      $mx = $d.monitor[0]; $my = $d.monitor[1]; $mw = $d.monitor[2]; $mh = $d.monitor[3]
      if ($cx -ge $mx -and $cx -lt ($mx + $mw) -and $cy -ge $my -and $cy -lt ($my + $mh)) { $disp = $d.uid; break }
    }
    if (-not $disp -and $displays.Count -gt 0) { $disp = $displays[0].uid }
    $rows += [pscustomobject]@{
      hwnd      = ("0x{0:X8}" -f $h.ToInt64())
      app       = $procName
      class     = $cls
      title     = $title
      display   = $disp
      rect      = @([int]$r.Left, [int]$r.Top, ([int]$r.Right - [int]$r.Left), ([int]$r.Bottom - [int]$r.Top))
      win       = @($wrL, $wrT, $wrW, $wrH)
      dpi       = [DDIR]::GetDpiForWindow($h)
      max       = [DDIR]::IsZoomed($h)
      minimized = [DDIR]::IsIconic($h)
      foreground = ([DDIR]::GetForegroundWindow() -eq $h)
    }
  }
  $rows
}

function Get-ManagedDisplays {
  @(Get-Displays | Where-Object { $_.managed })
}

function Invoke-Claim([string]$needsSpec, [switch]$DryRun) {
  $mode = Get-Mode
  if ($mode -eq "off") { return [pscustomobject]@{ ok = $false; error = "mode_off"; hint = "用户没开启 ddir" } }
  $managed = Get-ManagedDisplays
  if ($managed.Count -eq 0) { return [pscustomobject]@{ ok = $false; error = "display_not_managed"; hint = "没有托管屏" } }

  $needList = @()
  if ($needsSpec) {
    foreach ($part in ($needsSpec -split ",")) {
      $p = $part.Trim()
      if (-not $p) { continue }
      $name = $p; $w = 800; $h = 600
      if ($p -match '^(.*?):(\d+)x(\d+)$') { $name = $matches[1]; $w = [int]$matches[2]; $h = [int]$matches[3] }
      $needList += [pscustomobject]@{ match = $name; min_w = $w; min_h = $h }
    }
  }
  if ($needList.Count -eq 0) { $needList = @([pscustomobject]@{ match = ""; min_w = 800; min_h = 600 }) }
  if ($needList.Count -gt 3) { $needList = $needList[0..2] }

  $wins = Get-Windows | Where-Object { $managed.uid -contains $_.display }
  $state0 = Get-State
  $now = Get-Date
  $busy = @{}
  if ($state0) {
    foreach ($it in @($state0.items)) {
      if (-not $it.window) { continue }
      $exp = $null
      try { if ($it.expires) { $exp = [datetime]$it.expires } } catch { }
      $alive = ($null -eq $exp) -or ($exp -gt $now)
      if ($alive -and $it.agent -and $it.agent -ne $script:Agent) { $busy[$it.window] = $it }
    }
  }
  $blockedHit = $null
  $used = @()
  $assign = @()
  $gap = 16
  $d = $managed[0]
  $wx = $d.work[0]; $wy = $d.work[1]; $ww = $d.work[2]; $wh = $d.work[3]

  for ($i = 0; $i -lt $needList.Count; $i++) {
    $need = $needList[$i]
    $cand = $null
    foreach ($w in $wins) {
      if ($used -contains $w.hwnd) { continue }
      if ($w.minimized) { continue }
      if ($need.match -and ($w.app -notlike "*$($need.match)*") -and ($w.title -notlike "*$($need.match)*") -and ($w.class -notlike "*$($need.match)*")) { continue }
      if ($busy.ContainsKey($w.hwnd)) { if (-not $blockedHit) { $blockedHit = $busy[$w.hwnd] }; continue }
      $cand = $w; break
    }
    if (-not $cand) { continue }
    $used += $cand.hwnd

    if ($needList.Count -eq 1) {
      $rx = $wx + $gap; $ry = $wy + $gap; $rw = $ww - 2 * $gap; $rh = $wh - 2 * $gap
      $rect = @($rx, $ry, $rw, $rh)
    } elseif ($i -eq 0) {
      $rx = $wx + $gap; $ry = $wy + $gap; $rw = [int](($ww - 3 * $gap) * 0.66); $rh = $wh - 2 * $gap
      $rect = @($rx, $ry, $rw, $rh)
    } else {
      $remain = $needList.Count - 1
      $slotW = [int](($ww - 3 * $gap - [int](($ww - 3 * $gap) * 0.66)) / [Math]::Max(1, $remain))
      $x = $wx + 2 * $gap + [int](($ww - 3 * $gap) * 0.66) + ($i - 1) * $slotW
      $ry = $wy + $gap; $rw = $slotW - $gap; $rh = $wh - 2 * $gap
      $rect = @($x, $ry, $rw, $rh)
    }
    $assign += [pscustomobject]@{
      window  = $cand.hwnd
      app     = $cand.app
      title   = $cand.title
      display = $cand.display
      from    = $cand.win
      rect    = $rect
      action  = "move"
    }
  }

  if ($assign.Count -eq 0) {
    if ($blockedHit) {
      $left = 0
      try { $left = [int]([datetime]$blockedHit.expires - (Get-Date)).TotalSeconds } catch { }
      return [pscustomobject]@{ ok = $false; error = "window_owned_by"; window = $blockedHit.window
        owner_agent = $blockedHit.agent; owner_since = $blockedHit.ts; expires_in_s = $left
        hint = "该窗口正被另一个 Agent 使用；换窗口，或等它 release" }
    }
    return [pscustomobject]@{ ok = $false; error = "no_window"; hint = "没有匹配到托管屏上的窗口；先打开目标软件" }
  }

  if (-not $DryRun) {
    $state = $state0
    if (-not $state) {
      $state = [pscustomobject]@{ mode = $mode; created = (Get-Date).ToString("o"); items = @() }
    }
    $leaseId = "ls_" + [guid]::NewGuid().ToString("N").Substring(0, 6)
    $ttl = 300
    $items = @()
    foreach ($a in $assign) {
      $hv = [Convert]::ToInt64($a.window, 16)
      $h = [IntPtr]$hv
      if ([DDIR]::IsZoomed($h)) { [void][DDIR]::ShowWindow($h, [DDIR]::SW_RESTORE); Start-Sleep -Milliseconds 60 }
      [void][DDIR]::SetWindowPos($h, [IntPtr]::Zero, $a.rect[0], $a.rect[1], $a.rect[2], $a.rect[3],
        ([DDIR]::SWP_NOZORDER -bor [DDIR]::SWP_NOACTIVATE -bor [DDIR]::SWP_SHOWWINDOW))
      $items += [pscustomobject]@{ window = $a.window; action = "move"; agent = $script:Agent; lease = $leaseId
        from = $a.from; to = $a.rect; ts = (Get-Date).ToString("o"); expires = ((Get-Date).AddSeconds($ttl)).ToString("o") }
    }
    $state.items = @($state.items) + $items
    Save-State $state
    Write-Audit "claim" @{ lease = $leaseId; assign = $assign }
    return [pscustomobject]@{ ok = $true; lease = $leaseId; mode = $mode; displays_managed = @($managed.uid); assign = $assign; focus = "none"; ttl_s = $ttl }
  }
  return [pscustomobject]@{ ok = $true; dry_run = $true; mode = $mode; displays_managed = @($managed.uid); assign = $assign; focus = "none" }
}

function Resolve-OwnedWindow([string]$hwnd) {
  $win = (Get-Windows) | Where-Object { $_.hwnd -eq $hwnd } | Select-Object -First 1
  if (-not $win) { return [pscustomobject]@{ ok = $false; error = "no_window" } }
  $apps = Get-Apps
  $rec = $apps.PSObject.Properties | Where-Object { $_.Value.app -eq $win.app } | Select-Object -First 1
  if (-not $rec) { return [pscustomobject]@{ ok = $false; error = "not_owned"; win = $win; hint = ("先 ddir own --app `"$($win.app)`" 认领，再操作它") } }
  if ($rec.Value.owner -ne $script:Agent) { return [pscustomobject]@{ ok = $false; error = "owned_by_other"; win = $win; owner_agent = $rec.Value.owner; owner_since = $rec.Value.since } }
  [pscustomobject]@{ ok = $true; win = $win; app = $win.app }
}
function Add-StateItem($item) {
  $st = Get-State
  if (-not $st) { $st = [pscustomobject]@{ lease = ("ls_" + [guid]::NewGuid().ToString("N").Substring(0, 6)); agent = $script:Agent; mode = (Get-Mode); created = (Get-Date).ToString("o"); items = @() } }
  $st.items = @($st.items) + $item
  Save-State $st
  $st.lease
}

# ---------- dispatch ----------
switch ($Command.ToLower()) {
  "help" {
    @"
ddir — Desktop Director 参考实现（M1 行为参考 / M0 测试台）

  ddir mode [off|semi|auto]            查看/切换档位
  ddir displays                        托管屏 / 用户屏（JSON）
  ddir list [--text]                   窗口列表（过滤到 Alt+Tab 级）
  ddir status                          租约 / 我负责的软件 / 用户空闲
  ddir plan [--needs "a:1000x700,b"]   只算不做的布局预演
  ddir claim [--needs "a:1000x700,b"]  申请并摆放（SetWindowPos，不抢焦点）
  ddir move --window 0x... --rect x,y,w,h
  ddir release [--all]                 还原到 claim 前的位置
  ddir hide --window 0x... / show --window 0x...   隐藏/显示（需先 own）
  ddir own --app <name> / disown --app <name>
  ddir close --window 0x...            优雅关闭（仅限自己 own 过的 app；WM_CLOSE，不重试）
  ddir board                           看板

环境变量：DDIR_HOME（默认 ~\.ddir）、DDIR_AGENT（调用方标识，默认 pid-<PID>）
"@
    break
  }
  "mode" {
    if ($Rest -and $Rest.Count -gt 0 -and (@("off", "semi", "auto") -contains $Rest[0])) { Set-Mode $Rest[0]; Write-Audit "mode" @{ to = $Rest[0] } }
    $a = Get-Activity
    Write-Json ([pscustomobject]@{ ok = $true; mode = (Get-Mode); agent = $script:Agent
      input_age_s = $a.input_age_s; user_active = $a.user_active
      cursor_moved_px = $a.cursor_moved_px; foreground_changed = $a.foreground_changed; signal = $a.signal })
    break
  }
  "displays" {
    $ds = Get-Displays
    Write-Json ([pscustomobject]@{ ok = $true; mode = (Get-Mode); managed = @($ds | Where-Object { $_.managed }); user = @($ds | Where-Object { -not $_.managed }) })
    break
  }
  "list" {
    $w = Get-Windows
    if ($Rest -contains "--text") {
      $w | Select-Object hwnd, app, display, @{ n = "rect"; e = { $_.rect -join "," } }, title | Format-Table -AutoSize | Out-String -Width 200
    } else {
      Write-Json ([pscustomobject]@{ ok = $true; count = $w.Count; windows = $w })
    }
    break
  }
  "status" {
    $state = Get-State
    $apps = Get-Apps
    $a = Get-Activity
    $mine = @()
    $others = @()
    if ($state) {
      $nowS = Get-Date
      foreach ($it in @($state.items)) {
        $exp = $null
        try { if ($it.expires) { $exp = [datetime]$it.expires } } catch { }
        if ($exp -and $exp -le $nowS) { continue }
        if (-not $it.agent -or $it.agent -eq $script:Agent) { $mine += $it } else { $others += $it }
      }
    }
    $hide = @($mine | Where-Object { $_.action -eq "hide" }).Count
    $o = [pscustomobject]@{
      ok = $true; mode = (Get-Mode); you = $script:Agent
      leases = $mine.Count
      lease = $(if ($mine.Count -gt 0) { $mine[0].lease } else { $null })
      windows = @($mine | ForEach-Object { [pscustomobject]@{ window = $_.window; action = $_.action; expires = $_.expires } })
      held_by_others = $others.Count
      owns = @($apps.PSObject.Properties | Where-Object { $_.Value.owner -eq $script:Agent } | ForEach-Object { $_.Name })
      hidden_by_you = $hide
      focus_holder = "none"
      input_age_s = $a.input_age_s
      user_active = $a.user_active
      cursor_moved_px = $a.cursor_moved_px
      foreground_changed = $a.foreground_changed
      signal = $a.signal
    }
    Write-Json $o
    break
  }
  "plan" {
    $needs = ($Rest | Where-Object { $_ -notlike "--*" } | Select-Object -First 1)
    $r = Invoke-Claim -needsSpec $needs -DryRun
    Write-Json $r
    break
  }
  "claim" {
    $needs = ($Rest | Where-Object { $_ -notlike "--*" } | Select-Object -First 1)
    if (-not ($Rest -contains "--force")) {
      $a = Get-Activity
      if ($a.user_active) { Write-Json ([pscustomobject]@{ ok = $false; error = "user_active"; user_active = $true; hint = "用户正在操作；等它空闲，或加 --force" }); break }
    }
    $r = Invoke-Claim -needsSpec $needs
    Write-Json $r
    break
  }
  "move" {
    $hwnd = $null; $rect = $null
    for ($i = 0; $i -lt $Rest.Count; $i++) {
      if ($Rest[$i] -eq "--window") { $hwnd = $Rest[$i + 1] }
      if ($Rest[$i] -eq "--rect") {
        $parts = @()
        $j = $i + 1
        while ($j -lt $Rest.Count -and $Rest[$j] -notlike "--*" -and $parts.Count -lt 4) {
          $parts += @($Rest[$j]) | ForEach-Object { [string]$_ }
          $j++
        }
        $rect = ($parts -join ",")
      }
    }
    if (-not $hwnd -or -not $rect) { Write-Json ([pscustomobject]@{ ok = $false; error = "invalid_args"; hint = "move --window 0x... --rect x,y,w,h" }); break }
    if ($rect -is [array]) { $p = @($rect | ForEach-Object { [int]$_ }) } else { $p = @($rect -split "," | ForEach-Object { [int]$_ }) }
    if (-not ($Rest -contains "--force")) {
      $a = Get-Activity
      if ($a.user_active) { Write-Json ([pscustomobject]@{ ok = $false; error = "user_active"; user_active = $true; hint = "用户正在操作；等它空闲，或加 --force" }); break }
    }
    $h = [IntPtr][Convert]::ToInt64($hwnd, 16)
    $ok = [DDIR]::SetWindowPos($h, [IntPtr]::Zero, $p[0], $p[1], $p[2], $p[3],
      ([DDIR]::SWP_NOZORDER -bor [DDIR]::SWP_NOACTIVATE -bor [DDIR]::SWP_SHOWWINDOW))
    Write-Audit "move" @{ window = $hwnd; rect = $p }
    Write-Json ([pscustomobject]@{ ok = [bool]$ok; window = $hwnd; rect = $p })
    break
  }
  "release" {
    $state = Get-State
    if (-not $state) { Write-Json ([pscustomobject]@{ ok = $true; released = 0 }); break }
    $mine = @($state.items | Where-Object { -not $_.agent -or $_.agent -eq $script:Agent })
    $others = @($state.items | Where-Object { $_.agent -and $_.agent -ne $script:Agent })
    $n = 0
    foreach ($it in $mine) {
      $h = [IntPtr][Convert]::ToInt64($it.window, 16)
      if ($it.action -eq "hide") { [void][DDIR]::ShowWindow($h, 4); $n++; continue }
      [void][DDIR]::SetWindowPos($h, [IntPtr]::Zero, $it.from[0], $it.from[1], $it.from[2], $it.from[3],
        ([DDIR]::SWP_NOZORDER -bor [DDIR]::SWP_NOACTIVATE -bor [DDIR]::SWP_SHOWWINDOW))
      $n++
    }
    if ($others.Count -gt 0) { $state.items = $others; Save-State $state } else { Remove-Item $StateFile -ErrorAction SilentlyContinue }
    Write-Audit "release" @{ restored = $n; mine = $mine.Count; kept_others = $others.Count }
    Write-Json ([pscustomobject]@{ ok = $true; released = $n; other_leases_kept = $others.Count })
    break
  }
  "own" {
    $app = $null
    for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq "--app") { $app = $Rest[$i + 1] } }
    if (-not $app) { Write-Json ([pscustomobject]@{ ok = $false; error = "invalid_args"; hint = "own --app <name>" }); break }
    $apps = Get-Apps
    $existing = $apps.PSObject.Properties | Where-Object { $_.Value.app -eq $app } | Select-Object -First 1
    if ($existing -and $existing.Value.owner -ne $script:Agent) {
      $since = $null
      try { $since = [datetime]::Parse($existing.Value.since) } catch { }
      $expired = ($since -and (((Get-Date) - $since).TotalSeconds -gt [double]$existing.Value.ttl_s))
      if (-not $expired) {
      Write-Json ([pscustomobject]@{ ok = $false; error = "owned_by_other"; owner_agent = $existing.Value.owner; owner_since = $existing.Value.since; hint = "换实例或等它 disown" })
      break
      }
    }
    $rec = [pscustomobject]@{ app = $app; owner = $script:Agent; since = (Get-Date).ToString("o"); ttl_s = 1800 }
    if ($existing) { $apps.($existing.Name) = $rec } else { $apps | Add-Member -NotePropertyName $app -NotePropertyValue $rec -Force }
    Save-Apps $apps
    Write-Audit "own" @{ app = $app }
    Write-Json ([pscustomobject]@{ ok = $true; app = $app; owner = $script:Agent })
    break
  }
  "disown" {
    $app = $null
    for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq "--app") { $app = $Rest[$i + 1] } }
    $apps = Get-Apps
    $existing = $apps.PSObject.Properties | Where-Object { $_.Value.app -eq $app } | Select-Object -First 1
    if ($existing) { $apps.PSObject.Properties.Remove($existing.Name); Save-Apps $apps }
    Write-Audit "disown" @{ app = $app }
    Write-Json ([pscustomobject]@{ ok = $true; app = $app })
    break
  }
  "close" {
    $hwnd = $null
    for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq "--window") { $hwnd = $Rest[$i + 1] } }
    if (-not $hwnd) { Write-Json ([pscustomobject]@{ ok = $false; error = "invalid_args"; hint = "close --window 0x..." }); break }
    $r = Resolve-OwnedWindow $hwnd
    if (-not $r.ok) { Write-Json ([pscustomobject]@{ ok = $false; error = $r.error; hint = $r.hint; owner_agent = $r.owner_agent; owner_since = $r.owner_since }); break }
    $h = [IntPtr][Convert]::ToInt64($hwnd, 16)
    [void][DDIR]::CloseGraceful($h)
    $dead = $false
    for ($k = 0; $k -lt 30; $k++) { Start-Sleep -Milliseconds 100; if (-not [DDIR]::IsWindow($h)) { $dead = $true; break } }
    Write-Audit "close" @{ window = $hwnd; app = $r.app; closed = $dead }
    if ($dead) {
      Write-Json ([pscustomobject]@{ ok = $true; closed = $true; window = $hwnd; app = $r.app })
    } else {
      Write-Json ([pscustomobject]@{ ok = $false; error = "close_blocked"; window = $hwnd
        reason = "3 秒内未退出（可能有未保存内容或模态框）；不重试、不强杀" })
    }
    break
  }
  "hide" {
    $hwnd = $null
    for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq "--window") { $hwnd = $Rest[$i + 1] } }
    if (-not $hwnd) { Write-Json ([pscustomobject]@{ ok = $false; error = "invalid_args"; hint = "hide --window 0x..." }); break }
    $r = Resolve-OwnedWindow $hwnd
    if (-not $r.ok) { Write-Json ([pscustomobject]@{ ok = $false; error = $r.error; hint = $r.hint; owner_agent = $r.owner_agent }); break }
    $h = [IntPtr][Convert]::ToInt64($hwnd, 16)
    [void][DDIR]::ShowWindow($h, 0)
    $null = Add-StateItem ([pscustomobject]@{ window = $hwnd; action = "hide"; from = $r.win.win })
    Write-Audit "hide" @{ window = $hwnd; app = $r.app }
    Write-Json ([pscustomobject]@{ ok = $true; hidden = $true; window = $hwnd; app = $r.app })
    break
  }
  "show" {
    $hwnd = $null
    for ($i = 0; $i -lt $Rest.Count; $i++) { if ($Rest[$i] -eq "--window") { $hwnd = $Rest[$i + 1] } }
    if (-not $hwnd) { Write-Json ([pscustomobject]@{ ok = $false; error = "invalid_args"; hint = "show --window 0x..." }); break }
    $h = [IntPtr][Convert]::ToInt64($hwnd, 16)
    [void][DDIR]::ShowWindow($h, 4)
    Write-Audit "show" @{ window = $hwnd }
    Write-Json ([pscustomobject]@{ ok = $true; shown = $true; window = $hwnd })
    break
  }
  "board" {
    $state = Get-State
    $apps = Get-Apps
    $mode = Get-Mode
    $act = Get-Activity
    "== ddir mode $mode   焦点 none   input_age=$($act.input_age_s)s  user_active=$($act.user_active)  cursor_moved=$($act.cursor_moved_px)px"
    "== 窗口 $(@(Get-Windows).Count) 个（托管屏 $((Get-ManagedDisplays | ForEach-Object { $_.uid }) -join ',')）"
    if ($state) {
      $groups = @($state.items | Group-Object agent)
      foreach ($g in $groups) { "== lease $($g.Name)：$(($g.Group | ForEach-Object { $_.window }) -join ', ')" }
    } else { "== 无租约" }
    foreach ($p in $apps.PSObject.Properties) { "== owned: $($p.Value.app) -> $($p.Value.owner)" }
    break
  }
  default {
    Write-Json ([pscustomobject]@{ ok = $false; error = "unknown_command"; hint = "ddir mode|displays|list|status|plan|claim|move|release|own|disown|close|board" })
  }
}
