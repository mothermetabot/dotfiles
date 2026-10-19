# Shared, tidy command history across shells.
#
# PSReadLine already saves every command to one file (SaveIncrementally) and
# reads other sessions' commands back in - but only at the START of each prompt,
# i.e. after you press Enter in this shell. So with two shells open, a command
# typed in A is invisible to Up-arrow in B until B has run something itself.
#
# Fix: also pull in new lines from the file when Up/Down is pressed. There is no
# public API for that, so this calls PSReadLine's own private
# MaybeReadHistoryFile - the exact routine it runs at every prompt. It is cheap
# when nothing changed (it compares the file size), and every step is guarded:
# if a PSReadLine update renames the method, Up/Down just fall back to stock
# behaviour.
Import-Module PSReadLine -ErrorAction SilentlyContinue

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {

    function Sync-SharedHistory {
        try {
            $t     = [Microsoft.PowerShell.PSConsoleReadLine]
            $flags = [Reflection.BindingFlags]'NonPublic,Instance,Static'
            $self  = $t.GetField('_singleton', $flags).GetValue($null)
            $t.GetMethod('MaybeReadHistoryFile', $flags).Invoke($self, @())
        } catch { }
    }

    Set-PSReadLineKeyHandler -Key UpArrow -BriefDescription 'PreviousHistorySynced' `
        -LongDescription 'Previous history entry, after pulling in other shells'' commands' `
        -ScriptBlock {
            Sync-SharedHistory
            [Microsoft.PowerShell.PSConsoleReadLine]::PreviousHistory()
        }

    Set-PSReadLineKeyHandler -Key DownArrow -BriefDescription 'NextHistorySynced' `
        -LongDescription 'Next history entry, after pulling in other shells'' commands' `
        -ScriptBlock {
            Sync-SharedHistory
            [Microsoft.PowerShell.PSConsoleReadLine]::NextHistory()
        }

    # psmux types `cd '<dir>'; try { ...SetCurrentDirectory($PWD.ProviderPath)... }
    # ; cls` into every new pane to set its working directory. PSReadLine records
    # it like anything you typed, which buried real commands in Up-arrow and
    # Ctrl+R. Returning $false keeps it out of history entirely; everything else
    # gets PSReadLine's default decision (which skips lines holding passwords and
    # tokens). fzf-history.ps1 filters the same pattern for lines already saved.
    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)
        if ($line -like '*SetCurrentDirectory($PWD.ProviderPath)*') { return $false }
        try   { [Microsoft.PowerShell.PSConsoleReadLine]::GetDefaultAddToHistoryOption($line) }
        catch { $true }
    }
}
