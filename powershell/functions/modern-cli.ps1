# Modern replacements for ls and cat, matching the aliases in .bashrc.
#
# Defined as functions rather than Set-Alias because aliases cannot carry
# default arguments, and `ls`/`cat` need flags to behave sensibly. Each falls
# back to the PowerShell built-in when the tool is missing, so a machine that
# has not run bootstrap yet still works.

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls  { eza --group-directories-first @args }
    function l   { eza --group-directories-first --long --git @args }
    function la  { eza --group-directories-first --long --git --all @args }
    function lt  { eza --group-directories-first --tree --level=2 @args }
} else {
    function ls { Get-ChildItem @args }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    # --paging=never keeps `cat` behaving like cat in pipelines rather than
    # opening a pager and blocking.
    function cat { bat --paging=never @args }
    # `batp` when you actually do want the pager.
    function batp { bat @args }
} else {
    function cat { Get-Content @args }
}
