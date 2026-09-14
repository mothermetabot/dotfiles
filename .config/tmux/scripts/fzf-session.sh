#!/usr/bin/env bash
# fzf session picker for tmux (Prefix + s).
# Windows counterpart: fzf-session.ps1

set -euo pipefail

rows=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

if [ -z "$rows" ]; then
  echo 'No sessions found.'
  sleep 1
  exit 0
fi

current=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo '')

selection=$(printf '%s\n' "$rows" | fzf \
  --reverse \
  --prompt='session> ' \
  --header="current: $current") || exit 0

[ -z "$selection" ] && exit 0

tmux switch-client -t "$selection"
