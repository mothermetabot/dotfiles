# Fuzzy navigation and file opening. Requires fd, fzf, rg and nvim, all of
# which bootstrap.ps1 installs (fd was missing from the old bootstrap.bat, so
# `cb` was broken on a freshly provisioned machine).

# cb: fuzzy-pick a directory and cd into it.
function cb {
    $selection = fd --type d | fzf
    if (-not $selection) { return }   # cancelled with Esc / Ctrl+C

    Set-Location -LiteralPath $selection
}

# cl: fuzzy-pick a file and cd to its containing directory.
function cl {
    $selection = fzf
    if (-not $selection) { return }

    Set-Location -LiteralPath (Split-Path -Parent $selection)
}

# n: open nvim on the current directory.
function n { nvim . }

# fvim: fuzzy-pick a file by name and open it.
function fvim {
    $selection = rg --files --hidden --glob '!.git/*' | fzf
    if (-not $selection) { return }

    nvim $selection
}

# gvim: live-grep with rg, open the hit at the right line and column.
function gvim {
    $selection = fzf `
        --ansi `
        --disabled `
        --prompt 'grep> ' `
        --with-shell 'powershell.exe -NoProfile -Command' `
        --bind "change:reload:rg --column --line-number --no-heading --color=always --smart-case --hidden --glob '!.git/*' {q}; if (`$LASTEXITCODE -eq 1) { exit 0 }" `
        --bind "result:transform-list-label:if (`$env:FZF_MATCH_COUNT -eq 0) { ' No matches ' } else { ' ' + `$env:FZF_MATCH_COUNT + ' matches ' }" `
        --delimiter ':'

    if (-not $selection) { return }

    if ($selection -match '^(.*):(\d+):(\d+):(.*)$') {
        $file   = $matches[1]
        $line   = $matches[2]
        $column = $matches[3]

        nvim "+call cursor($line,$column)" -- $file
    }
}
