# fzf session picker for psmux (Prefix + s).
# Linux counterpart: fzf-session.sh

$ErrorActionPreference = 'Stop'

# list-sessions -F is used rather than parsing the default human-readable
# output, which is "name: N windows (created ...)".
$rows = @(psmux list-sessions -F '#{session_name}' 2>$null)

if (-not $rows -or $rows.Count -eq 0) {
    Write-Host 'No sessions found.'
    Start-Sleep -Seconds 1
    exit 0
}

$current = (psmux display-message -p '#{session_name}' 2>$null)

$selection = $rows | fzf `
    --reverse `
    --prompt='session> ' `
    --header="current: $current"

if (-not $selection) { exit 0 }

psmux switch-client -t $selection
