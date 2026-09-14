# Fast git branch for the prompt.
#
# starship's git modules cost ~130ms per prompt on this machine, and it is the
# repo OPEN that costs it, not the branch lookup - any one git module pays it:
#
#   prompt with $git_branch ... 147 ms
#   prompt with no git module .. 16 ms
#
# But reading .git/HEAD directly is 0.16ms. So do that, publish the branch in
# an environment variable, and let starship render it with its [env_var] module
# - which touches no repository at all.
#
# starship calls Invoke-Starship-PreCommand before each prompt (see its init),
# which is the hook used below.

function script:Get-GitBranchFast {
    $dir = (Get-Location).ProviderPath
    if (-not $dir) { return $null }

    while ($dir) {
        $git = Join-Path $dir '.git'
        if (Test-Path -LiteralPath $git) {
            $headFile = $null

            if ((Get-Item -LiteralPath $git -Force).PSIsContainer) {
                $headFile = Join-Path $git 'HEAD'
            } else {
                # Worktrees and submodules use a .git FILE: "gitdir: <path>"
                $line = [System.IO.File]::ReadAllText($git).Trim()
                if ($line -match '^gitdir:\s*(.+)$') {
                    $gitDir = $matches[1].Trim()
                    if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
                        $gitDir = Join-Path $dir $gitDir
                    }
                    $headFile = Join-Path $gitDir 'HEAD'
                }
            }

            if ($headFile -and (Test-Path -LiteralPath $headFile)) {
                $head = [System.IO.File]::ReadAllText($headFile).Trim()
                if ($head.StartsWith('ref: refs/heads/')) {
                    return $head.Substring(16)
                }
                # Detached HEAD: show a short sha.
                if ($head.Length -ge 7) { return $head.Substring(0, 7) }
            }
            return $null
        }

        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# starship invokes this before rendering, if it exists.
function global:Invoke-Starship-PreCommand {
    $branch = Get-GitBranchFast
    if ($branch) {
        $env:STARSHIP_GIT_BRANCH = $branch
    } elseif (Test-Path Env:STARSHIP_GIT_BRANCH) {
        Remove-Item Env:STARSHIP_GIT_BRANCH -ErrorAction SilentlyContinue
    }
}
