<#
.SYNOPSIS
    Provision this machine from the dotfiles repo. Windows side.

.DESCRIPTION
    Replaces the old bootstrap.bat. Three differences worth knowing:

    1. No admin, ever. Unprivileged symlinks need Developer Mode, which is not
       enabled here and may be policy-blocked. So: directory *junctions* (which
       never need privileges) for config directories, and environment variables
       for everything else. Nothing uses mklink /H - hardlinks silently break
       when an editor saves via write-temp-then-rename, which is how the
       PowerShell profile drifted out of sync before.

    2. Env-var-first. starship, komorebi and whkd all accept a config path
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

.EXAMPLE
    .\bootstrap.ps1 -DryRun
    .\bootstrap.ps1
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipPackages
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repo   = $PSScriptRoot
$Target = $env:USERPROFILE
$Xdg    = Join-Path $Target '.config'

$script:Changed = 0
$script:Skipped = 0
$script:Warned  = 0

function Write-Head($t) { Write-Host "`n$t" -ForegroundColor Green }
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
# fine here: loose FILES under .config/ (starship.toml) are not linked at all,
# they are pointed at by an environment variable instead. See $EnvVars.
$LinuxOnlyConfig = @('i3', 'i3status', 'sway', 'rofi')

$Junctions = @(
    Get-ChildItem -LiteralPath "$Repo\.config" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $LinuxOnlyConfig -notcontains $_.Name } |
        ForEach-Object {
            @{ Name = $_.Name; Link = "$Xdg\$($_.Name)"; Target = $_.FullName }
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
    'STARSHIP_CONFIG'      = "$Repo\.config\starship.toml"
    'KOMOREBI_CONFIG_HOME' = "$Repo\komorebi"
    'WHKD_CONFIG_HOME'     = "$Repo\komorebi"
}

# Directories that must exist as REAL directories, not junctions. This is the
# whole trick that keeps tool-written state out of the repo: $XDG_CONFIG_HOME
# itself is real, and only the per-tool subdirectories below it are junctions.
# Junction the parent instead and every tool that writes to ~/.config dirties
# your git tree - which is exactly how startup.log, .nvimlog, scoop/config.json
# and uv-receipt.json ended up tracked.
$RealDirs = @(
    $Xdg
    "$Target\.local\share"
    "$Target\.local\state"
    "$Target\.cache"
)

# PowerShell profile stubs. CurrentUserCurrentHost matches what was linked
# before. The PowerShell 7 path is written too, harmlessly, so the profile is
# already in place if pwsh is ever installed (it is not, today).
$ProfileStubs = @(
    "$Target\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    "$Target\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)

$PSModules = @('PSFzf', 'posh-git')

# =============================================================================
# Helpers
# =============================================================================

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

# =============================================================================
# 0. Preconditions
# =============================================================================

Write-Head '[0/7] Preconditions'

if (-not (Test-Path -LiteralPath "$Repo\install\packages.tsv")) {
    throw "packages.tsv not found. Is `$PSScriptRoot ($Repo) the repo root?"
}
Write-Skip "repo root: $Repo"
Write-Skip "deploy target: $Target"

if ($Repo -like "$Target\*" -and $Repo -notlike "$Target\home\*") {
    Write-Warn "repo lives under the deploy target; junction loops are possible"
}

# ~/.gitconfig shadows $XDG_CONFIG_HOME/git/config unconditionally, so it has to
# go or the tracked config is silently ignored. Move rather than delete: the
# live copy carries a credential-helper path that is not in the repo.
$LegacyGitconfig = if ($env:HOME) { Join-Path $env:HOME '.gitconfig' } else { $null }
if ($LegacyGitconfig -and (Test-Path -LiteralPath $LegacyGitconfig)) {
    $bak = "$LegacyGitconfig.pre-dotfiles"
    if ($DryRun) {
        Write-Plan "would move $LegacyGitconfig -> $bak (it shadows the XDG git config)"
    } else {
        Move-Item -LiteralPath $LegacyGitconfig -Destination $bak -Force
        Write-Do "moved $LegacyGitconfig -> $bak"
    }
}

# =============================================================================
# 1. Packages
# =============================================================================

Write-Head '[1/7] Packages (scoop)'

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

    $buckets = @($rows | ForEach-Object { ($_.Scoop -split '/')[0] } | Sort-Object -Unique)
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
        $short = ($r.Scoop -split '/')[-1]
        if ($installed -contains $short) { Write-Skip "$($r.Name)"; continue }
        if ($DryRun) { Write-Plan "would install $($r.Scoop)"; continue }
        scoop install $r.Scoop
        # Deliberately non-fatal: one unavailable manifest must not abort the
        # whole bootstrap. bootstrap.bat pretended to be fatal here but its
        # helper always returned 0, so all 22 error handlers were dead code.
        if ($LASTEXITCODE -ne 0) { Write-Warn "could not install $($r.Scoop)"; continue }
        Write-Do "installed $($r.Scoop)"
    }
}

# =============================================================================
# 2. Real directories
# =============================================================================

Write-Head '[2/7] Base directories'

foreach ($d in $RealDirs) {
    if (Test-IsReparsePoint $d) {
        Write-Warn "$d is a junction; it must be a real directory - not touching it"
        continue
    }
    if (Test-Path -LiteralPath $d) { Write-Skip $d; continue }
    if ($DryRun) { Write-Plan "would create $d"; continue }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    Write-Do "created $d"
}

# =============================================================================
# 3. Config junctions
# =============================================================================

Write-Head '[3/7] Config junctions'

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
# 4. Environment
# =============================================================================

Write-Head '[4/7] Environment (User scope)'

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
# 5. PowerShell profile stubs
# =============================================================================

Write-Head '[5/7] PowerShell profile'

$stubBody = @"
# Managed by dotfiles ($Repo). Do not edit - edit the repo file instead.
`$DotfilesRoot = '$Repo'
. "`$DotfilesRoot\powershell\profile.ps1"
"@

foreach ($p in $ProfileStubs) {
    $parent = Split-Path -Parent $p
    $cur    = if (Test-Path -LiteralPath $p) { (Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue) } else { $null }

    if ($null -ne $cur -and $cur.Trim() -eq $stubBody.Trim()) { Write-Skip $p; continue }

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
# 6. PowerShell modules
# =============================================================================

Write-Head '[6/7] PowerShell modules'

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
# 7. komorebi application-specific configuration
# =============================================================================

Write-Head '[7/7] komorebi ASC'

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

$verb = if ($DryRun) { 'planned' } else { 'applied' }
Write-Host "`n$($script:Changed) $verb, $($script:Skipped) already correct, $($script:Warned) warning(s)." -ForegroundColor Yellow
if ($DryRun) {
    Write-Host "Dry run - nothing was changed. Re-run without -DryRun to apply.`n" -ForegroundColor Yellow
} else {
    Write-Host "Open a new terminal for environment changes to take effect.`n" -ForegroundColor Yellow
}
