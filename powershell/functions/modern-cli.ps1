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

# ll / la: the real GNU ls, so Windows output is identical to Linux rather than
# a PowerShell approximation of it. Same flags as the aliases in .bashrc:
#
#   ll -> ls -lafg     long, all, unsorted, no owner column
#   la -> ls -lAh      long, almost-all, human-readable sizes
#
# scoop's coreutils is preferred over the copy bundled with Git for Windows.
# Both work, but git's reports 0 bytes for every directory and raw numeric UIDs
# where coreutils gives real sizes and group names.
#
# --color=always, not =auto: PowerShell captures the child's stdout, so `auto`
# sees a non-TTY and disables colour. The cost is that `ll | Out-File` keeps the
# escape codes - use `ls` for anything you intend to pipe.
#
# Resolved lazily and cached: this keeps the lookup out of shell startup, and
# `ll` is interactive so a one-off resolve costs nothing noticeable.
function script:Get-GnuLs {
    if ($script:GnuLsPath) { return $script:GnuLsPath }

    $candidates = @(
        "$env:USERPROFILE\scoop\apps\coreutils\current\bin\ls.exe"
        "$env:USERPROFILE\scoop\apps\git\current\usr\bin\ls.exe"
    )
    foreach ($c in $candidates) {
        if ([System.IO.File]::Exists($c)) { $script:GnuLsPath = $c; return $c }
    }
    # Last resort: whatever `ls` resolves to on PATH, ignoring the PowerShell alias.
    $onPath = Get-Command ls -CommandType Application -ErrorAction SilentlyContinue |
              Select-Object -First 1
    if ($onPath) { $script:GnuLsPath = $onPath.Source; return $script:GnuLsPath }
    return $null
}

function ll {
    $gnu = Get-GnuLs
    if ($gnu) { & $gnu -lafg --color=always @args; return }
    # No GNU ls: approximate rather than fail.
    Get-ChildItem -Force @args |
        Select-Object Mode, @{ N = 'Size'; E = { if ($_.PSIsContainer) { '<DIR>' } else { '{0,10:N0}' -f $_.Length } } },
                      LastWriteTime, Name
}

function la {
    $gnu = Get-GnuLs
    if ($gnu) { & $gnu -lAh --color=always @args; return }
    ll @args
}
