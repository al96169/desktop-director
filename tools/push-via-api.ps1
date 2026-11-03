# Push local commits through the GitHub REST API (works when github.com:443 is blocked).
# Requires: gh CLI authenticated with repo scope. Uses Git Data API (blobs/trees/commits/refs).
$ErrorActionPreference = 'Stop'
$repo = 'al96169/desktop-director'
$root = 'F:\desktop-director'
Set-Location $root

function GhJson([string[]]$ghArgs) {
    $json = $ghArgs | & gh api @ghArgs 2>&1 | Out-String
    return $json
}

$remote = (& gh api "repos/$repo/git/ref/heads/main" | ConvertFrom-Json)
$parent = $remote.object.sha
"remote main = $parent"

$commits = @(& git rev-list "origin/main..HEAD" --reverse)
if ($commits.Count -eq 0) { "nothing to push"; exit 0 }
"local commits: $($commits -join ', ')"

foreach ($c in $commits) {
    $msg = (& git log -1 --format=%B $c) -join "`n"
    $diff = @(& git diff-tree --no-commit-id --name-status -r $c)
    $entries = @()
    foreach ($line in $diff) {
        if (-not $line) { continue }
        $parts = $line -split "`t"
        $status = $parts[0]
        $path = $parts[1]
        if ($status -eq 'D') {
            $entries += @{ path = $path; mode = '100644'; type = 'blob'; sha = $null }
            continue
        }
        $full = Join-Path $root $path
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($full))
        $body = @{ content = $b64; encoding = 'base64' } | ConvertTo-Json -Compress
        $blob = ($body | & gh api "repos/$repo/git/blobs" --input - | Out-String | ConvertFrom-Json)
        $entries += @{ path = $path; mode = '100644'; type = 'blob'; sha = $blob.sha }
    }
    "commit $c : $($entries.Count) files"
    $baseTree = (& gh api "repos/$repo/git/commits/$parent" --jq .tree.sha | Out-String).Trim()
    $treeBody = @{ base_tree = $baseTree; tree = $entries } | ConvertTo-Json -Depth 8 -Compress
    $tree = ($treeBody | & gh api "repos/$repo/git/trees" --input - | Out-String | ConvertFrom-Json)
    $commitBody = @{ message = $msg; tree = $tree.sha; parents = @($parent) } | ConvertTo-Json -Compress
    $newCommit = ($commitBody | & gh api "repos/$repo/git/commits" --input - | Out-String | ConvertFrom-Json)
    $parent = $newCommit.sha
    "  -> $parent"
}

(& gh api -X PATCH "repos/$repo/git/refs/heads/main" -f sha=$parent -F force=true | Out-String).Trim()
& git update-ref refs/remotes/origin/main $parent
"PUSHED via API: $parent"
& git log --oneline -3
