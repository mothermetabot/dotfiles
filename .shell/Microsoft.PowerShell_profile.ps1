# --- ll: GNU ls-style long listing ---
function ll {
    # Compact "long" listing: size, date, name (no perms/links/owner/group)
    & dir -a -h --time-style=+"%Y-%m-%d %H:%M" --format=long-iso @args
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
