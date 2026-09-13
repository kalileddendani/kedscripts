if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
    Write-Host "Error: Current directory is not inside a Git repository." -ForegroundColor Red
    exit 1
}

Write-Host "Updating local remote-tracking references..." -ForegroundColor Cyan
git fetch --prune
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Could not update local remote-tracking references." -ForegroundColor Red
    exit 1
}

$currentBranch = git branch --show-current
$remoteBranches = @(git for-each-ref --format='%(refname:short)' refs/remotes/origin |
    Where-Object { $_ -ne 'origin/HEAD' } |
    ForEach-Object { $_ -replace '^origin/', '' })
$goneBranches = @(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads |
    ForEach-Object {
        $parts = $_ -split ' ', 2
        $branch = $parts[0]
        $track = if ($parts.Count -gt 1) { $parts[1] } else { '' }

        if (($track -match '\[gone\]$') -or
            (($track -eq '') -and ($remoteBranches -notcontains $branch))) {
            $branch
        }
    } |
    Where-Object { $_ -and $_ -ne $currentBranch })

if ($goneBranches) {
    Write-Host "Local branches to delete:" -ForegroundColor Yellow
    $goneBranches | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }

    Write-Host "Deleting local branches..." -ForegroundColor Cyan
    foreach ($branch in $goneBranches) {
        git branch -D $branch
    }
    Write-Host "Local branch cleanup completed." -ForegroundColor Green
}
else {
    Write-Host "No local branches to delete." -ForegroundColor Green
}