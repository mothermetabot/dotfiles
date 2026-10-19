# Branch completion for `git <subcommand> <TAB>`.
#
# Replaces the part of posh-git that was worth keeping. posh-git itself was
# dropped for its ~488 ms startup cost; this is one Register-ArgumentCompleter
# call, and the git process only runs when you actually press Tab.
#
# Only subcommands that take a branch or ref are handled. For anything else, and
# for options (-x / --x), it returns nothing so PowerShell falls back to its
# normal file-path completion.
Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -like '-*') { return }

    # First element after `git` that is not an option is the subcommand.
    $sub = $null
    foreach ($el in $commandAst.CommandElements | Select-Object -Skip 1) {
        $s = $el.ToString()
        if ($s -notlike '-*') { $sub = $s; break }
    }

    # Still typing the subcommand itself: nothing to offer.
    if (-not $sub -or $sub -eq $wordToComplete) { return }

    $takesRef = 'checkout', 'switch', 'merge', 'rebase', 'branch', 'diff', 'log',
                'show', 'cherry-pick', 'reset', 'push', 'pull', 'fetch', 'revert'
    if ($sub -notin $takesRef) { return }

    # Local branches, then remotes (minus the origin/HEAD pointer).
    #
    # Full refnames, not :short - the short form of refs/remotes/origin/HEAD is
    # just "origin", which cannot be told apart from a branch of that name.
    $refs = @(git for-each-ref --format='%(refname)' refs/heads refs/remotes 2>$null) |
        Where-Object { $_ -and $_ -notlike '*/HEAD' } |
        ForEach-Object { $_ -replace '^refs/(heads|remotes)/', '' }

    $refs |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_)
        }
}
