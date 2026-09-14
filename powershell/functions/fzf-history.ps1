# Ctrl+R history search through plain fzf. No PSFzf.
#
# An earlier attempt at this appeared to do nothing when pressed, and I wrongly
# concluded that fzf cannot run from inside a PSReadLine key handler. It can -
# PSFzf does exactly this. The missing piece was the redraw: after fzf exits it
# has scribbled over the screen, and PSReadLine has to be told to repaint. That
# is PSFzf's `InvokePromptHack`, reproduced below.
#
# The other fix is using Replace(0, len, text) rather than RevertLine + Insert,
# which is what PSFzf does and behaves correctly with a non-empty buffer.
#
# Do NOT gate on `Get-Module -Name PSReadLine`: the console host imports it
# lazily, AFTER the profile runs, so that check is false here and the handler
# silently never registers.
#
# Import explicitly rather than letting Get-Command auto-load it. Auto-loading
# makes PowerShell scan every module path to find which module provides the
# command. Measured in fresh processes:
#
#   Get-Command Set-PSReadLineKeyHandler ... 50 ms   (triggers the search)
#   Import-Module PSReadLine ............... 39 ms   (no search)
#   Set-PSReadLineKeyHandler itself ........ 30 ms
#
# The import is not really our cost - an interactive shell loads PSReadLine
# regardless - but the ~10ms of searching is.
Import-Module PSReadLine -ErrorAction SilentlyContinue

if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {

    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -BriefDescription 'FzfHistory' `
        -LongDescription 'Search command history with fzf' -ScriptBlock {

        # fzf is checked HERE, not at registration: it only matters on keypress,
        # it saves a PATH scan at startup, and installing fzf later then works
        # without re-sourcing the profile.
        if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

        $line   = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $histFile = (Get-PSReadLineOption).HistorySavePath
        if (-not [System.IO.File]::Exists($histFile)) { return }

        # Newest first, de-duplicated while preserving that order.
        $seen    = [System.Collections.Generic.HashSet[string]]::new()
        $entries = [System.Collections.Generic.List[string]]::new()
        $all     = [System.IO.File]::ReadAllLines($histFile)
        for ($i = $all.Length - 1; $i -ge 0; $i--) {
            $e = $all[$i]
            if ([string]::IsNullOrWhiteSpace($e)) { continue }
            if ($seen.Add($e)) { $entries.Add($e) }
        }

        $selection = $entries | fzf --height 40% --reverse --no-sort `
                                    --prompt 'history> ' --query $line

        # Repaint before touching the buffer: fzf has drawn over the prompt and
        # PSReadLine does not know. Without this the handler looks like a no-op.
        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [Text.Encoding]::UTF8
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        } finally {
            [Console]::OutputEncoding = $prevEncoding
        }

        if (-not [string]::IsNullOrEmpty($selection)) {
            if ($selection -is [array]) { $selection = $selection -join "`n" }
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $selection)
        }
    }
}
