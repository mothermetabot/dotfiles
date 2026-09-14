# Prompt. bash half.
#
# The PowerShell half is prompt.ps1 in this directory. They must render
# identically - change one, change the other. See prompt.ps1 for the full
# rationale; the short version is that the prompt is a path, a branch and a
# character, we already read .git/HEAD ourselves, and starship was left doing
# nothing but emitting colour codes for a process spawn on every Enter.
#
# Rendering:
#   <cyan>dir</> on <purple>branch</>
#   <orange>λ</>   success
#   <red>ϟ</>      failure - differs in SHAPE as well as colour
#
# Source this from .bashrc. It sets PROMPT_COMMAND.

_prompt_max_parts=3

_prompt_clr_dir=$'\e[1;36m'               # bold cyan
_prompt_clr_git=$'\e[1;35m'               # bold purple
_prompt_clr_ok=$'\e[1;38;2;219;126;65m'   # bold #db7e41
_prompt_clr_err=$'\e[1;31m'               # bold red
_prompt_clr_reset=$'\e[0m'

# Walk up for .git once, setting _prompt_repo_root and _prompt_branch.
_prompt_repo_info() {
  _prompt_repo_root=''
  _prompt_branch=''

  local dir=$1 git_path head gitdir ref
  while [ -n "$dir" ]; do
    git_path="$dir/.git"
    if [ -e "$git_path" ]; then
      _prompt_repo_root=$dir
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
        ref=$(<"$head")
        case "$ref" in
          "ref: refs/heads/"*) _prompt_branch=${ref#ref: refs/heads/} ;;
          ?*)                  _prompt_branch=${ref:0:7} ;;   # detached HEAD
        esac
      fi
      return
    fi
    [ "$dir" = "/" ] && return
    dir=${dir%/*}
    [ -z "$dir" ] && dir=/
  done
}

_prompt_path() {
  local path=$1 root=$2 rel display
  if [ -n "$root" ]; then
    rel=${path#"$root"}; rel=${rel#/}
    display="${root##*/}${rel:+/$rel}"
  else
    case "$path" in
      "$HOME")   display='~' ;;
      "$HOME"/*) display="~/${path#"$HOME"/}" ;;
      *)         display=$path ;;
    esac
  fi

  # Keep only the last N components.
  local IFS='/' parts=() kept=() p
  read -ra parts <<< "$display"
  for p in "${parts[@]}"; do [ -n "$p" ] && kept+=("$p"); done
  if [ "${#kept[@]}" -gt "$_prompt_max_parts" ]; then
    display=$(IFS=/; echo "${kept[*]: -$_prompt_max_parts}")
  fi
  printf '%s' "$display"
}

_prompt_command() {
  # MUST be first: everything below overwrites $?.
  local status=$?

  local dir branch sym
  _prompt_repo_info "$PWD"
  dir=$(_prompt_path "$PWD" "$_prompt_repo_root")
  branch=$_prompt_branch

  if [ "$status" -eq 0 ]; then
    sym="${_prompt_clr_ok}λ"
  else
    sym="${_prompt_clr_err}ϟ"
  fi

  # \[ \] tell readline these bytes take no screen width; without them it
  # miscounts the line and mangles editing on long commands.
  PS1="\[${_prompt_clr_dir}\]${dir}\[${_prompt_clr_reset}\]"
  [ -n "$branch" ] && PS1+=" on \[${_prompt_clr_git}\]${branch}\[${_prompt_clr_reset}\]"
  PS1+="\n\[${sym}\]\[${_prompt_clr_reset}\] "
}

PROMPT_COMMAND=_prompt_command
