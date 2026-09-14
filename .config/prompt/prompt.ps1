# Prompt. PowerShell half.
#
# The bash half is prompt.sh in this directory. They must render identically -
# change one, change the other.
#
# ---------------------------------------------------------------------------
# Why this exists instead of starship
# ---------------------------------------------------------------------------
# The prompt is a path, a branch, and a character. We already computed the
# path and branch ourselves - by reading .git/HEAD directly, because starship
# opening the repo cost ~130ms - which left starship doing nothing but emitting
# colour codes, for a process spawn on every Enter.
#
# Measured on this machine:
#   starship, before any tuning ...... 202 ms
#   starship, fully stripped ......... ~40 ms  (37ms of it the exe itself)
#   this module ...................... see the header of prompt.sh
#
# What is deliberately given up: every starship module we were not using
# anyway (language versions, cmd duration, jobs, battery, ...). If you ever
# want those back, starship is one `Invoke-Expression (&starship init ...)`
# away - but note that any module touching git re-introduces the ~130ms.
#
# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
#   <cyan>dir</> on <purple>branch</>
#   <orange>λ</>            success
#   <red>ϟ</>               failure  - differs in SHAPE as well as colour, so
#                                      it survives monochrome and colourblindness

$script:PromptMaxParts = 3

$script:Esc      = [char]27
$script:ClrDir   = "$($script:Esc)[1;36m"              # bold cyan
$script:ClrGit   = "$($script:Esc)[1;35m"              # bold purple
$script:ClrOk    = "$($script:Esc)[1;38;2;219;126;65m" # bold #db7e41
$script:ClrErr   = "$($script:Esc)[1;31m"              # bold red
$script:ClrReset = "$($script:Esc)[0m"

# Walk up for .git once, returning both the repo root and the branch.
function script:Get-RepoInfo([string]$Path) {
    $dir = $Path
    while ($dir) {
        $git = "$dir\.git"
        # .NET rather than Test-Path/Get-Item: this runs on EVERY prompt, and
        # the first filesystem cmdlet in a process costs ~27ms vs ~3ms.
        $isDir  = [System.IO.Directory]::Exists($git)
        $isFile = -not $isDir -and [System.IO.File]::Exists($git)
        if ($isDir -or $isFile) {
            $headFile = $null
            if ($isDir) {
                $headFile = "$git\HEAD"
            } else {
                # Worktrees and submodules use a .git FILE: "gitdir: <path>"
                $line = [System.IO.File]::ReadAllText($git).Trim()
                if ($line -match '^gitdir:\s*(.+)$') {
                    $gitDir = $matches[1].Trim()
                    if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
                        $gitDir = "$dir\$gitDir"
                    }
                    $headFile = "$gitDir\HEAD"
                }
            }

            $branch = $null
            if ($headFile -and [System.IO.File]::Exists($headFile)) {
                $head = [System.IO.File]::ReadAllText($headFile).Trim()
                if ($head.StartsWith('ref: refs/heads/')) {
                    $branch = $head.Substring(16)
                } elseif ($head.Length -ge 7) {
                    $branch = $head.Substring(0, 7)   # detached HEAD
                }
            }
            return @{ Root = $dir; Branch = $branch }
        }

        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return @{ Root = $null; Branch = $null }
}

function script:Get-PromptPath([string]$Path, [string]$RepoRoot) {
    if ($RepoRoot) {
        # Repo-relative, which is what starship's truncate_to_repo produced -
        # but without opening the repo to find the root.
        $repoName = [System.IO.Path]::GetFileName($RepoRoot.TrimEnd('\', '/'))
        $rel = $Path.Substring($RepoRoot.Length).Trim('\', '/')
        $display = if ($rel) { "$repoName/$($rel -replace '\\', '/')" } else { $repoName }
    } else {
        $h = $HOME.TrimEnd('\', '/')
        if ($Path.StartsWith($h, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $Path.Substring($h.Length).Trim('\', '/')
            $display = if ($rel) { "~/$($rel -replace '\\', '/')" } else { '~' }
        } else {
            $display = $Path -replace '\\', '/'
        }
    }

    $parts = $display.Split('/') | Where-Object { $_ -ne '' }
    if ($parts.Count -gt $script:PromptMaxParts) {
        $display = ($parts | Select-Object -Last $script:PromptMaxParts) -join '/'
    }
    return $display
}

function global:prompt {
    # Capture BEFORE anything else runs: every command below overwrites them.
    $ok       = $?
    $exitCode = $global:LASTEXITCODE

    $failed = (-not $ok) -or ($null -ne $exitCode -and $exitCode -ne 0)

    $path = (Get-Location).ProviderPath
    if (-not $path) { $path = (Get-Location).Path }

    $repo = Get-RepoInfo $path
    $dir  = Get-PromptPath $path $repo.Root

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($script:ClrDir).Append($dir).Append($script:ClrReset)
    if ($repo.Branch) {
        [void]$sb.Append(' on ').Append($script:ClrGit).Append($repo.Branch).Append($script:ClrReset)
    }
    [void]$sb.Append("`n")
    if ($failed) {
        [void]$sb.Append($script:ClrErr).Append([char]0x03DF)   # koppa
    } else {
        [void]$sb.Append($script:ClrOk).Append([char]0x03BB)    # lambda
    }
    [void]$sb.Append($script:ClrReset).Append(' ')

    # Put LASTEXITCODE back exactly as we found it; the shell shows it to the
    # user and our own commands above have clobbered it.
    $global:LASTEXITCODE = $exitCode

    $sb.ToString()
}
