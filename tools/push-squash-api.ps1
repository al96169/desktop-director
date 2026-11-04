# Squash-push current HEAD to GitHub through the REST API.
# Use when github.com:443 is blocked but api.github.com works.
# Reads file contents from the working tree (so it publishes the CURRENT state, not per-commit history).
param(
    [string]$Repo = "al96169/desktop-director",
    [string]$Base = "3b34116",   # last local commit whose tree is already on the remote
    [string]$Message = ""
)
$ErrorActionPreference = 'Stop'
Set-Location 'F:\desktop-director'

if (-not $Message) { $Message = (& git log -1 --format=%s) + "`n`n(squashed push via GitHub API)" }

$remote = (& gh api "repos/$Repo/git/ref/heads/main" | ConvertFrom-Json)
$parent = $remote.object.sha
$baseTree = (& gh api "repos/$Repo/git/commits/$parent" --jq .tree.sha | Out-String).Trim()
"remote main = $parent (tree $baseTree)"

$diff = @(& git diff --name-status "$Base" HEAD)
"changed vs $Base : $($diff.Count)"
$entries = @()
foreach ($line in $diff) {
    if (-not $line) { continue }
    $parts = $line -split "`t"
    $status = $parts[0]
    if ($status -eq 'D') {
        $entries += @{ path = $parts[1]; mode = '100644'; type = 'blob'; sha = $null }
        continue
    }
    if ($status.StartsWith('R')) { continue }  # no renames in practice; ignore
    $path = $parts[1]
    $full = Join-Path 'F:\desktop-director' $path
    if (-not (Test-Path $full)) { "skip (missing): $path"; continue }
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($full))
    $body = @{ content = $b64; encoding = 'base64' } | ConvertTo-Json -Compress
    $blob = ($body | & gh api "repos/$Repo/git/blobs" --input - | Out-String | ConvertFrom-Json)
    $entries += @{ path = $path; mode = '100644'; type = 'blob'; sha = $blob.sha }
    "  blob $path -> $($blob.sha.Substring(0,8))"
}
$treeBody = @{ base_tree = $baseTree; tree = $entries } | ConvertTo-Json -Depth 8 -Compress
$tree = ($treeBody | & gh api "repos/$Repo/git/trees" --input - | Out-String | ConvertFrom-Json)
$commitBody = @{ message = $Message; tree = $tree.sha; parents = @($parent) } | ConvertTo-Json -Compress
$newCommit = ($commitBody | & gh api "repos/$Repo/git/commits" --input - | Out-String | ConvertFrom-Json)
"new commit $($newCommit.sha)"
(& gh api -X PATCH "repos/$Repo/git/refs/heads/main" -f sha=$newCommit.sha -F force=true | Out-Null)
"tree local : " + (& git rev-parse "HEAD^{tree}")
"tree remote: " + $tree.sha
"PUSHED $($newCommit.sha)"
