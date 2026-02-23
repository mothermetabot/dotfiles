# --- ll: GNU ls-style long listing ---
function ll {
    # Compact "long" listing: size, date, name (no perms/links/owner/group)
    & ls -afgHo 
}

# --- gl: pretty, minimal git log ---
function gl {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Branches
    )

    # If no branches are provided, default to the current branch (HEAD)
    $rev = if ($Branches -and $Branches.Count -gt 0) { $Branches } else { @("HEAD") }

    git --no-pager log `
        --graph `
        --decorate=short `
        --date=short `
        --pretty=format:"%C(auto)%h%d %s %C(black)%C(bold)%ad %C(blue)%an%Creset" `
        --max-count=30 `
        @rev
}
# --- autocomplete git branch names for: gl <branch...> ---
Register-ArgumentCompleter -CommandName gl -ParameterName Branches -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    # Only offer completions when we're inside a git repo
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }

    # List local + remote branches, strip prefixes, uniq, then filter by what user typed
    $branches =
        git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>$null |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -ne 'HEAD' } |
        Sort-Object -Unique

    foreach ($b in $branches) {
        if ($b -like "$wordToComplete*") {
            [System.Management.Automation.CompletionResult]::new($b, $b, 'ParameterValue', $b)
        }
    }
}

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
