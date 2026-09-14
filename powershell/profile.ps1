# PowerShell profile. Dot-sourced by a one-line stub at $PROFILE that
# bootstrap.ps1 generates; this file is never linked or copied, so an editor
# saving over it cannot break the connection the way a hardlink could.
#
# Startup budget, measured medians on this machine:
#   bare shell (-NoProfile) ....  128 ms
#   this profile ............... ~250 ms
#   before the perf pass ....... ~900 ms
#
# What was removed to get there, and why, is noted inline. Keep new work out of
# the startup path: prefer a lazy stub or a cached init over an import.

$DotfilesRoot = Split-Path -Parent $PSScriptRoot

# --- aliases that shadow real tools ------------------------------------------
# PowerShell ships aliases for rm/gl/cat that mask the actual executables and
# the functions below. `ls` keeps its built-in alias: eza is not used.
#
# This has to happen before functions/ is dot-sourced: PowerShell resolves
# aliases BEFORE functions, so `function cat { bat ... }` alone is silently
# ignored while the built-in Get-Content alias still exists.
foreach ($a in 'rm', 'gl', 'cat', 'gs', 'ga') {
    if (Test-Path "Alias:$a") { Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue }
}

# --- functions ----------------------------------------------------------------
Get-ChildItem -LiteralPath "$PSScriptRoot\functions" -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# --- git quality of life (lazy) -----------------------------------------------
# Importing GG cost 137 ms on every shell start, and the only command it
# uniquely provides is `gg` - its ga/gl/gs are overridden by
# functions/git-shortcuts.ps1 anyway.
#
# So `gg` is a stub that loads the module on first use, then re-applies the
# repo's own definitions (Import-Module would otherwise shadow them) and
# forwards the call.
$script:GGModulePath = Join-Path $DotfilesRoot '..\src\gg\GG.psd1'
if (Test-Path -LiteralPath $script:GGModulePath) {
    function gg {
        Remove-Item function:gg -Force -ErrorAction SilentlyContinue
        Import-Module $script:GGModulePath -Force

        # GG re-exports ga/gl/gs; put ours back on top.
        . "$PSScriptRoot\functions\git-shortcuts.ps1"
        foreach ($a in 'gl', 'gs', 'ga') {
            if (Test-Path "Alias:$a") { Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue }
        }

        & (Get-Command gg -CommandType Function, Cmdlet, Alias | Select-Object -First 1) @args
    }
}

# --- modules ------------------------------------------------------------------
# None, deliberately.
#
#   PSFzf     (~278ms + 43ms of option calls) - replaced by
#             functions/fzf-history.ps1, which does the same fzf Ctrl+R in ~25
#             lines. It also bound Ctrl+T, the psmux prefix, and silently
#             swallowed it whenever psmux started without its config.
#   posh-git  (~488ms) - its git-aware prompt duplicated starship, which
#             already renders $git_branch and $git_status. Only tab-completion
#             was unique, which is not worth half a second per shell.

# --- prompt and navigation ----------------------------------------------------
# Both inits are cached (see functions/init-cache.ps1): they spawn the tool to
# print a script that only changes on upgrade. starship additionally gets its
# scoop shim unwrapped, because the path it bakes into the prompt is invoked on
# every single Enter.
Use-CachedInit -Name 'starship' -Command 'starship' `
    -Arguments @('init', 'powershell', '--print-full-init') `
    -Transform {
        param($s)
        $shim = (Get-Command starship -CommandType Application | Select-Object -First 1).Source
        $real = Resolve-ScoopShim $shim
        if ($real -ne $shim) { $s = $s.Replace($shim, $real) }
        $s
    }

# --cmd c => `c` to jump, `ci` to pick interactively.
Use-CachedInit -Name 'zoxide' -Command 'zoxide' -Arguments @('init', 'powershell', '--cmd', 'c')

# --- psmux -------------------------------------------------------------------
# psmux does not follow tmux's XDG search, so it needs this to find the shared
# .config/tmux/tmux.conf. bootstrap.ps1 also sets it at User scope, but that
# only reaches processes started AFTER the registry change propagates - a
# terminal opened beforehand launches psmux with stock defaults and no error.
#
# The failure is silent and confusing: prefix falls back to C-b, so Ctrl+T is
# never captured and falls through to whatever the shell has bound.
if (-not $env:PSMUX_CONFIG_FILE) {
    $env:PSMUX_CONFIG_FILE = Join-Path $DotfilesRoot '.config\tmux\tmux.conf'
}

# --- machine-local overrides --------------------------------------------------
# Gitignored. Put work-specific paths, proxies and credentials here.
$localProfile = Join-Path $PSScriptRoot 'profile.local.ps1'
if (Test-Path -LiteralPath $localProfile) { . $localProfile }
Remove-Variable localProfile -ErrorAction SilentlyContinue
