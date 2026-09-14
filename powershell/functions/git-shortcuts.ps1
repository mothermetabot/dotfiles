# git shortcuts, mirroring the bash functions of the same names in .bashrc.
#
# NOTE: the GG module also exports `gl` and `gs`. profile.ps1 imports GG BEFORE
# dot-sourcing this directory so these definitions win; swap the order there if
# you would rather keep GG's versions.

$script:GlFormat =
    '%C(bold blue)%h%C(reset) %C(bold green)%ad%C(reset)%C(red)%d%C(reset)%n' +
    '  %s %C(dim white)(%an)%C(reset)'

# gl: pretty git log.
#   gl                  -> current branch only
#   gl main             -> that branch only
#   gl main feat/x      -> those branches only
#   gl --all            -> anything else is passed straight through to git log
function gl {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Refs
    )

    $common = @(
        '--graph', '--decorate', '--color', '--date=short',
        "--pretty=format:$script:GlFormat"
    )

    if (-not $Refs -or $Refs.Count -eq 0) {
        # No ref given: current branch only, not --all. Detached HEAD still
        # works because HEAD is always a valid revision.
        git log @common HEAD
        return
    }

    git log @common @Refs
}

# Complete branch names for `gl`. Local branches first, then remotes.
Register-ArgumentCompleter -CommandName gl -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $branches = @(git branch --format='%(refname:short)' 2>$null) +
                @(git branch -r --format='%(refname:short)' 2>$null)

    $branches |
        Where-Object { $_ -and $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $_)
        }
}

# gs: short status.
function gs { git status --short @args }

# ga: stage everything in the repo, from anywhere inside it.
#
# `:/` is git's top-level pathspec magic, so this reaches the repo root without
# needing `cd` or `git rev-parse --show-toplevel`. Passing paths overrides that
# and stages only those, relative to the current directory as usual.
function ga {
    if ($args.Count -eq 0) { git add --all -- ':/' }
    else                   { git add --all -- @args }
}
