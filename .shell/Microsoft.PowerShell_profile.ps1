# --- ll: GNU ls-style long listing ---
function ll {
    param(
        [string]$Path = ".",
        [switch]$Force
    )

    $dirParams = @{
        Path = $Path
    }

    if ($Force) {
        $dirParams.Force = $true
    }

    dir @dirParams |
        Select-Object `
            @{ Name = 'Size'; Expression = {
                if ($_.PSIsContainer) { '<DIR>' }
                else { '{0,10:N0}' -f $_.Length }
            }},
            @{ Name = 'LastWriteTime'; Expression = { $_.LastWriteTime } },
            @{ Name = 'Name'; Expression = { $_.Name } }
}

# GIT quality of life functions
# --- gg: interactive git helper (branch, changes, stash, worktree, PR, log, undo) ---
# The implementation lives in an optional PowerShell module rather than in
# this profile. Source and tests: %USERPROFILE%\home\src\gg (see its README).
# The module exports gg, gl, gs and ga and registers their argument completers
# on import; all __gg_* helpers stay private to it. The module is optional: if
# the repository is absent this block does nothing and the profile is otherwise
# unaffected, so gg/gl/gs/ga are simply undefined.
$ggModulePath = Join-Path $env:USERPROFILE 'home\src\gg\GG.psd1'
if (Test-Path -LiteralPath $ggModulePath) {
    Import-Module $ggModulePath
}
Remove-Variable ggModulePath -ErrorAction SilentlyContinue

function envup {
    param(
        [Parameter(Position=0)]
        [string]$Name = ".env"
    )

    # 1. Check if the file exists
    if (-not (Test-Path $Name)) {
        Write-Error "Environment file '$Name' not found."
        return
    }

    Write-Host "Loading environment variables from: $Name" -ForegroundColor Cyan

    # 2. Read the file, ignore empty lines and comments
    Get-Content $Name | Where-Object { $_ -and -not $_.StartsWith("#") } | ForEach-Object {
        # Split by the first '=' found
        if ($_ -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            
            # Remove optional surrounding quotes from the value
            $value = $value -replace '^["'']|["'']$', ''

            # 3. Set the variable in the "Process" scope (current session only)
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
            Write-Host "  Set: $key" -ForegroundColor Gray
        }
    }
    
    Write-Host "Successfully loaded." -ForegroundColor Green
}

Invoke-Expression (&starship init powershell)
If (Test-Path Alias:rm) {Remove-Item Alias:rm}
If (Test-Path Alias:ls) {Remove-Item Alias:ls}
If (Test-Path Alias:gl) {Remove-Item Alias:gl -Force}

# =============================================================================
#
# Utility functions for zoxide.
#

# Call zoxide binary, returning the output as UTF-8.
function global:__zoxide_bin {
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new()
        $result = zoxide @args
        return $result
    } finally {
        [Console]::OutputEncoding = $encoding
    }
}

# pwd based on zoxide's format.
function global:__zoxide_pwd {
    $cwd = Get-Location
    if ($cwd.Provider.Name -eq "FileSystem") {
        $cwd.ProviderPath
    }
}

# cd + custom logic based on the value of _ZO_ECHO.
function global:__zoxide_cd($dir, $literal) {
    $dir = if ($literal) {
        Set-Location -LiteralPath $dir -Passthru -ErrorAction Stop
    } else {
        if ($dir -eq '-' -and ($PSVersionTable.PSVersion -lt 6.1)) {
            Write-Error "cd - is not supported below PowerShell 6.1. Please upgrade your version of PowerShell."
        }
        elseif ($dir -eq '+' -and ($PSVersionTable.PSVersion -lt 6.2)) {
            Write-Error "cd + is not supported below PowerShell 6.2. Please upgrade your version of PowerShell."
        }
        else {
            Set-Location -Path $dir -Passthru -ErrorAction Stop
        }
    }
}

# =============================================================================
#
# Hook configuration for zoxide.
#

# Hook to add new entries to the database.
$global:__zoxide_oldpwd = __zoxide_pwd
function global:__zoxide_hook {
    $result = __zoxide_pwd
    if ($result -ne $global:__zoxide_oldpwd) {
        if ($null -ne $result) {
            zoxide add "--" $result
        }
        $global:__zoxide_oldpwd = $result
    }
}

# Initialize hook.
$global:__zoxide_hooked = (Get-Variable __zoxide_hooked -ErrorAction Ignore -ValueOnly)
if ($global:__zoxide_hooked -ne 1) {
    $global:__zoxide_hooked = 1
    $global:__zoxide_prompt_old = $function:prompt

    function global:prompt {
        if ($null -ne $__zoxide_prompt_old) {
            & $__zoxide_prompt_old
        }
        $null = __zoxide_hook
    }
}

# =============================================================================
#
# When using zoxide with --no-cmd, alias these internal functions as desired.
#

# Jump to a directory using only keywords.
function global:__zoxide_z {
    if ($args.Length -eq 0) {
        __zoxide_cd ~ $true
    }
    elseif ($args.Length -eq 1 -and ($args[0] -eq '-' -or $args[0] -eq '+')) {
        __zoxide_cd $args[0] $false
    }
    elseif ($args.Length -eq 1 -and (Test-Path -PathType Container -LiteralPath $args[0])) {
        __zoxide_cd $args[0] $true
    }
    elseif ($args.Length -eq 1 -and (Test-Path -PathType Container -Path $args[0] )) {
        __zoxide_cd $args[0] $false
    }
    else {
        $result = __zoxide_pwd
        if ($null -ne $result) {
            $result = __zoxide_bin query --exclude $result "--" @args
        }
        else {
            $result = __zoxide_bin query "--" @args
        }
        if ($LASTEXITCODE -eq 0) {
            __zoxide_cd $result $true
        }
    }
}

# Jump to a directory using interactive search.
function global:__zoxide_zi {
    $result = __zoxide_bin query -i "--" @args
    if ($LASTEXITCODE -eq 0) {
        __zoxide_cd $result $true
    }
}

# =============================================================================
#
# Commands for zoxide. Disable these using --no-cmd.
#

Set-Alias -Name c -Value __zoxide_z -Option AllScope -Scope Global -Force
Set-Alias -Name ci -Value __zoxide_zi -Option AllScope -Scope Global -Force

# =============================================================================
#
# To initialize zoxide, add this to your configuration (find it by running
# `echo $profile` in PowerShell):
#
# Invoke-Expression (& { (zoxide init powershell | Out-String) })
#

# FUZZY find for command history
if (-not (Get-Module -ListAvailable -Name PSFzf)) {
    Install-Module -Name PSFzf -Scope CurrentUser
}
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordReverseHistory 'Ctrl+r'

if (-not (Get-Module -ListAvailable -Name posh-git)) {
      Install-Module posh-git -Scope CurrentUser -Force
  }
  Import-Module posh-git

# --- gp: fuzzy-find with paths (fd --type d) and cd to the selection ---
function cb {
    $selection =   fd --type d | fzf
    if (-not $selection) { return }  # cancelled with Esc/Ctrl+C

    Set-Location -LiteralPath $selection
}


# --- gn: fuzzy-find with nodes (files) and cd to the selection ---
function cl {
    $selection =    fzf 
    if (-not $selection) { return }  # cancelled with Esc/Ctrl+C

    Set-Location -LiteralPath (Split-Path -Parent $selection)
}

function n {
    nvim .
}

function fvim {
    $selection = rg --files --hidden --glob '!.git/*' | fzf

    if (-not $selection) { return }

    nvim $selection
}

function gvim {
    $selection = fzf `
        --ansi `
        --disabled `
        --prompt "grep> " `
        --with-shell "powershell.exe -NoProfile -Command" `
        --bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case --hidden --glob '!.git/*' {q}; if (`$LASTEXITCODE -eq 1) { exit 0 }" `
        --bind "result:transform-list-label:if (`$env:FZF_MATCH_COUNT -eq 0) { ' No matches ' } else { ' ' + `$env:FZF_MATCH_COUNT + ' matches ' }" `
        --delimiter ":"

    if (-not $selection) { return }

    if ($selection -match '^(.*):(\d+):(\d+):(.*)$') {
        $file = $matches[1]
        $line = $matches[2]
        $column = $matches[3]

        nvim "+call cursor($line,$column)" -- $file
    }
}

function dev {
    param(
        [Parameter(Position = 0)]
        [string] $Action
    )

    function Show-DevHelp {
        @"
Usage:
  dev on       Load the Visual Studio developer environment
  dev off      Unload it and restore the previous environment
  dev --help   Show this help
"@
    }

    # "dev" behaves like "dev --help", but isn't shown separately in help.
    if (-not $Action -or $Action -in @("--help", "-h", "help")) {
        Show-DevHelp
        return
    }

    switch ($Action.ToLowerInvariant()) {
        "on" {
            if ($script:DevEnvironmentActive) {
                Write-Host "Visual Studio developer environment is already loaded."
                return
            }

            $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

            if (-not (Test-Path $vswhere)) {
                Write-Error "Could not find vswhere.exe."
                return
            }

            $installPath = & $vswhere `
                -latest `
                -products * `
                -property installationPath

            if (-not $installPath) {
                Write-Error "Could not find a Visual Studio installation."
                return
            }

            $devShell = Join-Path `
                $installPath `
                "Common7\Tools\Launch-VsDevShell.ps1"

            if (-not (Test-Path $devShell)) {
                Write-Error "Could not find Launch-VsDevShell.ps1."
                return
            }

            # Save the environment before enabling the VS developer shell.
            $before = @{}

            Get-ChildItem Env: | ForEach-Object {
                $before[$_.Name] = $_.Value
            }

            try {
                & $devShell `
                    -SkipAutomaticLocation `
                    -Arch amd64 `
                    -HostArch amd64 `
                    | Out-Null
            }
            catch {
                Write-Error "Failed to load Visual Studio developer environment: $_"
                return
            }

            # Determine exactly what Visual Studio changed.
            $after = @{}

            Get-ChildItem Env: | ForEach-Object {
                $after[$_.Name] = $_.Value
            }

            $script:DevEnvironmentBackup = @{}

            $names = @($before.Keys) + @($after.Keys) |
                Sort-Object -Unique

            foreach ($name in $names) {
                $hadBefore = $before.ContainsKey($name)
                $hasAfter  = $after.ContainsKey($name)

                $oldValue = if ($hadBefore) { $before[$name] } else { $null }
                $newValue = if ($hasAfter)  { $after[$name] } else { $null }

                if (
                    $hadBefore -ne $hasAfter -or
                    $oldValue -ne $newValue
                ) {
                    $script:DevEnvironmentBackup[$name] = @{
                        Existed = $hadBefore
                        Value   = $oldValue
                    }
                }
            }

            $script:DevEnvironmentActive = $true

            Write-Host "Visual Studio developer environment loaded."
        }

        "off" {
            if (-not $script:DevEnvironmentActive) {
                Write-Host "Visual Studio developer environment is not loaded."
                return
            }

            foreach ($name in $script:DevEnvironmentBackup.Keys) {
                $original = $script:DevEnvironmentBackup[$name]

                if ($original.Existed) {
                    Set-Item "Env:$name" $original.Value
                }
                else {
                    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
                }
            }

            $script:DevEnvironmentBackup = $null
            $script:DevEnvironmentActive = $false

            Write-Host "Visual Studio developer environment unloaded."
        }

        default {
            Write-Error "Unknown command '$Action'."
            Show-DevHelp
        }
    }
}
