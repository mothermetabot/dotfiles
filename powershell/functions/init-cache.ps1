# Cache for tool init scripts.
#
# `starship init` and `zoxide init` each spawn the tool just to print a shell
# script that changes only when the tool is upgraded. Measured on this machine:
#
#   starship init powershell ... 270 ms   (TWO spawns: the bootstrap it prints
#                                          immediately re-runs --print-full-init)
#   zoxide init powershell .....  91 ms
#
# Caching to a file and regenerating only when the exe is newer removes both
# from every shell start.

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

# Resolve past scoop's shim to the real executable.
#
# A scoop shim is a 136 KB launcher that reads a .shim file and re-execs the
# target, so every invocation pays TWO process starts. Measured:
#
#   starship via shim ... 42.1 ms
#   real starship.exe ... 20.3 ms
#   cmd /c exit ......... 9.2 ms   (spawn floor on this box)
#
# starship bakes the resolved path into its init and calls it on every prompt,
# so the ~22ms shim tax lands on every Enter. This unwraps it.
function script:Resolve-ScoopShim {
    param([Parameter(Mandatory)][string] $Path)

    $shim = [System.IO.Path]::ChangeExtension($Path, '.shim')
    if (Test-Path -LiteralPath $shim) {
        $line = (Get-Content -LiteralPath $shim | Where-Object { $_ -match '^\s*path\s*=' } | Select-Object -First 1)
        if ($line) {
            $target = ($line -split '=', 2)[1].Trim().Trim('"')
            if (Test-Path -LiteralPath $target) { return $target }
        }
    }
    return $Path
}
