#!/usr/bin/env bash
# Provision this machine from the dotfiles repo. Linux side.
#
# Counterpart to bootstrap.ps1. The deploy step is GNU stow: the repo root
# mirrors $HOME, so one `stow .` places everything, with .stow-local-ignore
# holding back the parts that are not $HOME content.
#
# Homebrew is the package manager here, and the distro one is kept to the
# minimum:
#   distro  git plus Homebrew's own prerequisites, installed first, and the
#           packages brew cannot ship: i3, rofi, kitty and other GUI or
#           display-server tools. That is every packages.tsv row whose brew
#           column is '-'.
#   brew    everything else, so versions match the scoop ones on Windows.
#           Homebrew itself is installed if it is missing.
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
die()   { printf '  \033[31mx %s\033[0m\n' "$1" >&2; exit 1; }

# --- distro package manager ---------------------------------------------------

detect_distro_pm() {
  if   command -v pacman  >/dev/null 2>&1; then echo pacman
  elif command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v dnf     >/dev/null 2>&1; then echo dnf
  else echo none
  fi
}
PM="$(detect_distro_pm)"

# Homebrew's documented build prerequisites, plus git. Names differ per distro.
case "$PM" in
  apt)    BREW_PREREQS=(build-essential procps curl file git) ;;
  pacman) BREW_PREREQS=(base-devel procps-ng curl file git) ;;
  dnf)    BREW_PREREQS=(gcc gcc-c++ make procps-ng curl file git) ;;
  *)      BREW_PREREQS=() ;;
esac

APT_UPDATED=0
distro_cmd() {
  case "$PM" in
    pacman) sudo pacman -S --needed --noconfirm "$@" ;;
    apt)
      # A fresh machine can have an empty or stale package index.
      if [ "$APT_UPDATED" = 0 ]; then sudo apt-get update; APT_UPDATED=1; fi
      sudo apt-get install -y "$@" ;;
    dnf)    sudo dnf install -y "$@" ;;
    *)      return 1 ;;
  esac
}

# apt and dnf refuse the whole list when a single name is unknown, and with
# set -e that used to end the run before anything else happened. So try the
# batch first, and on failure retry one at a time and warn about the rest.
distro_install() {
  [ $# -eq 0 ] && return 0
  if [ "$PM" = none ]; then
    warn "no supported package manager; install manually: $*"
    return 0
  fi
  distro_cmd "$@" && return 0
  local p
  for p in "$@"; do
    distro_cmd "$p" || warn "$PM could not install: $p"
  done
}

# --- Homebrew -----------------------------------------------------------------

# The installer uses the shared prefix when it can sudo, the home one otherwise.
# .bashrc checks the same two paths so new shells find brew.
BREW_PREFIXES=(/home/linuxbrew/.linuxbrew "$HOME/.linuxbrew")

# Put brew on PATH for the rest of this script. The installer does not do that
# for the shell that called it.
load_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  local p
  for p in "${BREW_PREFIXES[@]}"; do
    if [ -x "$p/bin/brew" ]; then
      eval "$("$p/bin/brew" shellenv)"
      return 0
    fi
  done
  return 1
}

