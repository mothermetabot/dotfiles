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
