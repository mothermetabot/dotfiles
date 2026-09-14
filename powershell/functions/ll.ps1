# ll: GNU ls-style long listing.
function ll {
    param(
        [string]$Path = '.',
        [switch]$Force
    )

    $dirParams = @{ Path = $Path }
    if ($Force) { $dirParams.Force = $true }

    Get-ChildItem @dirParams |
        Select-Object `
            @{ Name = 'Size'; Expression = {
                if ($_.PSIsContainer) { '<DIR>' }
                else { '{0,10:N0}' -f $_.Length }
            }},
            @{ Name = 'LastWriteTime'; Expression = { $_.LastWriteTime } },
            @{ Name = 'Name';          Expression = { $_.Name } }
}
