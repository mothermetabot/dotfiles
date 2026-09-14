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
# The PowerShell side gets this from PSFzf; bash needs it wired by hand.
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

# --- aliases and functions ----------------------------------------------------
alias ll="ls -lafg --color=auto"

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

# gl: pretty git log. Mirrors the `gl` provided by the GG module on Windows.
gl() {
  local fmt='%C(bold blue)%h%C(reset) %C(bold green)%ad%C(reset)%C(red)%d%C(reset)%n  %s %C(dim white)(%an)%C(reset)'
  if [ $# -eq 0 ]; then
    git log --graph --decorate --color --date=short --pretty=format:"$fmt" --all
  else
    git log --graph --decorate --color --date=short --pretty=format:"$fmt" "$@"
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

# --- machine-local overrides --------------------------------------------------
# Gitignored. Project shortcuts, proxies, credentials, uv's PATH shim.
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
