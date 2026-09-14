# Interactive bash configuration. Linux only - Windows uses PowerShell.
#
# This file used to target Git Bash on Windows: it carried a `devshell`
# function that shelled out to cmd.exe, cygpath and vcvars64.bat, and pointed
# at a Visual Studio Enterprise path that did not match the BuildTools install
# the bootstrap actually performed. All of that is gone; `dev` in the
# PowerShell profile is the Windows equivalent.

# Skip everything when not interactive (prevents bind warnings in scripts).
case $- in
  *i*) ;;
  *) return ;;
esac

# --- history ------------------------------------------------------------------
shopt -s histappend
HISTCONTROL=ignoredups:erasedups
HISTSIZE=5000
HISTFILESIZE=10000

# --- completion ---------------------------------------------------------------
if [ -z "$DISABLE_BASH_COMPLETION" ]; then
  if [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -r /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Ctrl+n / Ctrl+p cycle completion candidates (replaces Tab cycling).
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'
bind '"\C-n":menu-complete'
bind '"\C-p":menu-complete-backward'

# --- fuzzy history ------------------------------------------------------------
# Superseded by atuin when installed (see the bottom of this file); kept as
# the fallback for machines without it.
_fzf_history_widget() {
  local selected
  selected=$(
    HISTTIMEFORMAT= builtin history |
      fzf +s --tac --no-sort --query "$READLINE_LINE" --prompt='history> ' \
          --bind='ctrl-r:toggle-sort'
  ) || return
  READLINE_LINE=$(printf '%s' "$selected" | sed 's/^[[:space:]]*[0-9]\+[[:space:]]*//')
  READLINE_POINT=${#READLINE_LINE}
}

if command -v fzf >/dev/null 2>&1; then
  bind -x '"\C-r": _fzf_history_widget'
else
  bind '"\C-r": reverse-search-history'
fi

# --- modern replacements ------------------------------------------------------
# Mirrors powershell/functions/modern-cli.ps1. Each guarded so a machine that
# has not run bootstrap yet still gets working ls/cat.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias l='eza --group-directories-first --long --git'
  alias la='eza --group-directories-first --long --git --all'
  alias lt='eza --group-directories-first --tree --level=2'
  # CAVEAT: eza's -f is --only-files, which HIDES directories. It is not GNU
  # ls's -f (do not sort). If you wanted the old `ls -lafg` listing, use `la`.
  alias ll='eza -afGH'
else
  alias ls='ls --color=auto'
  alias ll='ls -lafg --color=auto'
fi

if command -v bat >/dev/null 2>&1; then
  # --paging=never so cat stays usable in pipelines instead of opening a pager.
  alias cat='bat --paging=never'
  alias batp='bat'
fi

# --- aliases and functions ----------------------------------------------------

envup() {
  local file="${1:-.env}"
  if [[ -f "$file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
  else
    echo "envup: no $file found in $(pwd)" >&2
    return 1
  fi
}

# gl: pretty git log. Mirrors powershell/functions/git-shortcuts.ps1.
#   gl              -> current branch only
#   gl main         -> that branch only
#   gl main feat/x  -> those branches only
#   gl --all        -> anything else passes straight through to git log
gl() {
  local fmt='%C(bold blue)%h%C(reset) %C(bold green)%ad%C(reset)%C(red)%d%C(reset)%n  %s %C(dim white)(%an)%C(reset)'
  local common=(--graph --decorate --color --date=short --pretty=format:"$fmt")
  if [ $# -eq 0 ]; then
    # HEAD rather than --all, and it still resolves when detached.
    git log "${common[@]}" HEAD
  else
    git log "${common[@]}" "$@"
  fi
}

# Complete gl with branch names, local first then remote.
_gl_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local branches
  branches=$(
    git branch --format='%(refname:short)' 2>/dev/null
    git branch -r --format='%(refname:short)' 2>/dev/null
  )
  mapfile -t COMPREPLY < <(compgen -W "$branches" -- "$cur")
}
complete -F _gl_complete gl

# gs: short status with branch header.
gs() { git status --short --branch "$@"; }

# ga: stage everything in the repo, from anywhere inside it.
# `:/` is git's top-level pathspec magic, so this reaches the repo root with no
# cd and no `git rev-parse --show-toplevel`.
ga() {
  if [ $# -eq 0 ]; then
    git add --all -- :/
  else
    git add --all -- "$@"
  fi
}

# Fuzzy navigation, matching the PowerShell functions of the same names.
cb() {
  local sel
  sel=$(fd --type d | fzf) || return
  [ -n "$sel" ] && cd "$sel" || return
}

fvim() {
  local sel
  sel=$(rg --files --hidden --glob '!.git/*' | fzf) || return
  [ -n "$sel" ] && nvim "$sel"
}

n() { nvim .; }

# --- prompt and navigation ----------------------------------------------------
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init bash --cmd c)"

# atuin owns Ctrl+R when present, replacing _fzf_history_widget above.
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init bash --disable-up-arrow)"
fi

# --- machine-local overrides --------------------------------------------------
# Gitignored. Project shortcuts, proxies, credentials, uv's PATH shim.
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
