# cat -> bat, plus the listing helpers.
#
# Defined as functions rather than Set-Alias because aliases cannot carry
# default arguments.
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

# ll / la both exec GNU ls directly - no capture, no reformat, no fallback.
#
# `ls.exe` (not `ls`, which is the PowerShell alias for Get-ChildItem) resolves
# through the scoop shim to coreutils. There is deliberately no availability
# check: if coreutils is missing, ll fails with "the term 'ls.exe' is not
# recognized", which means run the bootstrap. coreutils is in
# install/packages.tsv for all three platforms.
#
# Executing ls directly also means the native process writes to the console and
# the terminal interprets ls's own ANSI, so --color works and the output stays
# pipeable. Capturing it to drop columns would cost both: Windows PowerShell 5.1
# runs with VT processing OFF for re-emitted strings, so escapes would arrive as
# literal text.
#
# Flags:
#   -l  long listing        -g  hide the owner
#   -h  human-readable      -G  hide the group
#   -a  include dotfiles
#
# -g and -G are as close to "size, date, name" as ls gets on its own. The mode
# and link-count columns stay, because -l always prints them and there is no
# column-selection flag.
#
# .bashrc has the same two definitions. Keep them identical.
function ll { ls.exe -lhgGa --color=always @args }

# la: the full long listing, every column, all but . and ..
function la { ls.exe -lAh --color=always @args }
