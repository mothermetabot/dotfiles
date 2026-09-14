# dev: load and unload the Visual Studio developer environment in-place.
#
# Launch-VsDevShell mutates the current process environment with no way back,
# so `dev on` diffs the environment before and after and stores the delta,
# letting `dev off` restore it exactly.

function dev {
    param(
        [Parameter(Position = 0)]
        [string]$Action
    )

    function Show-DevHelp {
        @"
Usage:
  dev on       Load the Visual Studio developer environment
  dev off      Unload it and restore the previous environment
  dev --help   Show this help
"@
    }

    if (-not $Action -or $Action -in @('--help', '-h', 'help')) {
        Show-DevHelp
        return
    }

    switch ($Action.ToLowerInvariant()) {
        'on' {
            if ($script:DevEnvironmentActive) {
                Write-Host 'Visual Studio developer environment is already loaded.'
                return
            }

            $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
            if (-not (Test-Path $vswhere)) {
                Write-Error 'Could not find vswhere.exe.'
                return
            }

            $installPath = & $vswhere -latest -products * -property installationPath
            if (-not $installPath) {
                Write-Error 'Could not find a Visual Studio installation.'
                return
            }

            $devShell = Join-Path $installPath 'Common7\Tools\Launch-VsDevShell.ps1'
            if (-not (Test-Path $devShell)) {
                Write-Error 'Could not find Launch-VsDevShell.ps1.'
                return
            }

            # Snapshot before.
            $before = @{}
            Get-ChildItem Env: | ForEach-Object { $before[$_.Name] = $_.Value }

            try {
                & $devShell -SkipAutomaticLocation -Arch amd64 -HostArch amd64 | Out-Null
            }
            catch {
                Write-Error "Failed to load Visual Studio developer environment: $_"
                return
            }

            # Snapshot after, and keep only what actually changed.
            $after = @{}
            Get-ChildItem Env: | ForEach-Object { $after[$_.Name] = $_.Value }

            $script:DevEnvironmentBackup = @{}
            $names = @($before.Keys) + @($after.Keys) | Sort-Object -Unique

            foreach ($name in $names) {
                $hadBefore = $before.ContainsKey($name)
                $hasAfter  = $after.ContainsKey($name)
                $oldValue  = if ($hadBefore) { $before[$name] } else { $null }
                $newValue  = if ($hasAfter)  { $after[$name]  } else { $null }

                if ($hadBefore -ne $hasAfter -or $oldValue -ne $newValue) {
                    $script:DevEnvironmentBackup[$name] = @{
                        Existed = $hadBefore
                        Value   = $oldValue
                    }
                }
            }

            $script:DevEnvironmentActive = $true
            Write-Host 'Visual Studio developer environment loaded.'
        }

        'off' {
            if (-not $script:DevEnvironmentActive) {
                Write-Host 'Visual Studio developer environment is not loaded.'
                return
            }

            foreach ($name in $script:DevEnvironmentBackup.Keys) {
                $original = $script:DevEnvironmentBackup[$name]
                if ($original.Existed) {
                    Set-Item "Env:$name" $original.Value
                } else {
                    Remove-Item "Env:$name" -ErrorAction SilentlyContinue
                }
            }

            $script:DevEnvironmentBackup = $null
            $script:DevEnvironmentActive = $false
            Write-Host 'Visual Studio developer environment unloaded.'
        }

        default {
            Write-Error "Unknown command '$Action'."
            Show-DevHelp
        }
    }
}
