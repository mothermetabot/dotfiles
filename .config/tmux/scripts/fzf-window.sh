#!/usr/bin/env bash
# fzf window picker for tmux (Prefix + b).
# Windows counterpart: fzf-window.ps1
#
# Run inside `display-popup -E`, so stdout is the popup and exiting closes it.
# Lists every window in every session, so it doubles as a cross-session jump.

set -euo pipefail

fmt='#{session_name}:#{window_index}|#{window_name}|#{pane_current_path}'
rows=$(tmux list-windows -a -F "$fmt" 2>/dev/null || true)

if [ -z "$rows" ]; then
  echo 'No windows found.'
  sleep 1
  exit 0
fi

# | as the delimiter to stay identical to the PowerShell version.
selection=$(printf '%s\n' "$rows" | fzf \
  --delimiter='|' \
  --with-nth='1,2,3' \
  --reverse \
  --prompt='window> ' \
  --header='select a window') || exit 0

[ -z "$selection" ] && exit 0

target=${selection%%|*}
[ -n "$target" ] && tmux switch-client -t "$target"
