# fzf window picker for psmux (Prefix + b).
# Linux counterpart: fzf-window.sh
#
# Run inside `display-popup -E`, so stdout is the popup and exiting closes it.
# Lists every window in every session, not just the current one, so it doubles
# as a cross-session jump.

$ErrorActionPreference = 'Stop'

$fmt = '#{session_name}:#{window_index}|#{window_name}|#{pane_current_path}'
$rows = @(psmux list-windows -a -F $fmt 2>$null)

if (-not $rows -or $rows.Count -eq 0) {
    Write-Host 'No windows found.'
    Start-Sleep -Seconds 1
    exit 0
}

# --with-nth shows all three columns; the target is column 1, split back off
# afterwards. Using | as the delimiter because Windows paths contain \ and :.
$selection = $rows | fzf `
    --delimiter='|' `
    --with-nth='1,2,3' `
    --reverse `
    --prompt='window> ' `
    --header='select a window'

if (-not $selection) { exit 0 }   # cancelled with Esc / Ctrl+C

$target = ($selection -split '\|')[0]
if ($target) { psmux switch-client -t $target }
