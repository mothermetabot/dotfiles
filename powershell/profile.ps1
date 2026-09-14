# PowerShell profile. Dot-sourced by a one-line stub at $PROFILE that
# bootstrap.ps1 generates; this file is never linked or copied, so an editor
# saving over it cannot break the connection the way a hardlink could.

$DotfilesRoot = Split-Path -Parent $PSScriptRoot

# --- aliases that shadow real tools ------------------------------------------
# PowerShell ships aliases for ls/rm/gl/cat that mask the actual executables and
# the functions below.
#
# This has to happen before functions/ is dot-sourced: PowerShell resolves
# aliases BEFORE functions, so `function cat { bat ... }` alone is silently
# ignored while the built-in Get-Content alias still exists.
foreach ($a in 'ls', 'rm', 'gl', 'cat') {
    if (Test-Path "Alias:$a") { Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue }
}

# --- git quality of life ------------------------------------------------------
# Imported BEFORE functions/ on purpose: GG exports `gl` and `gs`, and the
# repo's own definitions in functions/git-shortcuts.ps1 should win. Swap these
# two blocks to prefer GG's versions instead.
$ggModulePath = Join-Path $DotfilesRoot '..\src\gg\GG.psd1'
if (Test-Path -LiteralPath $ggModulePath) { Import-Module $ggModulePath }
Remove-Variable ggModulePath -ErrorAction SilentlyContinue

# GG exports `gl` as an alias, which would still shadow the function below
# since PowerShell resolves aliases first. Same for ga/gs if GG ever aliases
# them too.
foreach ($a in 'gl', 'gs', 'ga') {
    if (Test-Path "Alias:$a") { Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue }
}

# --- functions ----------------------------------------------------------------
Get-ChildItem -LiteralPath "$PSScriptRoot\functions" -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# --- modules ------------------------------------------------------------------
# None. Both that used to load here are gone, for ~766ms off every shell start:
#
#   PSFzf     (~278ms) - atuin owns Ctrl+R now, and PSFzf's Ctrl+T collided
#                        with the psmux prefix, silently hijacking it whenever
#                        psmux started without its config.
#   posh-git  (~488ms) - its git-aware prompt duplicated starship, which
#                        already renders $git_branch and $git_status. Only its
#                        tab-completion was unique, which is not worth half a
#                        second per shell.
#
# Measured medians: bare shell 180ms, full profile was ~1755ms with both.

# --- prompt and navigation ----------------------------------------------------
# Both of these were previously pasted in as generated output - 130 lines of
# zoxide init frozen at whatever version generated it. Generating at startup
# keeps them current.
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    # --cmd c => `c` to jump, `ci` to pick interactively.
    Invoke-Expression (& { (zoxide init powershell --cmd c | Out-String) })
}

# atuin owns Ctrl+R; it replaced PSFzf entirely.
#
# atuin's PowerShell init hard-requires PSReadLine and writes an error without
# it. PSReadLine is absent in non-interactive shells (powershell -Command ...),
# so gate on it rather than emit noise in every script that starts a shell.
if ((Get-Command atuin -ErrorAction SilentlyContinue) -and
    (Get-Module -Name PSReadLine)) {
    try { Invoke-Expression (& { (atuin init powershell | Out-String) }) }
    catch { Write-Verbose "atuin init failed: $($_.Exception.Message)" }
}

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
