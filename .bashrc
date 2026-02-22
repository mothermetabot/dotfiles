# Git Bash interactive enhancements

# Skip everything when not interactive (prevents bind warnings in scripts)
case $- in
  *i*) ;;
  *) return ;;
esac

devshell() {
    local vcvars="C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    local bash_exe=$(cygpath -w "$(which bash)")
    local wrapper="$HOME/launch_msvc.bat"

    # We create a wrapper that sets the VS env, 
    # then MANUALLY moves the VS Binaries to the front of the PATH
    cat <<EOF > "$wrapper"
@echo off
call "$vcvars"
set PATH=%VCINSTALLDIR%Tools\MSVC\%VCToolsVersion%\bin\HostX64\x64;%PATH%
"$bash_exe" -l -i
EOF

    cmd.exe //c "$(cygpath -w "$wrapper")"
}
envup() {
  if [[ -f .env ]]; then
    set -a
    source .env
    set +a
  else
    echo "envup: no .env found in $(pwd)" >&2
    return 1
  fi
}

# Enable bash-completion when available (Git for Windows ships it)
if [ -z "$DISABLE_BASH_COMPLETION" ]; then
  if [ -r /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -r /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Ctrl+n / Ctrl+p cycle completion candidates (replaces Tab cycling)
bind 'set show-all-if-ambiguous on'
bind 'set menu-complete-display-prefix on'
bind '"\C-n":menu-complete'
bind '"\C-p":menu-complete-backward'

# History quality
shopt -s histappend
HISTCONTROL=ignoredups:erasedups
HISTSIZE=5000
HISTFILESIZE=10000

# Fuzzy history search with fzf when available; fall back to readline search
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

# if command -v fzf >/dev/null 2>&1; then
#   bind -x '"\C-r": _fzf_history_widget'
# else
#   bind '"\C-r": reverse-search-history'
# fi


alias ll="ls -lafg --color=auto"

# git pretty log function
function gl {
  if [ $# -eq 0 ]; then
    git log --graph --decorate --color --date=short \
      --pretty=format:'%C(bold blue)%h%C(reset) %C(bold green)%ad%C(reset)%C(red)%d%C(reset)%n  %s %C(dim white)(%an)%C(reset)' \
      --all
  else
    git log --graph --decorate --color --date=short \
      --pretty=format:'%C(bold blue)%h%C(reset) %C(bold green)%ad%C(reset)%C(red)%d%C(reset)%n  %s %C(dim white)(%an)%C(reset)' \
      "$@"
  fi
}

function o() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    NVIM_APPNAME="nvim_oil" nvim
  else
    mkdir -p -- "$path"
    cd "$path"
    NVIM_APPNAME="nvim_oil" nvim -- "$path"
  fi
}

alias pn="cd ~/proteus-now/"
export CC=gcc


eval "$(starship init bash)"

. "$HOME/.local/bin/env"
