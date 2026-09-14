# PowerShell profile. Dot-sourced by a one-line stub at $PROFILE that
# bootstrap.ps1 generates; this file is never linked or copied, so an editor
# saving over it cannot break the connection the way a hardlink could.
#
# Startup budget, measured medians on this machine:
#   bare shell (-NoProfile) ....  128 ms
#   this profile ...............  see the numbers in git log
#   before the perf pass ....... ~900 ms
#
# Keep new work out of the startup path: prefer a lazy stub or a cached init
# over an import.
#
# AND PREFER .NET CALLS OVER CMDLETS HERE. The first use of a filesystem cmdlet
# in a process costs ~27ms - loading the provider and JITing the cmdlet - while
# the .NET equivalent is ~3ms. Measured in fresh processes:
#
#   Test-Path ....................... 27.2 ms   [IO.File]::Exists ........ 2.9 ms
#   Get-ChildItem ................... 28.4 ms   [IO.Directory]::GetFiles . 3.2 ms
#   (Get-Item x).LastWriteTimeUtc ... 29.0 ms   [IO.File]::GetLastWrite... 3.0 ms
#
# That is why this file looks less idiomatic than it otherwise would.

$DotfilesRoot = Split-Path -Parent $PSScriptRoot

# --- aliases that shadow real tools ------------------------------------------
# PowerShell ships aliases for rm/gl/cat that mask the actual executables and
# the functions below. `ls` keeps its built-in alias: eza is not used.
#
# This has to happen before functions/ is dot-sourced: PowerShell resolves
# aliases BEFORE functions, so `function cat { bat ... }` alone is silently
# ignored while the built-in Get-Content alias still exists.
#
# Only these three are real built-in aliases. gs and ga used to be here too,
# but only because the old GG module exported them; that module is gone.
#
# One Remove-Item, no Test-Path: -ErrorAction already covers a missing alias,
# and Test-Path was a second provider hit for nothing. -Ignore rather than
# -SilentlyContinue, which still appends to $Error.
Remove-Item -Path Alias:rm, Alias:gl, Alias:cat -Force -ErrorAction Ignore

# --- functions ----------------------------------------------------------------
foreach ($f in [System.IO.Directory]::GetFiles("$PSScriptRoot\functions", '*.ps1')) { . $f }

# --- gg -----------------------------------------------------------------------
# The GG PowerShell module is gone: ~/home/src/gg is now a Rust project and
# ships no .psd1, so the lazy-import stub that used to live here could never
# fire again. Only a debug build exists and it is not on PATH - if you want
# `gg` back, `cargo install --path ~/home/src/gg` and it needs nothing here.

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

# --- prompt -------------------------------------------------------------------
# Native, no starship. The prompt is a path, a branch and a character; we were
# already reading .git/HEAD ourselves, so starship was left emitting colour
# codes for a process spawn on every Enter. See .config/prompt/prompt.ps1.
. "$DotfilesRoot\.config\prompt\prompt.ps1"

# --- navigation ---------------------------------------------------------------
# Cached (see functions/init-cache.ps1): zoxide spawns to print a script that
# only changes on upgrade. --cmd c => `c` to jump, `ci` to pick interactively.
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
    $env:PSMUX_CONFIG_FILE = "$DotfilesRoot\.config\tmux\tmux.conf"
}

# --- machine-local overrides --------------------------------------------------
# Gitignored. Put work-specific paths, proxies and credentials here.
$localProfile = "$PSScriptRoot\profile.local.ps1"
if ([System.IO.File]::Exists($localProfile)) { . $localProfile }
