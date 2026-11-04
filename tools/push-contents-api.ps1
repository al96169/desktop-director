# Push current working tree through the GitHub Contents API (one commit per file).
# Fallback for when github.com:443 is blocked but api.github.com works.
param(
    [string]$Repo = "al96169/desktop-director",
    [string]$Base = "3b34116",
    [string]$Message = "chore: sync %PATH% (0.3.0, via Contents API)"
)
$ErrorActionPreference = 'Stop'
Set-Location 'F:\desktop-director'

function Get-Sha([string]$path) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $r = & gh api "repos/$Repo/contents/$path" --jq '.sha' 2>$null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { return $null }
    return ($r | Out-String).Trim()
}

$diff = @(& git diff --name-status "$Base" HEAD)
"changed: $($diff.Count)"
foreach ($line in $diff) {
    if (-not $line) { continue }
    $parts = $line -split "`t"
    $status = $parts[0]
    $path = $parts[1]
    $msg = $Message.Replace('%PATH%', $path)
    $existing = Get-Sha $path
    if ($status -eq 'D') {
        if ($existing) {
            $body = @{ message = $msg; sha = $existing } | ConvertTo-Json -Compress
            $body | & gh api -X DELETE "repos/$Repo/contents/$path" --input - | Out-Null
            "deleted $path"
        }
        continue
    }
    $full = Join-Path 'F:\desktop-director' $path
    if (-not (Test-Path $full)) { "skip (missing) $path"; continue }
    $localBlob = (& git hash-object $full).Trim()
    if ($existing -eq $localBlob) { "same $path"; continue }
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($full))
    $payload = @{ message = $msg; content = $b64; encoding = 'base64' }
    if ($existing) { $payload.sha = $existing }
    ($payload | ConvertTo-Json -Compress) | & gh api -X PUT "repos/$Repo/contents/$path" --input - | Out-Null
    "put $path"
}
$head = (& gh api "repos/$Repo/git/ref/heads/main" | ConvertFrom-Json).object.sha
"remote head now: $head"
$remoteTree = (& gh api "repos/$Repo/git/commits/$head" --jq .tree.sha | Out-String).Trim()
$localTree = (& git rev-parse "HEAD^{tree}").Trim()
"remote tree: $remoteTree"
"local  tree: $localTree"
if ($remoteTree -eq $localTree) { "TREES IDENTICAL - content in sync" } else { "TREES DIFFER" }
