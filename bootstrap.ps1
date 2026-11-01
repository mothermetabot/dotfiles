<#
.SYNOPSIS
    Provision this machine from the dotfiles repo. Windows side.

.DESCRIPTION
    Replaces the old bootstrap.bat. Three differences worth knowing:

    1. No admin, except the MSVC step. Unprivileged symlinks need Developer
       Mode, which is not enabled here and may be policy-blocked. So:
       directory *junctions* (which never need privileges) for config
       directories, and environment variables for everything else. Nothing
       uses mklink /H - hardlinks silently break when an editor saves via
       write-temp-then-rename, which is how the PowerShell profile drifted out
       of sync before.

       The one exception is the MSVC build tools step. Microsoft ships no
       unprivileged installer for the C++ toolset and no scoop bucket carries
       it, so that step asks before it elevates and is skippable - everything
       else completes whether you say yes or no.

    2. Env-var-first. komorebi, whkd and psmux all accept a config path
       directly, so they get no link at all. Fewer moving parts than linking.

    3. The PowerShell profile is a generated one-line stub that dot-sources the
       repo, not a link. Immune to rename-on-save by construction.

    Layout note: the repo root mirrors $HOME the way GNU stow expects, so Linux
    runs a single `stow .` over the exact same tree (see .stow-local-ignore for
    what is held back). On Windows the deploy target is %USERPROFILE%, because
    that is where 32 of your 36 dotdirs already live. $HOME (~\home) is your
    workspace root and is deliberately left alone.

.PARAMETER DryRun
    Print every change without making it. Run this first.

.PARAMETER SkipPackages
    Skip scoop installs; only deploy config.

.PARAMETER SkipMsvc
    Skip the MSVC build tools step without asking. Use when you know this
    machine builds no Rust or C/C++, or when running unattended.

.PARAMETER Yes
    Answer yes to every prompt instead of asking. The MSVC and komorebi
    autostart steps are the only interactive ones, so this makes the whole run
    unattended - note that MSVC still raises a UAC dialog, which no switch can
    suppress.

.EXAMPLE
    .\bootstrap.ps1 -DryRun
    .\bootstrap.ps1
    .\bootstrap.ps1 -Yes
    .\bootstrap.ps1 -SkipMsvc
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipPackages,
    [switch]$SkipMsvc,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repo   = $PSScriptRoot
$Target = $env:USERPROFILE
$Xdg    = Join-Path $Target '.config'

$script:Changed = 0
$script:Skipped = 0
$script:Warned  = 0

# Steps number themselves. They were hand-numbered as [n/7] strings before,
# which meant inserting a step touched every other heading - and the headings
# silently disagreed with each other whenever that was done incompletely.
$script:Step  = 0
$script:Steps = 12

function Write-Head($t) {
    $script:Step++
    Write-Host "`n[$script:Step/$script:Steps] $t" -ForegroundColor Green
}
function Write-Do($m)   { Write-Host "  + $m" -ForegroundColor Cyan;     $script:Changed++ }
function Write-Skip($m) { Write-Host "  = $m" -ForegroundColor DarkGray; $script:Skipped++ }
function Write-Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow;   $script:Warned++ }
function Write-Plan($m) { Write-Host "  ? $m" -ForegroundColor Magenta;  $script:Changed++ }

# =============================================================================
# What gets deployed
# =============================================================================

# Every directory under .config/ is junctioned into $XDG_CONFIG_HOME. Discovered
# rather than listed, so adding a tool means adding a directory and nothing else.
#
# Directory junctions are the only link type available unprivileged, which is
# fine here: loose FILES under .config/ are not linked at all, they are pointed
# at by an environment variable instead. See $EnvVars.
$LinuxOnlyConfig = @('i3', 'i3status', 'rofi')

$Junctions = @(
    Get-ChildItem -LiteralPath "$Repo\.config" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $LinuxOnlyConfig -notcontains $_.Name } |
        ForEach-Object {
            @{ Name = $_.Name; Link = "$Xdg\$($_.Name)"; Target = $_.FullName }
        }
)

# nvim also gets its Windows-native location, for the same reason ~/.gitconfig
# gets an include stub: a process that did not inherit XDG_CONFIG_HOME would
# otherwise fall back to %LOCALAPPDATA%\nvim and find nothing. Both paths
# resolve to the same directory, so the config is reachable either way.
$Junctions += @{
    Name   = 'nvim (LOCALAPPDATA fallback)'
    Link   = "$env:LOCALAPPDATA\nvim"
    Target = "$Repo\.config\nvim"
}