# Same batch-then-one-by-one fallback as distro_install.
brew_install() {
  [ $# -eq 0 ] && return 0
  brew install "$@" && return 0
  local p
  for p in "$@"; do
    brew install "$p" || warn "brew could not install: $p"
  done
}

# --- 0. preconditions ---------------------------------------------------------

head '[0/7] Preconditions'
[ -f "$REPO/install/packages.tsv" ] || die "packages.tsv not found; is $REPO the repo root?"
skip "repo root: $REPO"
skip "distro package manager: $PM"

# --- 1. git and Homebrew ------------------------------------------------------

head '[1/7] git and Homebrew'

have_brew=0; load_brew && have_brew=1
have_git=0;  command -v git >/dev/null 2>&1 && have_git=1

if [ "$have_git" = 1 ] && [ "$have_brew" = 1 ]; then
  skip "git: $(command -v git)"
  skip "brew: $(command -v brew)"
elif [ "$SKIP_PACKAGES" = 1 ]; then
  [ "$have_git"  = 1 ] || warn 'git not installed (--no-packages)'
  [ "$have_brew" = 1 ] || warn 'brew not installed (--no-packages)'
elif [ "$DRY_RUN" = 1 ]; then
  if [ "$have_brew" = 0 ]; then
    plan "would install via $PM: ${BREW_PREREQS[*]}"
    plan 'would install Homebrew'
  else
    plan "would install git via $PM"
  fi
elif [ "$have_brew" = 0 ]; then
  [ "$PM" = none ] && die 'no supported package manager for git and the Homebrew prerequisites'
  distro_install "${BREW_PREREQS[@]}"
  command -v git  >/dev/null 2>&1 || die 'git failed to install'
  command -v curl >/dev/null 2>&1 || die 'curl failed to install'
  did "prerequisites via $PM: ${BREW_PREREQS[*]}"

  # NONINTERACTIVE stops the installer asking for confirmation, but it then
  # only uses `sudo -n`, so refresh the sudo timestamp first. Without sudo it
  # falls back to the home prefix, where most bottles build from source.
  sudo -v
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew || die 'Homebrew installed but brew was not found in any known prefix'
  did "Homebrew: $(command -v brew)"
else
  skip "brew: $(command -v brew)"
  distro_install git
  command -v git >/dev/null 2>&1 || die 'git failed to install'
  did "git via $PM"
fi

# --- 2. packages --------------------------------------------------------------

head '[2/7] Packages'

if [ "$SKIP_PACKAGES" = 1 ]; then
  skip 'skipped (--no-packages)'
else
  # Column 3 = brew, column 4 = distro. '-' means not available there.
  # A row with a brew formula comes from brew only. The distro column is used
  # only when brew has nothing, which leaves the GUI and display-server tools.
  # A `local:` prefix in the brew column is a formula kept in this repo rather
  # than a name in a tap, so it is collected separately.
  mapfile -t brew_pkgs   < <(awk -F'\t' '!/^#/ && NF>=3 && $3!="-" && $3!="" && $3 !~ /^local:/ {print $3}' "$REPO/install/packages.tsv")
  mapfile -t brew_local  < <(awk -F'\t' '!/^#/ && NF>=3 && $3 ~ /^local:/ {sub(/^local:/,"",$3); print $3}' "$REPO/install/packages.tsv")
  mapfile -t distro_pkgs < <(awk -F'\t' '!/^#/ && NF>=4 && ($3=="-" || $3=="") && $4!="-" && $4!="" {print $4}' "$REPO/install/packages.tsv")

  if [ "$DRY_RUN" = 1 ]; then
    plan "would install via $PM: ${distro_pkgs[*]}"
    plan "would install via brew: ${brew_pkgs[*]}"
    [ ${#brew_local[@]} -gt 0 ] && plan "would install local formulae: ${brew_local[*]}"
  else
    distro_install "${distro_pkgs[@]}"
    did "distro packages (${#distro_pkgs[@]})"

    if ! command -v brew >/dev/null 2>&1; then
      warn 'brew not found; skipping brew packages'
    else
      brew_install "${brew_pkgs[@]}"
      did "brew packages (${#brew_pkgs[@]})"
      # Local formulae. Homebrew rejects `brew install path/to/x.rb` ("requires
      # formulae to be in a tap"), so copy them into a tap that exists only on
      # this machine. Copying on every run picks up version bumps.
      if [ ${#brew_local[@]} -gt 0 ]; then
        LOCAL_TAP=local/dotfiles
        brew tap | grep -qx "$LOCAL_TAP" || brew tap-new --no-git "$LOCAL_TAP" >/dev/null
        tap_formula_dir="$(brew --repository "$LOCAL_TAP")/Formula"
        mkdir -p "$tap_formula_dir"
        for f in "${brew_local[@]}"; do
          if [ ! -r "$REPO/$f" ]; then
            warn "local formula missing: $REPO/$f"
            continue
          fi
          cp "$REPO/$f" "$tap_formula_dir/"
          name="$(basename "$f" .rb)"
          if brew install "$LOCAL_TAP/$name"; then
            did "brew local: $f"
          else
            warn "brew could not install local formula: $f"
          fi
        done
      fi
    fi
  fi
fi

# --- 3. base directories ------------------------------------------------------

head '[3/7] Base directories'

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

# --- 4. tmux plugin tail ------------------------------------------------------

head '[4/7] tmux plugin manager'

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

# --- 5. deploy ----------------------------------------------------------------

head '[5/7] Deploy (stow)'

# The repo itself is the stow directory and `.` the package. Pointing --dir at
# the repo's parent instead breaks when the repo lives directly in $HOME: stow
# dir and target are then the same, stow skips everything and still exits 0.
STOW_ARGS=(--dir "$REPO" --target "$HOME")

# Plain files already in $HOME, such as the distro's default ~/.bashrc, make
# stow refuse the whole deploy. Ask stow which paths clash, relative to $HOME.
# The two patterns are stow's wording for a plain file and for a symlink that
# stow does not own. The first pattern covers both "is neither a link nor a
# directory" (stow 2.3) and "is not owned by stow"; the second is stow 2.4's
# "cannot stow X over existing target Y since ...".
stow_conflicts() {
  stow --simulate --restow "${STOW_ARGS[@]}" . 2>&1 |
    sed -nE 's/.*existing target is [^:]*: (.+)$/\1/p
              s/.* over existing target (.+) since .*/\1/p' |
    sort -u
}

if ! command -v stow >/dev/null 2>&1; then
  warn 'stow not installed; cannot deploy'
else
  # Move clashing files aside rather than overwrite or adopt them. --adopt
  # would copy their content into the repo over the tracked version.
  mapfile -t clashes < <(stow_conflicts)
  for c in "${clashes[@]}"; do
    bak="$HOME/$c.pre-dotfiles"
    [ -e "$bak" ] && bak="$bak.$(date +%Y%m%d%H%M%S)"
    if [ "$DRY_RUN" = 1 ]; then
      plan "would move ~/$c aside to ${bak#"$HOME"/}"
    else
      mv "$HOME/$c" "$bak"
      did "moved ~/$c aside to ${bak#"$HOME"/}"
    fi
  done

  if [ "$DRY_RUN" = 1 ]; then
    # stow's own simulate mode is more accurate than anything we could print.
    # It still reports the clashes above, which the real run moves first.
    stow --simulate --restow --verbose "${STOW_ARGS[@]}" . 2>&1 | sed 's/^/  /'
  else
    stow --restow "${STOW_ARGS[@]}" .
    did "stowed $REPO -> $HOME"
  fi
fi

# --- 6. fonts -----------------------------------------------------------------

head '[6/7] Fonts'

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

# --- 7. local overrides -------------------------------------------------------

head '[7/7] Local overrides'

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
