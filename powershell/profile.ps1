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
# Installed by bootstrap.ps1, not here: the old profile ran Install-Module
# probes on every shell start.
#
# These two dominate startup. Medians over 5 runs on this machine:
#
#   bare shell (-NoProfile) .......  180 ms
#   profile without these two .....  845 ms
#   + posh-git .................... +488 ms
#   + PSFzf ....................... +278 ms
#   full profile .................. 1755 ms
#
# Import-Module directly rather than guarding with Get-Module -ListAvailable,
# which scans the whole module path a second time for no benefit.
#
# NOTE: posh-git's git-aware prompt is redundant with starship, which already
# renders $git_branch and $git_status (see .config/starship.toml), so its 488ms
# buys git tab-completion and nothing else. Delete the line to get it back.
try { Import-Module PSFzf -ErrorAction Stop; Set-PsFzfOption -PSReadlineChordReverseHistory 'Ctrl+r' } catch { }
try { Import-Module posh-git -ErrorAction Stop } catch { }

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

# atuin replaces shell history search. Initialised AFTER PSFzf on purpose:
# both bind Ctrl+R, and atuin should win. Remove the PSFzf import above if you
# settle on atuin, since that is most of what PSFzf was doing here.
#
# atuin's PowerShell init hard-requires PSReadLine and writes an error without
# it. PSReadLine is absent in non-interactive shells (powershell -Command ...),
# so gate on it rather than emit noise in every script that starts a shell.
if ((Get-Command atuin -ErrorAction SilentlyContinue) -and
    (Get-Module -Name PSReadLine)) {
    try { Invoke-Expression (& { (atuin init powershell | Out-String) }) }
    catch { Write-Verbose "atuin init failed: $($_.Exception.Message)" }
}

# --- machine-local overrides --------------------------------------------------
# Gitignored. Put work-specific paths, proxies and credentials here.
$localProfile = Join-Path $PSScriptRoot 'profile.local.ps1'
if (Test-Path -LiteralPath $localProfile) { . $localProfile }
Remove-Variable localProfile -ErrorAction SilentlyContinue
