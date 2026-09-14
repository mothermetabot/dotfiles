# Prompt data computed in-shell, so starship never has to open a git repo.
#
# starship's git modules cost ~130ms per prompt on this machine, and it is the
# repo OPEN that costs it - `directory` pays the same price when
# truncate_to_repo is on, because it opens the repo just to find the root.
# Reading .git/HEAD directly is 0.16ms.
#
# So we walk up for .git once and publish two variables, which starship renders
# with its [env_var] module without touching git at all:
#
#   STARSHIP_GIT_BRANCH   branch name, or short sha when detached
#   STARSHIP_DIR          repo-relative path when in a repo, ~-relative outside
#
# .bashrc has a byte-for-byte equivalent so the shared starship.toml renders
# identically on Linux. Change one, change the other.

$script:PromptMaxParts = 3

function script:Get-PromptPathDisplay {
    param([string]$Path, [string]$RepoRoot)

    if ($RepoRoot) {
        # Repo-relative: "<reponame>/sub/dir". This is what starship's
        # truncate_to_repo produces, without the repo open.
        $repoName = Split-Path -Leaf $RepoRoot
        $rel = $Path.Substring($RepoRoot.Length).Trim('\', '/')
        $display = if ($rel) { "$repoName/$($rel -replace '\\', '/')" } else { $repoName }
    } else {
        $home_ = $HOME.TrimEnd('\', '/')
        if ($Path.StartsWith($home_, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $Path.Substring($home_.Length).Trim('\', '/')
            $display = if ($rel) { "~/$($rel -replace '\\', '/')" } else { '~' }
        } else {
            $display = $Path -replace '\\', '/'
        }
    }

    # Keep only the last N components, like starship's truncation_length.
    $parts = $display.Split('/') | Where-Object { $_ -ne '' }
    if ($parts.Count -gt $script:PromptMaxParts) {
        $display = ($parts | Select-Object -Last $script:PromptMaxParts) -join '/'
    }
    return $display
}

function script:Update-PromptVars {
    $path = (Get-Location).ProviderPath
    if (-not $path) { return }

    $branch   = $null
    $repoRoot = $null

    $dir = $path
    while ($dir) {
        $git = Join-Path $dir '.git'
        if (Test-Path -LiteralPath $git) {
            $repoRoot = $dir
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
                    $branch = $head.Substring(16)
                } elseif ($head.Length -ge 7) {
                    $branch = $head.Substring(0, 7)   # detached HEAD
                }
            }
            break
        }

        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }

    if ($branch) {
        $env:STARSHIP_GIT_BRANCH = $branch
    } elseif (Test-Path Env:STARSHIP_GIT_BRANCH) {
        Remove-Item Env:STARSHIP_GIT_BRANCH -ErrorAction SilentlyContinue
    }

    $env:STARSHIP_DIR = Get-PromptPathDisplay -Path $path -RepoRoot $repoRoot
}

# starship invokes this before rendering, if it exists.
function global:Invoke-Starship-PreCommand { Update-PromptVars }
