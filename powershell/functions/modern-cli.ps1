# cat -> bat, plus the listing helpers.
#
# Defined as functions rather than Set-Alias because aliases cannot carry
# default arguments. Each falls back to the PowerShell built-in when the tool
# is missing, so a machine that has not run bootstrap yet still works.
#
# eza was tried and dropped: the scoop build (GNU target, 0.23.5) HANGS on any
# directory listing on this machine - reproduced from PowerShell, cmd.exe and a
# redirected process, while `eza --version` returned fine. Aliasing `ls` to a
# binary that never returns is worse than the built-in.

if (Get-Command bat -ErrorAction SilentlyContinue) {
    # --paging=never keeps `cat` usable in pipelines rather than opening a
    # pager and blocking.
    function cat { bat --paging=never @args }
    # `batp` when you actually do want the pager.
    function batp { bat @args }
} else {
    function cat { Get-Content @args }
}

# GNU ls-style long listing, matching `ll` in .bashrc.
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

function la { ll -Force @args }
