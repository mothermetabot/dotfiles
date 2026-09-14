# Cache for tool init scripts.
#
# `zoxide init` spawns the tool just to print a shell script that changes only
# when the tool is upgraded - 91 ms on this machine. Caching to a file and
# regenerating only when the exe is newer removes it from every shell start.
#
# This also cached starship's init (270 ms, because the bootstrap it prints
# immediately re-runs --print-full-init) until the prompt was replaced by
# .config/prompt/, which needs no external process at all.

function script:Use-CachedInit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]   $Name,
        [Parameter(Mandatory)][string]   $Command,
        [Parameter(Mandatory)][string[]] $Arguments,
        # Optional rewrite of the generated script before caching.
        [scriptblock] $Transform
    )

    $exe = (Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1)
    if (-not $exe) { return }

    $cacheRoot = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { $env:LOCALAPPDATA }
    $cacheDir  = Join-Path $cacheRoot 'dotfiles-init'
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $cache = Join-Path $cacheDir "$Name.ps1"

    # Regenerate when the cache is missing or older than the executable.
    $stale = $true
    if (Test-Path -LiteralPath $cache) {
        $stale = (Get-Item -LiteralPath $cache).LastWriteTimeUtc -lt
                 (Get-Item -LiteralPath $exe.Source).LastWriteTimeUtc
    }

    if ($stale) {
        $script = & $exe.Source @Arguments | Out-String
        if ($Transform) { $script = & $Transform $script }
        Set-Content -LiteralPath $cache -Value $script -Encoding utf8
    }

    . $cache
}
