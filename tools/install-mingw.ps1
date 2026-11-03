# install-mingw.ps1 - MSYS2 (TUNA mirror) + mingw-w64 gcc, user-space, no admin
$ErrorActionPreference = 'Stop'
$root = 'F:\envs\msys64'
$log  = 'F:\desktop-director\.install-mingw.log'
function Log($m) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; $line; $line | Add-Content -Path $log -Encoding UTF8 }
$ProgressPreference = 'SilentlyContinue'
Log "start"

$exe = 'F:\envs\msys2-install.exe'
New-Item -ItemType Directory -Force -Path 'F:\envs' | Out-Null
if (-not (Test-Path $exe)) {
  Log "downloading msys2 installer from TUNA"
  & curl.exe -L --fail -o $exe 'https://mirrors.tuna.tsinghua.edu.cn/msys2/distrib/msys2-x86_64-latest.exe'
  if ($LASTEXITCODE -ne 0) { throw "curl failed: $LASTEXITCODE" }
}
Log ("installer size: " + [math]::Round((Get-Item $exe).Length/1MB,1) + " MB")

if (-not (Test-Path (Join-Path $root 'usr\bin\bash.exe'))) {
  Log "installing to $root (silent)"
  $p = Start-Process -FilePath $exe -ArgumentList @('in','--confirm-command','--accept-messages','--accept-licenses','--root', $root) -PassThru -Wait
  Log ("installer exit: " + $p.ExitCode)
}
$bash = Join-Path $root 'usr\bin\bash.exe'
if (-not (Test-Path $bash)) { throw "msys2 bash not found at $bash" }
Log "msys2 installed"

# point pacman at TUNA mirrors
$ml = Join-Path $root 'etc\pacman.d\mirrorlist.mingw'
$mlMsys = Join-Path $root 'etc\pacman.d\mirrorlist.msys'
$mingwLines = @(
  'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/$repo/',
  'Server = https://mirrors.ustc.edu.cn/msys2/mingw/$repo/'
)
$msysLines = @(
  'Server = https://mirrors.tuna.tsinghua.edu.cn/msys2/msys/$arch/',
  'Server = https://mirrors.ustc.edu.cn/msys2/msys/$arch/'
)
Set-Content -Path $ml -Value $mingwLines -Encoding ASCII
Set-Content -Path $mlMsys -Value $msysLines -Encoding ASCII
Log "mirrors set to TUNA"

$env:MSYSTEM = 'MINGW64'
$env:CHERE_INVOKING = '1'
Log "pacman -Sy"
& $bash -lc 'pacman -Sy --noconfirm' 2>&1 | ForEach-Object { Log ("  " + $_) }
Log "pacman -S gcc"
& $bash -lc 'pacman -S --noconfirm --needed mingw-w64-x86_64-gcc' 2>&1 | ForEach-Object { Log ("  " + $_) }

$gcc = Join-Path $root 'mingw64\bin\gcc.exe'
if (Test-Path $gcc) { Log ("gcc: " + (& $gcc --version | Select-Object -First 1)) } else { throw "gcc not installed" }
Log "done"
