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
$worktreePaths = @{}
$worktreePath = $null
foreach ($line in git worktree list --porcelain) {
    if ($line -match '^worktree (.+)$') {
        $worktreePath = $Matches[1]
    }
    elseif ($line -match '^branch refs/heads/(.+)$' -and $worktreePath) {
        $worktreePaths[$Matches[1]] = $worktreePath
    }
}
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
    Where-Object {
        $_ -and
        $_ -ne $currentBranch
    })

if ($goneBranches) {
    Write-Host "Local branches that are not present on origin:" -ForegroundColor Yellow
    $goneBranches | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }

    Write-Host "`nChoose for each branch: [y]es, [n]o, [a]ll remaining, [q]uit." -ForegroundColor Cyan
    $deleteAll = $false
    $deletedBranches = @()

    foreach ($branch in $goneBranches) {
        if (-not $deleteAll -or $worktreePaths[$branch]) {
            $worktreePath = $worktreePaths[$branch]
            if ($worktreePath) {
                Write-Host "Branch '$branch' is used by worktree '$worktreePath'." -ForegroundColor Yellow
                $choice = (Read-Host "Remove the worktree and delete the branch, including local changes? [y/n]").Trim().ToLowerInvariant()
                if ($choice -notin @('y', 'yes')) {
                    continue
                }

                git worktree remove --force -- $worktreePath
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Could not remove worktree '$worktreePath'." -ForegroundColor Red
                    continue
                }
            }
            else {
                do {
                    $choice = (Read-Host "Delete local branch '$branch'? [y/n/a/q]").Trim().ToLowerInvariant()
                } while ($choice -notin @('y', 'n', 'a', 'q', ''))

                if ($choice -eq 'q') {
                    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
                    break
                }

                if ($choice -eq 'a') {
                    $deleteAll = $true
                }

                if ($choice -ne 'y' -and $choice -ne 'a') {
                    continue
                }
            }
        }

        git branch -D -- $branch
        if ($LASTEXITCODE -eq 0) {
            $deletedBranches += $branch
        }
    }

    if ($deletedBranches.Count -gt 0) {
        Write-Host "Deleted local branches: $($deletedBranches -join ', ')" -ForegroundColor Green
    }
}
else {
    Write-Host "No local branches to delete." -ForegroundColor Green
}