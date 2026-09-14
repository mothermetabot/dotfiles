# envup: load a .env file into the current process only.
function envup {
    param(
        [Parameter(Position = 0)]
        [string]$Name = '.env'
    )

    if (-not (Test-Path $Name)) {
        Write-Error "Environment file '$Name' not found."
        return
    }

    Write-Host "Loading environment variables from: $Name" -ForegroundColor Cyan

    Get-Content $Name |
        Where-Object { $_ -and -not $_.StartsWith('#') } |
        ForEach-Object {
            if ($_ -match '^([^=]+)=(.*)$') {
                $key   = $matches[1].Trim()
                $value = $matches[2].Trim() -replace '^["'']|["'']$', ''

                [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
                Write-Host "  Set: $key" -ForegroundColor Gray
            }
        }

    Write-Host 'Successfully loaded.' -ForegroundColor Green
}