# $HOME points at the workspace root (~\home), not at %USERPROFILE%. Unix-ish
# tools resolve ~ through $HOME, so without this they look in
# ~\home\.config\<tool> and find nothing - which is exactly how psmux silently
# ran with stock defaults instead of .config/tmux/tmux.conf.
#
# Aliasing the whole directory rather than adding a per-tool fallback means any
# future XDG tool works under either home with no extra wiring.
if ($env:HOME -and $env:HOME.TrimEnd('\') -ne $Target.TrimEnd('\')) {
    $Junctions += @{
        Name   = 'HOME/.config alias'
        Link   = "$($env:HOME.TrimEnd('\'))\.config"
        Target = $Xdg
    }
}

# Claude Code keeps config and machine-local state in the same directory, so
# ~/.claude is NEVER linked wholesale: sessions, projects, history.jsonl, the
# memory directory and .credentials.json all live there, and .credentials.json
# must never reach a git repo. Only the config subdirectories are linked, by
# name rather than by discovery - the point is to hold the list down to what
# is safe, so a new state directory appearing upstream cannot opt itself in.
#
# settings.json is a loose FILE and so cannot be junctioned; it gets copied,
# see the 'Claude Code settings' step.
$ClaudeDirs = @('skills', 'agents', 'commands')

$Junctions += @(
    $ClaudeDirs | ForEach-Object {
        @{ Name = ".claude/$_"; Link = "$Target\.claude\$_"; Target = "$Repo\.claude\$_" }
    }
)

# User-scope environment. Machine scope is never used: these are per-user tools,
# and bootstrap.bat's `setx /M` required two UAC prompts to set variables that
# (as the live machine shows) were only ever actually set at User scope anyway.
#
# HOME is deliberately absent. It points at your workspace root (~\home) and is
# not this script's business.
$EnvVars = [ordered]@{
    'XDG_CONFIG_HOME'      = $Xdg
    'XDG_DATA_HOME'        = "$Target\.local\share"
    'XDG_STATE_HOME'       = "$Target\.local\state"
    'XDG_CACHE_HOME'       = "$Target\.cache"
    # psmux does not follow tmux's XDG search, so point it straight at the
    # shared config. It branches internally with if-shell; there is no
    # Windows-specific config file and nothing is generated.
    'PSMUX_CONFIG_FILE'    = "$Repo\.config\tmux\tmux.conf"
    'KOMOREBI_CONFIG_HOME' = "$Repo\komorebi"
    'WHKD_CONFIG_HOME'     = "$Repo\komorebi"
}

# Directories that must exist as REAL directories, not junctions. This is the
# whole trick that keeps tool-written state out of the repo: $XDG_CONFIG_HOME
# itself is real, and only the per-tool subdirectories below it are junctions.
# Junction the parent instead and every tool that writes to ~/.config dirties
# your git tree - which is exactly how startup.log, .nvimlog, scoop/config.json
# and uv-receipt.json ended up tracked.
#
# ~/.claude is in this list for the same reason and with extra force: it holds
# .credentials.json. Junction it and the credentials land in the repo.
$RealDirs = @(
    $Xdg
    "$Target\.local\share"
    "$Target\.local\state"
    "$Target\.cache"
    "$Target\.claude"
)

# PowerShell profile stubs. CurrentUserCurrentHost matches what was linked
# before. The PowerShell 7 path is written too, harmlessly, so the profile is
# already in place if pwsh is ever installed (it is not, today).
$ProfileStubs = @(
    "$Target\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    "$Target\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)

$PSModules = @()

# Windows Terminal font. The face is the FAMILY name as Windows reports it,
# not the registry's file-registration name (CommitMonoNerdFontMono-Regular):
# get it wrong and Windows Terminal silently falls back to Consolas with no
# error anywhere. Verify a change here with:
#
#   Add-Type -AssemblyName System.Drawing
#   (New-Object System.Drawing.Text.InstalledFontCollection).Families
#
# The -NF-Mono build is the one installed by packages.tsv, chosen because it
# forces single-width glyphs - see the font notes there.
$TerminalFont = 'CommitMono Nerd Font Mono'

# Every Windows Terminal channel that might be installed. Store builds keep
# settings under their package's LocalState; the unpackaged build does not.
# All present ones are patched - having stable and preview disagree about the
# font is exactly the kind of thing this script exists to prevent.
$TerminalSettings = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

# =============================================================================
# Helpers
# =============================================================================

# Read a file whole, or $null if it is not there.
function Get-TextOrNull([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
}

# Compare a file against generated content, ignoring three differences that
# are invisible in a diff and meant nothing here:
#
#   BOM          Set-Content -Encoding utf8 on PS 5.1 writes one, and
#                Get-Content -Raw hands it back as a leading U+FEFF. It is a
#                format character, not whitespace, so .Trim() does NOT remove
#                it and a raw comparison can never match.
#   line endings the here-strings below inherit this file's endings, while
#                the written file gets whatever Set-Content produces.
#   trailing \n  Set-Content appends one; the here-strings do not have it.
#
# Without this every run rewrote both stubs and reported changes it did not
# need to make, which buried the real changes in noise.
function Test-FileHasContent([string]$Path, [string]$Expected) {
    $cur = Get-TextOrNull $Path
    if ($null -eq $cur) { return $false }
    $norm = {
        param($s)
        ($s -replace "^$([char]0xFEFF)", '' -replace "`r`n", "`n").TrimEnd()
    }
    return (& $norm $cur) -eq (& $norm $Expected)
}

function Test-IsReparsePoint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $i = Get-Item -LiteralPath $Path -Force
    return ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

function Get-JunctionTarget([string]$Path) {
    if (-not (Test-IsReparsePoint $Path)) { return $null }
    $i = Get-Item -LiteralPath $Path -Force
    # PS 5.1 exposes .Target as a collection; normalise and strip any \??\ prefix.
    $t = @($i.Target)[0]
    if ($null -eq $t) { return $null }
    return ($t -replace '^\\\?\?\\', '').TrimEnd('\')
}

# Delete a junction WITHOUT recursing into it. Remove-Item -Recurse on a
# reparse point can delete the target's contents on PowerShell 5.1 - here the
# target is the dotfiles repo, so this matters.
function Remove-JunctionSafely([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-IsReparsePoint $Path)) {
        throw "Refusing to remove '$Path': it is a real directory, not a junction."
    }
    [System.IO.Directory]::Delete($Path, $false)
}

function New-Junction([string]$Link, [string]$LinkTarget) {
    New-Item -ItemType Junction -Path $Link -Target $LinkTarget -ErrorAction Stop | Out-Null
}

# Is the MSVC C++ toolset (cl.exe, link.exe, the SDK libs) installed?
#
# Testing for link.exe on PATH proves nothing: it is only on PATH inside a
# developer prompt, and rustc does not need it there - the cc crate locates the
# toolset through vswhere and the registry. So probe the way rustc does.
#
# vswhere ships with every VS installer since 2017 at a fixed path, so its
# absence means no VS or Build Tools of any edition. -requires narrows to
# installs that actually carry the C++ workload; a Visual Studio with only the
# .NET workload has no link.exe and must still count as missing.
function Invoke-VsWhere([string[]]$Arguments) {
    $pf = ${env:ProgramFiles(x86)}
    if (-not $pf) { return $null }
    $vswhere = Join-Path $pf 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    # -property takes exactly ONE name. Passing a comma-joined list returns
    # empty output and exit 0, which is indistinguishable from "not installed"
    # unless you know to look for it.
    $out = & $vswhere @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (@($out) | Where-Object { $_ } | Select-Object -First 1)
}

# An install that actually carries the C++ toolset. This is the only probe
# that answers "will cargo link", so it is what every decision below turns on.
function Get-MsvcInstallPath {
    Invoke-VsWhere @(
        '-products', '*', '-latest',
        '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
        '-property', 'installationPath')
}

# ANY Visual Studio or Build Tools install, workload or not. The distinction
# matters: a Build Tools instance with no C++ workload - which is what a plain
# `winget install` of the package produces - leaves winget reporting the
# package installed and refusing to act, while cargo still cannot find
# link.exe. Adding a workload to that needs the installer's `modify` verb.
function Get-VsInstallPath {
    Invoke-VsWhere @('-products', '*', '-latest', '-property', 'installationPath')
}

# Ask until the answer is exactly yes or no. Deliberately NOT y/n: this one
# elevates and costs a multi-gigabyte download, so it should not be answerable
# by a stray keystroke.
#
# A redirected stdin (CI, `| .\bootstrap.ps1`) would make Read-Host either hang
# or spin on EOF, so treat a non-interactive session as "no" - the caller can
# pass -SkipMsvc to say so explicitly and skip the warning.
function Read-YesNo([string]$Question) {
    if ($Yes) {
        Write-Host "  $Question [yes/no] yes (-Yes)" -ForegroundColor DarkGray
        return $true
    }
    if ([Console]::IsInputRedirected) {
        Write-Warn 'stdin is not a console; assuming no'
        return $false
    }
    while ($true) {
        $a = (Read-Host "  $Question [yes/no]").Trim().ToLowerInvariant()
        if ($a -eq 'yes') { return $true }
        if ($a -eq 'no')  { return $false }
        Write-Host "  Please type 'yes' or 'no'." -ForegroundColor DarkGray
    }
}

# PS 5.1 leaves junctions unresolved in .FullName. Walk the parent chain and
# substitute each reparse point for its target, so a link path and a target can
# be compared for actual on-disk identity rather than by spelling.
function Resolve-RealPath([string]$Path) {
    $cur = $Path.TrimEnd('\'); $rest = @()
    while ($cur) {
        if (Test-IsReparsePoint $cur) {
            $t = Get-JunctionTarget $cur
            if ($t) { $cur = $t; continue }
        }
        $parent = Split-Path -Parent $cur
        if (-not $parent -or $parent -eq $cur) { break }
        $rest = ,(Split-Path -Leaf $cur) + $rest
        $cur  = $parent
    }
    return (@($cur.TrimEnd('\')) + $rest) -join '\'
}

# =============================================================================
# Preconditions
# =============================================================================

Write-Head 'Preconditions'

if (-not (Test-Path -LiteralPath "$Repo\install\packages.tsv")) {
    throw "packages.tsv not found. Is `$PSScriptRoot ($Repo) the repo root?"
}
Write-Skip "repo root: $Repo"
Write-Skip "deploy target: $Target"

if ($Repo -like "$Target\*" -and $Repo -notlike "$Target\home\*") {
    Write-Warn "repo lives under the deploy target; junction loops are possible"
}

# git finds the tracked config through XDG_CONFIG_HOME, but only for processes
# that inherited that variable. Anything started without it - an older session,
# a GUI tool launched from Explorer - would silently lose the identity and
# aliases entirely.
#
# So rather than just moving the legacy ~/.gitconfig out of the way, replace it
# with a two-line include. git always reads $HOME/.gitconfig regardless of XDG,
# which makes the config reachable both ways. Same stub pattern as $PROFILE.
$GitconfigStub = @"
# Managed by dotfiles ($Repo). Do not edit - edit the repo file instead.
# Present so git resolves the config even when XDG_CONFIG_HOME is not set.
[include]
	path = $($Repo -replace '\\', '/')/.config/git/config
"@

foreach ($home_ in @($env:HOME, $Target) | Where-Object { $_ } | Sort-Object -Unique) {
    $gc  = Join-Path $home_ '.gitconfig'
    $cur = Get-TextOrNull $gc

    if (Test-FileHasContent $gc $GitconfigStub) { Write-Skip $gc; continue }

    # A real pre-existing config carries settings that are not in the repo yet
    # (credential helpers, machine paths). Never clobber it silently.
    if ($null -ne $cur -and $cur -notmatch 'Managed by dotfiles') {
        $bak = "$gc.pre-dotfiles"
        if ($DryRun) {
            Write-Plan "would back up $gc -> $bak, then write include stub"
            continue
        }
        Move-Item -LiteralPath $gc -Destination $bak -Force
        Write-Do "backed up $gc -> $bak"
    } elseif ($DryRun) {
        Write-Plan "would write git include stub to $gc"
        continue
    }

    Set-Content -LiteralPath $gc -Value $GitconfigStub -Encoding ascii
    Write-Do "git include stub -> $gc"
}

# =============================================================================
# Packages
# =============================================================================

Write-Head 'Packages (scoop)'

if ($SkipPackages) {
    Write-Skip 'skipped (-SkipPackages)'
} elseif (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Warn 'scoop not on PATH - skipping package install'
    Write-Warn 'install it with: iwr -useb get.scoop.sh | iex'
} else {
    $rows = Get-Content "$Repo\install\packages.tsv" |
        Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') } |
        ForEach-Object {
            $c = $_ -split "`t"
            if ($c.Count -ge 2) { [pscustomobject]@{ Name = $c[0].Trim(); Scoop = $c[1].Trim() } }
        } |
        Where-Object { $_.Scoop -and $_.Scoop -ne '-' }

    # `local:` entries are manifests in this repo, not bucket/package ids.
    $buckets = @($rows |
        Where-Object { -not $_.Scoop.StartsWith('local:') } |
        ForEach-Object { ($_.Scoop -split '/')[0] } | Sort-Object -Unique)
    $have    = @(scoop bucket list 6>$null | ForEach-Object { $_.Name })

    foreach ($b in $buckets) {
        if ($have -contains $b) { Write-Skip "bucket $b"; continue }
        if ($DryRun) { Write-Plan "would add bucket $b"; continue }
        scoop bucket add $b
        if ($LASTEXITCODE -ne 0) { Write-Warn "failed to add bucket $b"; continue }
        Write-Do "added bucket $b"
    }

    $installed = @(scoop list 6>$null | ForEach-Object { $_.Name })
    foreach ($r in $rows) {
        # local:install/scoop/gg.json -> install name 'gg', path under $Repo
        if ($r.Scoop.StartsWith('local:')) {
            # Forward slashes are fine on Windows; no separator rewrite needed.
            $rel   = $r.Scoop.Substring(6)
            $spec  = Join-Path $Repo $rel
            $short = [System.IO.Path]::GetFileNameWithoutExtension($spec)
            if (-not [System.IO.File]::Exists($spec)) {
                Write-Warn "$($r.Name): manifest missing at $spec"
                continue
            }
        } else {
            $spec  = $r.Scoop
            $short = ($r.Scoop -split '/')[-1]
        }
        if ($installed -contains $short) { Write-Skip "$($r.Name)"; continue }
        if ($DryRun) { Write-Plan "would install $spec"; continue }
        scoop install $spec
        # Deliberately non-fatal: one unavailable manifest must not abort the
        # whole bootstrap. bootstrap.bat pretended to be fatal here but its
        # helper always returned 0, so all 22 error handlers were dead code.
        if ($LASTEXITCODE -ne 0) { Write-Warn "could not install $spec"; continue }
        Write-Do "installed $spec"
    }
}

# =============================================================================
# Real directories
# =============================================================================

Write-Head 'Base directories'

foreach ($d in $RealDirs) {
    if (Test-IsReparsePoint $d) {
        # A junctioned ~/.config (bootstrap.bat's doing) aliases the deploy
        # target onto the source: $Xdg\git then resolves back into the repo, so
        # step 3's "back up the existing dir" branch renames the repo's own
        # .config\git and the junction that follows fails on a missing target.
        # Dropping the reparse point loses nothing - step 3 re-links every
        # subdirectory it pointed at. Only safe when it points at this repo.
        # Safe to drop only when it points into the repo: the content survives
        # at the target and step 3 re-links the subdirectories. A junction to
        # anywhere else may be the only path to real data, so refuse that.
        $t = Get-JunctionTarget $d
        if (-not ($t -and $t.ToLowerInvariant().StartsWith($Repo.ToLowerInvariant()))) {
            throw "'$d' is a junction to '$t', which is outside this repo. Resolve it by hand before re-running."
        }
        if ($DryRun) { Write-Plan "would replace junction $d ($t) with a real directory"; continue }
        Remove-JunctionSafely $d   # deletes the link only, never the target
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Do "replaced junction $d ($t) with a real directory"
        continue
    }
    if (Test-Path -LiteralPath $d) { Write-Skip $d; continue }
    if ($DryRun) { Write-Plan "would create $d"; continue }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Write-Do "created $d"
}

# =============================================================================
# Config junctions
# =============================================================================

Write-Head 'Config junctions'

foreach ($j in $Junctions) {
    if (-not (Test-Path -LiteralPath $j.Target)) {
        Write-Warn "$($j.Name): target missing, skipping -> $($j.Target)"
        continue
    }

    $want = $j.Target.TrimEnd('\')
    $cur  = Get-JunctionTarget $j.Link

    if ($cur -eq $want) { Write-Skip "$($j.Name) -> $want"; continue }

    if (Test-Path -LiteralPath $j.Link) {
        if (Test-IsReparsePoint $j.Link) {
            if ($DryRun) {
                Write-Plan "would relink $($j.Name): $cur -> $want"
            } else {
                Remove-JunctionSafely $j.Link
                New-Junction $j.Link $want
                Write-Do "relinked $($j.Name) -> $want"
            }
        } else {
            # Link and Target are the same directory, reached through an
            # aliased parent (a junctioned ~/.config, or $env:HOME pointing at
            # %USERPROFILE%). Backing it up would rename the repo's own files,
            # so refuse rather than "move it out of the way".
            if ((Resolve-RealPath $j.Link) -ieq (Resolve-RealPath $want)) {
                Write-Warn "$($j.Name): $($j.Link) already resolves to $want via an aliased parent - skipping"
                continue
            }
            # A real directory with real content. Never delete it blind.
            $n = @(Get-ChildItem -LiteralPath $j.Link -Force -ErrorAction SilentlyContinue).Count
            if ($n -gt 0) {
                $bak = "$($j.Link).pre-dotfiles"
                if ($DryRun) {
                    Write-Plan "would move existing $($j.Link) ($n items) -> $bak, then junction"
                } else {
                    Move-Item -LiteralPath $j.Link -Destination $bak -Force
                    New-Junction $j.Link $want
                    Write-Do "moved existing $($j.Name) -> $bak, junctioned -> $want"
                }
            } else {
                if ($DryRun) {
                    Write-Plan "would replace empty dir $($j.Link) with junction -> $want"
                } else {
                    Remove-Item -LiteralPath $j.Link -Force
                    New-Junction $j.Link $want
                    Write-Do "$($j.Name) -> $want"
                }
            }
        }
    } else {
        if ($DryRun) { Write-Plan "would junction $($j.Name) -> $want"; continue }
        New-Junction $j.Link $want
        Write-Do "$($j.Name) -> $want"
    }
}

# =============================================================================
# Environment
# =============================================================================

Write-Head 'Environment (User scope)'

foreach ($name in $EnvVars.Keys) {
    $want = $EnvVars[$name]
    $cur  = [Environment]::GetEnvironmentVariable($name, 'User')
    if ($cur -eq $want) { Write-Skip "$name = $want"; continue }
    if ($DryRun) {
        Write-Plan "would set $name = $want$(if ($cur) { "  (was: $cur)" })"
        continue
    }
    [Environment]::SetEnvironmentVariable($name, $want, 'User')
    Set-Item "Env:$name" $want   # so later steps in THIS run see it
    Write-Do "$name = $want"
}

# Old bootstrap.bat set these two at Machine scope behind a UAC prompt. If a
# stale Machine value is ever present it silently wins over ours for new
# processes, so surface it rather than fight it.
foreach ($name in @('KOMOREBI_CONFIG_HOME', 'WHKD_CONFIG_HOME')) {
    $m = [Environment]::GetEnvironmentVariable($name, 'Machine')
    if ($m) { Write-Warn "$name is also set at Machine scope ($m); remove it as admin" }
}

# =============================================================================
# PowerShell profile stubs
# =============================================================================

Write-Head 'PowerShell profile'

$stubBody = @"
# Managed by dotfiles ($Repo). Do not edit - edit the repo file instead.
`$DotfilesRoot = '$Repo'
. "`$DotfilesRoot\powershell\profile.ps1"
"@

foreach ($p in $ProfileStubs) {
    $parent = Split-Path -Parent $p
    $cur    = Get-TextOrNull $p

    if (Test-FileHasContent $p $stubBody) { Write-Skip $p; continue }

    if ($DryRun) {
        $what = if (Test-IsReparsePoint $p) { 'link' }
                elseif ($null -ne $cur)     { 'existing file' }
                else                        { 'nothing' }
        Write-Plan "would write stub to $p (currently: $what)"
        continue
    }

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # If a hardlink from the old bootstrap is still here, deleting this entry
    # only drops one of the two directory entries; the repo file is untouched.
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    Set-Content -LiteralPath $p -Value $stubBody -Encoding utf8
    Write-Do "stub -> $p"
}

# =============================================================================
# Claude Code settings
# =============================================================================
#
# skills/, agents/ and commands/ are junctioned in step 3 - anything written
# there lands in the repo with no further thought. settings.json cannot be:
# junctions are directory-only, and file symlinks need Developer Mode, which
# is off on this machine.
#
# The repo's two other loose-file cases dodge that with a generated stub that
# points back at the repo ($PROFILE dot-sources it, ~/.gitconfig includes it).
# settings.json has no include mechanism, so copying is the only option left.
#
# One direction only, repo -> home, and never over a newer home copy: Claude
# Code rewrites settings.json whenever a setting changes in the TUI, and
# clobbering that would throw the change away silently.

Write-Head 'Claude Code settings'

$ClaudeSrc = "$Repo\.claude\settings.json"
$ClaudeDst = "$Target\.claude\settings.json"

if (-not (Test-Path -LiteralPath $ClaudeSrc)) {
    Write-Warn "no tracked settings.json at $ClaudeSrc"
} else {
    $srcText = Get-TextOrNull $ClaudeSrc
    $dstText = Get-TextOrNull $ClaudeDst

    if (Test-FileHasContent $ClaudeDst $srcText) {
        Write-Skip $ClaudeDst
    } elseif ($null -ne $dstText -and
              (Get-Item -LiteralPath $ClaudeDst).LastWriteTimeUtc -gt
              (Get-Item -LiteralPath $ClaudeSrc).LastWriteTimeUtc) {
        # Changed in the TUI since the repo copy was last touched. Their edit
        # wins; pulling it back into the repo is a decision for them to make.
        Write-Warn "$ClaudeDst is newer than the repo copy - not overwriting"
        Write-Host '    Keep it by copying it into the repo:' -ForegroundColor DarkGray
        Write-Host "    Copy-Item '$ClaudeDst' '$ClaudeSrc'" -ForegroundColor DarkGray
    } elseif ($DryRun) {
        Write-Plan "would copy settings.json -> $ClaudeDst"
    } else {
        $parent = Split-Path -Parent $ClaudeDst
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $ClaudeSrc -Destination $ClaudeDst -Force
        Write-Do "settings.json -> $ClaudeDst"
    }
}

# =============================================================================
# Windows Terminal font
# =============================================================================
#
# A JSON patch, not a link. settings.json is a loose file (so no junction),
# Developer Mode is off (so no symlink), and Windows Terminal rewrites the
# file whenever a setting changes in its UI - a link would be fighting it even
# if one were possible. So: read, set one key, write back only if it differs.
#
# font.face goes on profiles.defaults so it covers every profile, including
# ones added later. A per-profile face would still win over it, which is the
# intended precedence.

Write-Head 'Windows Terminal font'

# Patches one settings.json in place. Returns nothing; reports its own result.
function Set-TerminalFont([string]$Path, [string]$Face) {
    $raw = Get-TextOrNull $Path
    if ($null -eq $raw) { Write-Warn "could not read $Path"; return }

    # Windows Terminal permits // and /* */ comments; PS 5.1's
    # ConvertFrom-Json rejects them outright. Stripping them first is not
    # safe either - it would cut into any string containing a // , such as a
    # URL or a UNC path. Refuse and say so rather than mangle the file.
    if ($raw -match '(?m)^\s*(//|/\*)') {
        Write-Warn "$Path has comments; PS 5.1 cannot parse it - not editing"
        Write-Host "    Set profiles.defaults.font.face to `"$Face`" by hand." -ForegroundColor DarkGray
        return
    }

    try {
        $json = $raw | ConvertFrom-Json
    } catch {
        Write-Warn "$Path is not valid JSON - not editing: $($_.Exception.Message)"
        return
    }

    if (-not $json.PSObject.Properties['profiles']) {
        $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{})
    }
    # The pre-1.0 schema had profiles as a bare array with no defaults block.
    # Nothing sensible to patch there, and guessing would rewrite the lot.
    if ($json.profiles -is [array]) {
        Write-Warn "$Path uses the legacy array schema for profiles - not editing"
        return
    }
    if (-not $json.profiles.PSObject.Properties['defaults']) {
        $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{})
    }
    if (-not $json.profiles.defaults.PSObject.Properties['font']) {
        $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{})
    }

    $font = $json.profiles.defaults.font
    if ($font.PSObject.Properties['face'] -and $font.face -eq $Face) {
        Write-Skip "$Path (font.face = $Face)"
        return
    }

    if ($DryRun) {
        $was = if ($font.PSObject.Properties['face']) { $font.face } else { '<unset>' }
        Write-Plan "would set font.face = $Face in $Path (was: $was)"
        return
    }

    if ($font.PSObject.Properties['face']) {
        $font.face = $Face
    } else {
        $font | Add-Member -NotePropertyName face -NotePropertyValue $Face
    }

    # ConvertTo-Json reformats the entire file, so keep the original once.
    $bak = "$Path.pre-dotfiles"
    if (-not (Test-Path -LiteralPath $bak)) {
        Copy-Item -LiteralPath $Path -Destination $bak
        Write-Do "backed up $Path -> $(Split-Path -Leaf $bak)"
    }

    # -Depth is NOT optional: PS 5.1 defaults to 2 and silently renders
    # anything deeper as the literal string "System.Object[]", which would
    # destroy the profile list and every colour scheme in the file.
    Set-Content -LiteralPath $Path -Value ($json | ConvertTo-Json -Depth 100) -Encoding utf8
    Write-Do "font.face = $Face -> $Path"
}

$terminalFound = @($TerminalSettings | Where-Object { Test-Path -LiteralPath $_ })

if (-not $terminalFound) {
    Write-Skip 'no Windows Terminal settings.json found'
} else {
    foreach ($s in $terminalFound) { Set-TerminalFont $s $TerminalFont }
}

# =============================================================================
# PowerShell modules
# =============================================================================

Write-Head 'PowerShell modules'

# These used to be installed from inside the profile, costing two
# Get-Module -ListAvailable scans on every single shell start. They belong here.
foreach ($m in $PSModules) {
    if (Get-Module -ListAvailable -Name $m) { Write-Skip $m; continue }
    if ($DryRun) { Write-Plan "would install module $m"; continue }
    try {
        Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Do "installed module $m"
    } catch {
        Write-Warn "could not install module ${m}: $($_.Exception.Message)"
    }
}

# =============================================================================
# komorebi application-specific configuration
# =============================================================================

Write-Head 'komorebi ASC'

# applications.json is upstream data (62 KB, 3263 lines) that used to be
# vendored into this repo. komorebi regenerates it on demand, so it is
# gitignored and fetched here instead.
$asc = "$Repo\komorebi\applications.json"
if (Test-Path -LiteralPath $asc) {
    Write-Skip 'applications.json present'
} elseif (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
    Write-Warn 'komorebic not on PATH - cannot fetch applications.json'
} elseif ($DryRun) {
    Write-Plan 'would run: komorebic fetch-app-specific-configuration'
} else {
    komorebic fetch-app-specific-configuration
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $asc)) {
        Write-Do 'fetched applications.json'
    } else {
        Write-Warn 'komorebic fetch-app-specific-configuration did not produce applications.json'
    }
}

# =============================================================================
# MSVC build tools
# =============================================================================
#
# The one step that elevates, and the one package that does not come from
# scoop. rustup defaults to the x86_64-pc-windows-msvc target, which links
# through link.exe; without the C++ toolset every cargo build dies with
# "linker `link.exe` not found". Crates that compile C - rusqlite's `bundled`
# feature, say - need cl.exe on top of that.
#
# Not in packages.tsv because scoop cannot deliver it. main/windows-sdk-
# buildtools is appx and signing tooling only (makeappx, signtool, rc) with no
# compiler, no linker and no libs; nothing in main or extras carries the
# toolset. Microsoft ships no unprivileged installer either, so this is an
# elevated winget call or nothing.
#
# Last on purpose: it is interactive and slow, so everything that can be done
# unattended is already done by the time it asks.

Write-Head 'MSVC build tools'

# Two different operations, picked on what is already on the machine.
#
# NOTHING INSTALLED -> winget install. --override replaces the installer's
# default arguments wholesale, so the workload has to be named here; a bare
# install lays down Build Tools with no C++ in it. --includeRecommended is
# what pulls the Windows SDK alongside the compiler.
#
# AN INSTALL WITHOUT THE C++ WORKLOAD -> vs_installer modify. This is the case
# that cost an afternoon: winget sees the package present, reports it
# installed, declines to do anything, and cargo still cannot link. `winget
# install` cannot add a workload to an existing Visual Studio; only the
# installer's own `modify` verb can.
#
# Both are ONE STRING, not an array. Start-Process joins an array with spaces
# without re-quoting elements that contain spaces, so the --override value
# would reach winget as five separate arguments - --override swallowing
# --quiet, with --wait and --add left over as unknown top-level flags. winget
# answers that with 0x8A150002 (invalid command line) AFTER the UAC prompt has
# been accepted, so it reads like a failed install rather than one that never
# started. A single pre-quoted string is passed through verbatim.
# The workload selection itself is the only part the two share.
$MsvcWorkload = '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'

# Path 1, the bootstrapper. winget downloads vs_BuildTools.exe and passes the
# --override string to it. --wait is valid HERE, and only here.
$MsvcWingetCmd = 'install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget ' +
                 '--accept-package-agreements --accept-source-agreements ' +
                 "--override `"--quiet --wait --norestart $MsvcWorkload`""

# Path 2, vs_installer.exe (which re-execs as setup.exe). A DIFFERENT binary
# with a DIFFERENT command line, despite the shared vocabulary: it rejects
# --wait outright, exiting 87 (ERROR_INVALID_PARAMETER) with a usage dump.
#
# --passive rather than --quiet because this one shows no progress at all
# otherwise, and the download runs to several GB. It still needs no
# interaction, so -Yes stays unattended.
function Get-MsvcModifyCmd([string]$InstallPath) {
    return "modify --installPath `"$InstallPath`" $MsvcWorkload --passive --norestart"
}

# vs_installer.exe hands the real work to a child process and returns almost
# at once, so Start-Process -Wait on it proves nothing - the probe that
# follows would run against a half-finished install and report failure.
# Wait for the installer's own processes to go away instead.
function Wait-ForVsInstaller([int]$TimeoutMinutes = 90) {
    $names    = @('setup', 'vs_installer', 'vs_installershell', 'vs_installerservice')
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    # The child may not have started yet when the parent returns; without this
    # the first poll sees nothing running and declares the install finished.
    Start-Sleep -Seconds 10

    while ((Get-Date) -lt $deadline) {
        if (-not @(Get-Process -Name $names -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

# Printed whenever the install is declined or fails. Derived from the same
# strings the script runs, never written out by hand - the previous version
# kept two copies and they disagreed, so the hint worked while the script's
# own invocation did not.
function Write-MsvcManualHint([string]$Exe, [string]$Arguments) {
    Write-Host '    Run this in an elevated terminal when you want it:' -ForegroundColor DarkGray
    Write-Host "    & '$Exe' $Arguments" -ForegroundColor DarkGray
}

# Runs one of the two elevated installers and reports on the result. Success
# is judged by re-probing vswhere, not by the exit code: the failure mode that
# started all this was an installer exiting 0 having installed no C++ at all.
function Invoke-MsvcInstaller([string]$Exe, [string]$Arguments, [bool]$IsVsInstaller) {
    Write-Host '  Waiting for the installer (this takes several minutes)...' -ForegroundColor DarkGray
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $Arguments `
                           -Verb RunAs -Wait -PassThru -ErrorAction Stop
    } catch {
        # Declining the UAC dialog is by far the commonest cause.
        Write-Warn "could not start the installer: $($_.Exception.Message)"
        Write-MsvcManualHint $Exe $Arguments
        return
    }

    # Exit 87 is ERROR_INVALID_PARAMETER - the installer rejected the command
    # line and did nothing. Worth naming, because it looks like a failed
    # install rather than one that never began.
    if ($p.ExitCode -eq 87) {
        Write-Warn 'the installer rejected its command line (exit 87) - nothing was installed'
        Write-MsvcManualHint $Exe $Arguments
        return
    }

    if ($IsVsInstaller -and -not (Wait-ForVsInstaller)) {
        Write-Warn 'timed out waiting for the Visual Studio installer to finish'
    }

    if (Get-MsvcInstallPath) {
        Write-Do "installed the MSVC C++ toolset -> $(Get-MsvcInstallPath)"
        # 3010 is "success, reboot required" and is normal for this package.
        if ($p.ExitCode -eq 3010) { Write-Warn 'installer asked for a reboot' }
        return
    }

    if ($p.ExitCode -eq 0) {
        Write-Warn 'installer reported success but the C++ workload is still missing'
    } else {
        # winget's codes are 0x8A15xxxx and surface here as large negatives;
        # print hex too, since that is the only form its error table lists.
        Write-Warn ("installer exited with code {0} (0x{1:X8})" -f $p.ExitCode, $p.ExitCode)
    }
    Write-MsvcManualHint $Exe $Arguments
}

$msvc = Get-MsvcInstallPath
$vs   = Get-VsInstallPath

# An existing install needs vs_installer.exe, which sits beside vswhere.exe.
$VsInstallerExe = if (${env:ProgramFiles(x86)}) {
    Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vs_installer.exe'
} else { $null }

$useModify = [bool]($vs -and $VsInstallerExe -and (Test-Path -LiteralPath $VsInstallerExe))

if ($msvc) {
    Write-Skip "MSVC C++ toolset: $msvc"
} elseif ($SkipMsvc) {
    Write-Skip 'MSVC C++ toolset absent (-SkipMsvc)'
} elseif ($DryRun) {
    if ($useModify) {
        Write-Plan "would ask whether to add the C++ workload to $vs (elevates)"
    } else {
        Write-Plan 'would ask whether to install the MSVC C++ toolset (elevates)'
    }
} elseif (-not $useModify -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn 'MSVC C++ toolset not installed, and winget is not on PATH'
} else {
    Write-Host ''
    if ($useModify) {
        Write-Host "  Visual Studio is installed at" -ForegroundColor Yellow
        Write-Host "    $vs" -ForegroundColor Yellow
        Write-Host '  but WITHOUT the C++ workload, so there is no link.exe and cargo' -ForegroundColor Yellow
        Write-Host '  builds for the default x86_64-pc-windows-msvc target fail at the' -ForegroundColor Yellow
        Write-Host '  link step. This adds the workload to that existing install.' -ForegroundColor Yellow
    } else {
        Write-Host '  The MSVC C++ toolset is not installed. Without it, cargo builds for' -ForegroundColor Yellow
        Write-Host '  the default x86_64-pc-windows-msvc target fail at the link step.' -ForegroundColor Yellow
    }
    Write-Host '  This needs administrator rights (one UAC prompt) and downloads' -ForegroundColor Yellow
    Write-Host '  several GB. Everything else in this run is already done.' -ForegroundColor Yellow
    Write-Host ''

    $question = if ($useModify) { 'Add the C++ workload to the existing install now?' }
                else            { 'Install Visual Studio 2022 Build Tools now?' }

    if (Read-YesNo $question) {
        if ($useModify) {
            Invoke-MsvcInstaller $VsInstallerExe (Get-MsvcModifyCmd $vs) $true
        } else {
            # Resolve the shim to a full path: the elevated process gets a
            # different PATH and would not otherwise find a scoop shim.
            Invoke-MsvcInstaller (Get-Command winget).Source $MsvcWingetCmd $false
        }
    } else {
        Write-Warn 'MSVC C++ toolset not installed - cargo builds will fail to link'
        if ($useModify) {
            Write-MsvcManualHint $VsInstallerExe (Get-MsvcModifyCmd $vs)
        } else {
            Write-MsvcManualHint 'winget' $MsvcWingetCmd
        }
    }
}

# =============================================================================
# komorebi autostart
# =============================================================================
#
# komorebic writes the shortcut itself - no registry Run key, no scheduled
# task, no admin. enable-autostart drops komorebi.lnk into shell:startup with
# the flags passed through, so --whkd --bar here is what gets baked into the
# shortcut's arguments.
#
# Interactive like step 8, and after it, because unlike MSVC this one is a
# matter of taste: plenty of reasons to run komorebi by hand instead.

Write-Head 'komorebi autostart'

$StartupDir   = [Environment]::GetFolderPath('Startup')
$AutostartLnk = Join-Path $StartupDir 'komorebi.lnk'
$AutostartCmd = 'komorebic enable-autostart --whkd --bar'

# Returns the .lnk files in shell:startup that launch komorebic but are NOT
# the one komorebic manages. A hand-made shortcut next to komorebi.lnk starts
# a second komorebi at login, which looks like komorebi crashing on startup.
function Get-StrayKomorebiShortcut {
    if (-not (Test-Path -LiteralPath $StartupDir)) { return @() }
    $shell = New-Object -ComObject WScript.Shell
    return @(Get-ChildItem -LiteralPath $StartupDir -Filter *.lnk -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'komorebi.lnk' } |
        Where-Object { $shell.CreateShortcut($_.FullName).TargetPath -match 'komorebic?\.exe$' })
}

$HaveKomorebic = [bool](Get-Command komorebic -ErrorAction SilentlyContinue)

# komorebic ends enable-autostart with a note: a komorebi.json referencing
# $KOMOREBI_CONFIG_HOME needs that variable persisted in User Variables. The
# login shortcut is launched by Explorer, which only ever sees the persisted
# user environment - never a value exported into some shell, and never one
# this script set for its own process alone.
#
# komorebi.json does reference it (app_specific_configuration_path), and step
# 4 already persists it, so this normally passes untouched. Checked rather
# than assumed: the coupling between steps 4 and 9 is otherwise invisible, and
# the failure mode is silent - komorebi just quietly uses stock app rules.
if ($HaveKomorebic) {
    foreach ($n in @('KOMOREBI_CONFIG_HOME', 'WHKD_CONFIG_HOME')) {
        $want = $EnvVars[$n]
        if ([Environment]::GetEnvironmentVariable($n, 'User') -eq $want) { continue }
        if ($DryRun) {
            Write-Plan "would persist $n = $want at User scope (the login shortcut needs it)"
            continue
        }
        [Environment]::SetEnvironmentVariable($n, $want, 'User')
        Set-Item "Env:$n" $want
        Write-Do "persisted $n = $want at User scope for the autostart shortcut"
    }
}

if (-not $HaveKomorebic) {
    Write-Warn 'komorebic not on PATH - cannot configure autostart'
} elseif ($DryRun) {
    if (Test-Path -LiteralPath $AutostartLnk) {
        Write-Skip "autostart shortcut present: $AutostartLnk"
    } else {
        Write-Plan 'would ask whether to enable komorebi autostart'
    }
    foreach ($s in Get-StrayKomorebiShortcut) {
        Write-Plan "would move aside duplicate startup shortcut $($s.Name)"
    }
} else {
    if (Test-Path -LiteralPath $AutostartLnk) {
        Write-Skip "autostart shortcut present: $AutostartLnk"
        $enabled = $true
    } else {
        Write-Host ''
        Write-Host '  komorebi is not set to start at login. Enabling it writes' -ForegroundColor Yellow
        Write-Host "  komorebi.lnk to shell:startup, running: komorebic start --whkd --bar" -ForegroundColor Yellow
        Write-Host ''

        if (Read-YesNo 'Enable komorebi autostart now?') {
            komorebic enable-autostart --whkd --bar
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $AutostartLnk)) {
                Write-Do "autostart enabled -> $AutostartLnk"
                $enabled = $true
            } else {
                Write-Warn 'komorebic enable-autostart did not produce komorebi.lnk'
                Write-Host "    Run this when you want it:" -ForegroundColor DarkGray
                Write-Host "    $AutostartCmd" -ForegroundColor DarkGray
                $enabled = $false
            }
        } else {
            Write-Warn 'komorebi will not start at login'
            Write-Host '    Run this when you want it:' -ForegroundColor DarkGray
            Write-Host "    $AutostartCmd" -ForegroundColor DarkGray
            $enabled = $false
        }
    }

    # Only a problem once komorebi.lnk exists; before that a hand-made shortcut
    # is the only thing starting komorebi and must not be touched. Renamed, not
    # deleted - same .pre-dotfiles idiom as the config backups above.
    if ($enabled) {
        foreach ($s in Get-StrayKomorebiShortcut) {
            $bak = "$($s.FullName).pre-dotfiles"
            Move-Item -LiteralPath $s.FullName -Destination $bak -Force
            Write-Do "moved duplicate startup shortcut $($s.Name) -> $(Split-Path -Leaf $bak)"
        }
    }
}

# =============================================================================

$verb = if ($DryRun) { 'planned' } else { 'applied' }
Write-Host "`n$($script:Changed) $verb, $($script:Skipped) already correct, $($script:Warned) warning(s)." -ForegroundColor Yellow
if ($DryRun) {
    Write-Host "Dry run - nothing was changed. Re-run without -DryRun to apply.`n" -ForegroundColor Yellow
} else {
    Write-Host "Open a new terminal for environment changes to take effect.`n" -ForegroundColor Yellow
}
