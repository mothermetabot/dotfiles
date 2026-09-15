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

# ch: cd to the best-matching directory ONE level down. No picker, no recursion.
#
# cb/cl already cover "search everywhere and let me choose". ch is the other
# case: you know roughly what the child is called and just want to be there.
#
# Ranking is deterministic - the same pattern in the same directory always
# resolves the same way:
#
#   0  name equals the pattern      ch nvim  -> ./nvim
#   1  name starts with it          ch nv    -> ./nvim
#   2  name contains it             ch onf   -> ./.config
#
# Only the BEST rank competes: an exact match always beats a prefix match, so
# `ch i3` goes to i3 and never offers i3status.
#
# The pattern is matched LITERALLY. Comparisons use .NET string methods rather
# than -like precisely so `*` and `?` are ordinary characters, not wildcards.
#
# On a tie within the best rank, fzf opens over just those candidates and Enter
# navigates. Without fzf it takes the first alphabetically.
#
# GetDirectories includes hidden directories, which matters: without them
# `ch conf` could never find .config.
#
# The bash twin is in .bashrc. Change one, change the other.
function ch {
    param([Parameter(Mandatory, Position = 0)][string]$Pattern)

    $cmp = [System.StringComparison]::OrdinalIgnoreCase
    $here = (Get-Location).ProviderPath
    if (-not $here) { Write-Warning 'ch: not on a filesystem path'; return }

    $bestRank = 99
    $matched  = [System.Collections.Generic.List[string]]::new()

    foreach ($dir in [System.IO.Directory]::GetDirectories($here)) {
        $name = [System.IO.Path]::GetFileName($dir)

        $rank = if     ($name.Equals($Pattern, $cmp))          { 0 }
                elseif ($name.StartsWith($Pattern, $cmp))      { 1 }
                elseif ($name.IndexOf($Pattern, $cmp) -ge 0)   { 2 }
                else                                           { continue }

        if ($rank -lt $bestRank) { $bestRank = $rank; $matched.Clear(); $matched.Add($dir) }
        elseif ($rank -eq $bestRank) { $matched.Add($dir) }
    }

    if ($matched.Count -eq 0) {
        Write-Warning "ch: no directory here matching '$Pattern'"
        return
    }
    if ($matched.Count -eq 1) {
        Set-Location -LiteralPath $matched[0]
        return
    }

    # Tie within the best rank: let fzf break it.
    $sorted = $matched | Sort-Object
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Set-Location -LiteralPath $sorted[0]
        return
    }

    $selection = $sorted |
        ForEach-Object { [System.IO.Path]::GetFileName($_) } |
        fzf --height 40% --reverse --prompt 'ch> ' `
            --header "$($matched.Count) matches for '$Pattern'"

    if ($selection) { Set-Location -LiteralPath (Join-Path $here $selection) }
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
