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

# ll / la are backed by the real GNU ls rather than a PowerShell approximation,
# so the data matches Linux exactly:
#
#   ll -> size, date, name      (mode/links/owner/group deliberately dropped)
#   la -> ls -lAh               full long listing, all columns
#
# scoop's coreutils is preferred over the copy bundled with Git for Windows.
# Both work, but git's reports 0 bytes for every directory and raw numeric UIDs
# where coreutils gives real sizes and group names. coreutils is in
# install/packages.tsv, so bootstrap installs it on all three platforms.
#
# la execs ls directly and keeps ls's own colours. ll has to capture the output
# to drop columns, which loses colour rendering - see the note inside ll - so it
# colours via Write-Host instead and therefore cannot be piped. Use plain `ls`
# if you need to redirect.
#
# Resolved lazily and cached: this keeps the lookup out of shell startup, and
# these are interactive commands where a one-off resolve costs nothing.
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

# ll shows size, date, name - no mode, no link count, no owner, no group.
#
# GNU ls cannot express that on its own: -g drops the owner and -G the group,
# but -l always prints the mode, and there is no column-selection flag. So we
# take `-lhgG --time-style=long-iso`, whose columns are then fixed at
#
#     mode  links  size  date  time  name
#
# and drop the first two. long-iso matters: the default time format is 3
# whitespace-separated fields for recent files and 3 different ones for old
# ones, so the name column would move depending on file age.
#
# The name is taken as "everything after the time" rather than as a field, so
# filenames containing spaces survive intact.
#
# .bashrc does the same reformat in awk. Keep the two column layouts identical.
function ll {
    $gnu = Get-GnuLs
    if (-not $gnu) {
        # No GNU ls: approximate rather than fail.
        Get-ChildItem -Force @args |
            Select-Object @{ N = 'Size'; E = { if ($_.PSIsContainer) { '' } else { '{0,10:N0}' -f $_.Length } } },
                          @{ N = 'Modified'; E = { $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm') } },
                          Name
        return
    }

    # --color=never, and we colour it ourselves.
    #
    # ls emits ANSI escapes, but Windows PowerShell 5.1 runs with VT processing
    # OFF for ordinary command output (verified: console mode 0x0, bit 0x4
    # clear), so those escapes reach the terminal as literal ←[01;34m text. The
    # prompt escapes colour fine only because PSReadLine enables VT for its own
    # drawing.
    #
    # Turning VT on needs a SetConsoleMode P/Invoke, and Add-Type costs ~200ms -
    # far too much for a shell that starts in ~320ms total. Write-Host's
    # -ForegroundColor uses the legacy console API instead, which needs no VT
    # and always renders.
    #
    # The mode column is still parsed - it is what tells us directory from
    # executable - it is just never printed.
    & $gnu -lhgG -a --time-style=long-iso --color=never @args |
        ForEach-Object {
            if ($_ -match '^total\s') { return }
            if ($_ -notmatch '^(?<mode>\S+)\s+\d+\s+(?<size>\S+)\s+(?<when>\S+\s+\S+)\s+(?<name>.*)$') {
                Write-Host $_
                return
            }

            $colour = Get-LsColour $Matches.mode
            Write-Host ('{0,6}  {1}  ' -f $Matches.size, $Matches.when) -NoNewline
            if ($colour) { Write-Host $Matches.name -ForegroundColor $colour }
            else         { Write-Host $Matches.name }
        }
}

# Colour a name the way ls would, using the console API rather than ANSI.
# See the note in ll for why we cannot just let ls emit escapes.
function script:Get-LsColour([string]$Mode) {
    if     ($Mode.StartsWith('d')) { 'Blue'  }   # directory
    elseif ($Mode.StartsWith('l')) { 'Cyan'  }   # symlink
    elseif ($Mode -match 'x')      { 'Green' }   # executable
    else                           { $null   }
}

# la: the full long listing, straight from ls with ls's own colours.
#
# This execs ls directly, so the native process writes to the console and the
# terminal interprets the ANSI itself - no VT flag on PowerShell's side needed.
# That is exactly why la never showed raw escapes while ll did: ll has to
# capture and re-emit the lines in order to drop columns, and re-emitted
# strings go through PowerShell, which has VT processing off.
function la {
    $gnu = Get-GnuLs
    if ($gnu) { & $gnu -lAh --color=always @args; return }
    ll @args
}
