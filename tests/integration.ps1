# Integration test for ddir (Windows). Runs against an isolated DDIR_HOME and unique file names.
param(
    [string]$Exe = "F:\desktop-director\target\release\ddir.exe"
)
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if ($ok) { $script:pass++; Write-Host ("PASS  " + $name) }
    else { $script:fail++; Write-Host ("FAIL  " + $name + "  " + $detail) }
}
function D([string[]]$argv) { return ((& $Exe @argv) -join "`n") }
function J([string[]]$argv) { return (D $argv | ConvertFrom-Json) }

$tag = [guid]::NewGuid().ToString("N").Substring(0, 6)
$nameA = "$tag-a.txt"; $nameB = "$tag-b.txt"
$tmp = Join-Path $env:TEMP ("ddir-it-$tag")
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$env:DDIR_HOME = $tmp
$env:DDIR_AGENT = "it-agent"
Set-Content "$tmp\$nameA" "alpha" -Encoding ASCII
Set-Content "$tmp\$nameB" "beta" -Encoding ASCII

Check "version runs" ((D @('version')).Length -gt 0)
& $Exe mode semi | Out-Null
Check "mode = semi" ((J @('mode')).mode -eq 'semi')

Start-Process notepad "$tmp\$nameA" | Out-Null; Start-Sleep -Milliseconds 900
Start-Process notepad "$tmp\$nameB" | Out-Null; Start-Sleep -Milliseconds 900

$wins = (J @('list')).windows | Where-Object { $_.app -eq 'notepad' -and $_.title -like "*$tag*" }
Check "two demo windows" ($wins.Count -ge 2) ("got " + $wins.Count)
if ($wins.Count -lt 2) {
    Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*$tag*" } | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Write-Host "RESULT: $pass passed, $fail failed"; exit 1
}
$wa = $wins | Where-Object { $_.title -like "*$nameA*" } | Select-Object -First 1
$wb = $wins | Where-Object { $_.title -like "*$nameB*" } | Select-Object -First 1
$origA = $wa.win

$r1 = J @('claim','--needs',$nameA,'--force')
Check "claim 1 ok" ($r1.ok -eq $true)
Check "claim 1 single column" (@($r1.assign).Count -eq 1)

$r2 = J @('claim','--needs',$nameB,'--force')
Check "claim 2 ok" ($r2.ok -eq $true)
Check "claim 2 has two columns" (@($r2.assign).Count -eq 2)
Check "claim 2 retiled the old one" ($r2.retiled -eq 1)
$a2 = @($r2.assign)[0]; $b2 = @($r2.assign)[-1]
Check "columns equal width" ([Math]::Abs($a2.rect[2] - $b2.rect[2]) -le 2) ("$($a2.rect[2]) vs $($b2.rect[2])")
Check "columns do not overlap" (($a2.rect[0] + $a2.rect[2]) -le $b2.rect[0]) ("$($a2.rect) / $($b2.rect)")

$hideWin = $wb.hwnd
$rawHide = D @('hide','--window',$hideWin)
Check "hide ok" ($rawHide -match '"ok":true') $rawHide
$vis = (J @('list')).windows | Where-Object { $_.hwnd -eq $hideWin }
Check "hidden window not listed" ($null -eq $vis)
$st = J @('status')
Check "hide recorded a lease" ($st.leases -ge 1)

$rel = J @('release')
Check "release ok" ($rel.ok -eq $true)
Start-Sleep -Milliseconds 600
$back = (J @('list')).windows | Where-Object { $_.app -eq 'notepad' -and $_.title -like "*$tag*" }
Check "both windows visible again" ($back.Count -ge 2)
$ba = $back | Where-Object { $_.title -like "*$nameA*" } | Select-Object -First 1
Check "geometry restored" ([Math]::Abs($ba.win[0] - $origA[0]) -le 2 -and [Math]::Abs($ba.win[2] - $origA[2]) -le 2) ("$($ba.win) vs $($origA)")

$pa = $back | Where-Object { $_.title -like "*$nameA*" } | Select-Object -First 1
$pb = $back | Where-Object { $_.title -like "*$nameB*" } | Select-Object -First 1
$o = J @('own','--pid', "$($pa.pid)")
Check "own --pid ok" ($o.ok -eq $true)
$c1 = J @('close','--window',$pa.hwnd)
Check "close owned window" ($c1.ok -eq $true -and $c1.closed -eq $true)
$c2 = J @('close','--window',$pb.hwnd)
Check "close unowned window refused" ($c2.ok -eq $false -and $c2.error -eq 'not_owned')
$docOut = D @('doctor')
Check "doctor reports no failures" ($docOut -match '0 failed') $docOut

Get-Process notepad -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*$tag*" } | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "---"
Write-Host ("RESULT: " + $pass + " passed, " + $fail + " failed")
if ($fail -gt 0) { exit 1 } else { exit 0 }
