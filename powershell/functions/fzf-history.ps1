# Ctrl+R history search through plain fzf.
#
# Replaces both PSFzf and atuin: no module to import, no daemon, no database -
# just PSReadLine's own history file piped through fzf. Mirrors the
# _fzf_history_widget in .bashrc so Ctrl+R behaves the same on both platforms.
#
# Requires PSReadLine (absent in non-interactive shells) and fzf.

if ((Get-Module -Name PSReadLine) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {

    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -BriefDescription 'FzfHistory' `
        -LongDescription 'Search command history with fzf' -ScriptBlock {

        $line   = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $histFile = (Get-PSReadLineOption).HistorySavePath
        if (-not (Test-Path -LiteralPath $histFile)) { return }

        # Newest first, and drop duplicates while preserving that order.
        $history = [System.Collections.Generic.List[string]]::new(
            [string[]][System.IO.File]::ReadAllLines($histFile))
        $history.Reverse()

        $selection = $history |
            Select-Object -Unique |
            fzf --height 40% --reverse --no-sort `
                --prompt 'history> ' --query $line

        if ($selection) {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selection)
        }
    }
}
