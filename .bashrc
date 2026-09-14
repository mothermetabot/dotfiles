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
# Ctrl+R through plain fzf. Mirrors powershell/functions/fzf-history.ps1;
# no module, no daemon, no database.
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
# Mirrors powershell/functions/modern-cli.ps1. eza was tried and dropped: the
# Windows build hangs on any listing, and keeping the two shells identical is
# worth more than the colours.
alias ls='ls --color=auto'
alias ll='ls -lafg --color=auto'
alias la='ls -lAh --color=auto'

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

# --- prompt data --------------------------------------------------------------
# Equivalent of powershell/functions/prompt-vars.ps1. The starship config is
# SHARED between both platforms and renders these two variables with its
# [env_var] module, so without this the branch and path silently vanish here.
#
# The point is that starship never opens the git repo: its git modules - and
# `directory` with truncate_to_repo on - cost ~130ms per prompt on the Windows
# box for the repo open alone. Reading .git/HEAD is a fraction of a ms.
#
# Change this and prompt-vars.ps1 together; they must produce the same strings.
_dotfiles_prompt_max_parts=3

_dotfiles_prompt_vars() {
  local path repo_root='' branch='' git_path head gitdir rel display
  path=$PWD

  local dir=$path
  while [ -n "$dir" ]; do
    git_path="$dir/.git"
    if [ -e "$git_path" ]; then
      repo_root=$dir
      if [ -d "$git_path" ]; then
        head="$git_path/HEAD"
      else
        # Worktrees and submodules use a .git FILE: "gitdir: <path>"
        gitdir=$(sed -n 's/^gitdir: //p' "$git_path" 2>/dev/null)
        case "$gitdir" in
          /*) : ;;
          ?*) gitdir="$dir/$gitdir" ;;
        esac
        head="${gitdir:+$gitdir/HEAD}"
      fi
      if [ -n "$head" ] && [ -r "$head" ]; then
        local ref
        ref=$(<"$head")
        case "$ref" in
          "ref: refs/heads/"*) branch=${ref#ref: refs/heads/} ;;
          ?*)                  branch=${ref:0:7} ;;   # detached HEAD
        esac
      fi
      break
    fi
    [ "$dir" = "/" ] && break
    dir=$(dirname "$dir")
  done

  if [ -n "$branch" ]; then export STARSHIP_GIT_BRANCH="$branch"
  else unset STARSHIP_GIT_BRANCH
  fi

  if [ -n "$repo_root" ]; then
    rel=${path#"$repo_root"}; rel=${rel#/}
    display="${repo_root##*/}${rel:+/$rel}"
  else
    case "$path" in
      "$HOME")   display='~' ;;
      "$HOME"/*) display="~/${path#"$HOME"/}" ;;
      *)         display=$path ;;
    esac
  fi

  # Keep only the last N components, like starship's truncation_length.
  local IFS='/' parts=() p
  read -ra parts <<< "$display"
  local kept=()
  for p in "${parts[@]}"; do [ -n "$p" ] && kept+=("$p"); done
  if [ "${#kept[@]}" -gt "$_dotfiles_prompt_max_parts" ]; then
    display=$(IFS=/; echo "${kept[*]: -$_dotfiles_prompt_max_parts}")
  fi

  export STARSHIP_DIR="$display"
}

# starship calls this before every prompt, if defined.
starship_precmd_user_func() { _dotfiles_prompt_vars; }

# --- prompt and navigation ----------------------------------------------------
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v zoxide   >/dev/null 2>&1 && eval "$(zoxide init bash --cmd c)"

# --- machine-local overrides --------------------------------------------------
# Gitignored. Project shortcuts, proxies, credentials, uv's PATH shim.
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
