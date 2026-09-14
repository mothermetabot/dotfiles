#!/usr/bin/env bash
# Provision this machine from the dotfiles repo. Linux side.
#
# Counterpart to bootstrap.ps1. The deploy step is GNU stow: the repo root
# mirrors $HOME, so one `stow .` places everything, with .stow-local-ignore
# holding back the parts that are not $HOME content.
#
# Two package sources, deliberately:
#   distro  i3, fonts, X/Wayland deps, stow itself - Homebrew on Linux does not
#           ship GUI or display-server packages, so these cannot come from brew
#   brew    the CLI tools, so versions match the scoop ones on Windows
#
# Usage:
#   ./bootstrap.sh              # full run
#   ./bootstrap.sh --dry-run    # print what would happen
#   ./bootstrap.sh --no-packages

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
SKIP_PACKAGES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --no-packages) SKIP_PACKAGES=1 ;;
    -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

changed=0; skipped=0; warned=0
head()  { printf '\n\033[32m%s\033[0m\n' "$1"; }
did()   { printf '  \033[36m+ %s\033[0m\n' "$1"; changed=$((changed+1)); }
skip()  { printf '  \033[90m= %s\033[0m\n' "$1"; skipped=$((skipped+1)); }
warn()  { printf '  \033[33m! %s\033[0m\n' "$1"; warned=$((warned+1)); }
plan()  { printf '  \033[35m? %s\033[0m\n' "$1"; changed=$((changed+1)); }

# --- distro detection ---------------------------------------------------------

detect_distro_pm() {
  if   command -v pacman  >/dev/null 2>&1; then echo pacman
  elif command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf     >/dev/null 2>&1; then echo dnf
  else echo none
  fi
}
PM="$(detect_distro_pm)"

distro_install() {
  local pkgs=("$@")
  [ ${#pkgs[@]} -eq 0 ] && return 0
  case "$PM" in
    pacman) sudo pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    apt)    sudo apt-get install -y "${pkgs[@]}" ;;
    dnf)    sudo dnf install -y "${pkgs[@]}" ;;
    *)      warn "no supported package manager; install manually: ${pkgs[*]}" ;;
  esac
}

# --- 0. preconditions ---------------------------------------------------------

head '[0/6] Preconditions'
[ -f "$REPO/install/packages.tsv" ] || { echo "packages.tsv not found; is $REPO the repo root?" >&2; exit 1; }
skip "repo root: $REPO"
skip "distro package manager: $PM"

# --- 1. packages --------------------------------------------------------------

head '[1/6] Packages'

if [ "$SKIP_PACKAGES" = 1 ]; then
  skip 'skipped (--no-packages)'
else
  # Column 3 = brew, column 4 = distro. '-' means not available there.
  mapfile -t brew_pkgs < <(awk -F'\t' '!/^#/ && NF>=3 && $3!="-" && $3!="" {print $3}' "$REPO/install/packages.tsv")
  mapfile -t distro_pkgs < <(awk -F'\t' '!/^#/ && NF>=4 && $4!="-" && $4!="" {print $4}' "$REPO/install/packages.tsv")

  if [ "$DRY_RUN" = 1 ]; then
    plan "would install via $PM: ${distro_pkgs[*]}"
    plan "would install via brew: ${brew_pkgs[*]}"
  else
    # stow and git are needed by this script itself, so they go first.
    distro_install stow git
    distro_install "${distro_pkgs[@]}"
    did "distro packages (${#distro_pkgs[@]})"

    if ! command -v brew >/dev/null 2>&1; then
      warn 'brew not found; skipping brew packages'
      warn 'install: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    else
      brew install "${brew_pkgs[@]}"
      did "brew packages (${#brew_pkgs[@]})"
    fi
  fi
fi

# --- 2. base directories ------------------------------------------------------

head '[2/6] Base directories'

# ~/.config MUST exist as a real directory before stowing. Otherwise stow folds
# the tree and links ~/.config itself at the repo, so every tool that writes
# into ~/.config writes into the git tree. That is exactly how startup.log,
# .nvimlog, scoop/config.json and uv-receipt.json ended up tracked.
for d in "$HOME/.config" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.cache"; do
  if [ -d "$d" ]; then
    skip "$d"
  elif [ "$DRY_RUN" = 1 ]; then
    plan "would create $d"
  else
    mkdir -p "$d"; did "created $d"
  fi
done

# --- 3. tmux plugin tail ------------------------------------------------------

head '[3/6] tmux plugin manager'

# Nothing to generate: .config/tmux is stowed like everything else, and tmux
# discovers ~/.config/tmux/tmux.conf on its own. The config branches internally
# with if-shell, so the same file serves psmux on Windows.
if [ "$DRY_RUN" = 1 ]; then
  plan 'would chmod +x the picker scripts and clone tpm'
else
  chmod +x "$REPO/.config/tmux/scripts/"*.sh 2>/dev/null || true
  did 'picker scripts executable'
fi

TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [ -d "$TPM_DIR" ]; then
  skip 'tpm present'
elif [ "$DRY_RUN" = 1 ]; then
  plan 'would clone tpm'
else
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
  did 'cloned tpm'
fi

# --- 4. deploy ----------------------------------------------------------------

head '[4/6] Deploy (stow)'

if ! command -v stow >/dev/null 2>&1; then
  warn 'stow not installed; cannot deploy'
elif [ "$DRY_RUN" = 1 ]; then
  # stow's own simulate mode is more accurate than anything we could print.
  stow --simulate --verbose --dir "$REPO/.." --target "$HOME" "$(basename "$REPO")" 2>&1 | sed 's/^/  /'
else
  stow --restow --dir "$REPO/.." --target "$HOME" "$(basename "$REPO")"
  did "stowed $REPO -> $HOME"
fi

# --- 5. fonts -----------------------------------------------------------------

head '[5/6] Fonts'

# Nerd Fonts are not in brew (casks are macOS-only) and are patchy across
# distros, so use getnf, which drops them in ~/.local/share/fonts and runs
# fc-cache. Windows gets the same font from the scoop nerd-fonts bucket.
if fc-list 2>/dev/null | grep -qi 'CommitMono Nerd Font'; then
  skip 'CommitMono Nerd Font present'
elif [ "$DRY_RUN" = 1 ]; then
  plan 'would install CommitMono Nerd Font via getnf'
elif command -v getnf >/dev/null 2>&1; then
  getnf -i CommitMono
  did 'installed CommitMono Nerd Font'
else
  warn 'getnf not installed; see https://github.com/getnf/getnf'
  warn 'then run: getnf -i CommitMono'
fi

# --- 6. local overrides -------------------------------------------------------

head '[6/6] Local overrides'

# Gitignored files for machine-specific settings. Created empty so the
# conditional sources in .bashrc and .config/git/config have something to find.
for f in "$HOME/.bashrc.local" "$REPO/.config/git/config.local"; do
  if [ -f "$f" ]; then
    skip "$f"
  elif [ "$DRY_RUN" = 1 ]; then
    plan "would create $f"
  else
    printf '# Machine-local overrides. Gitignored.\n' > "$f"
    did "created $f"
  fi
done

# ------------------------------------------------------------------------------

verb=$([ "$DRY_RUN" = 1 ] && echo planned || echo applied)
printf '\n\033[33m%d %s, %d already correct, %d warning(s).\033[0m\n' \
  "$changed" "$verb" "$skipped" "$warned"
[ "$DRY_RUN" = 1 ] && printf '\033[33mDry run - nothing changed.\033[0m\n'
printf '\033[33mOpen a new shell to pick up the changes.\033[0m\n\n'
