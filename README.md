# dotfiles

One branch, two platforms. The repo root mirrors `$HOME`, so the same tree is
deployed by `stow` on Linux and by junctions + environment variables on Windows.

```
.
├── .config/             XDG config, shared by both platforms
│   ├── git/             config (tracked) + config.local (gitignored)
│   ├── nvim/            Neovim 0.12, vim.pack + a small lazy-loading harness
│   ├── tmux/            shared conf; plugin tail swapped per platform
│   └── starship.toml    reached by $STARSHIP_CONFIG, not linked
├── .bashrc              Linux shell
├── .bash_profile
├── powershell/          Windows shell; dot-sourced by a stub at $PROFILE
│   ├── profile.ps1
│   └── functions/       ll, envup, navigation (cb/cl/n/fvim/gvim), dev
├── komorebi/            Windows WM; reached by $KOMOREBI_CONFIG_HOME
├── install/
│   └── packages.tsv     one manifest, columns for scoop / brew / distro
├── bootstrap.ps1        Windows
└── bootstrap.sh         Linux
```

## Install

Both bootstraps take a dry-run flag. Use it first — they print every change
they would make and touch nothing.

**Windows** (PowerShell, no admin required):

```powershell
git clone <url> ~\home\.dotfiles
cd ~\home\.dotfiles
.\bootstrap.ps1 -DryRun
.\bootstrap.ps1
```

**Linux:**

```bash
git clone <url> ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh --dry-run
./bootstrap.sh
```

Both are idempotent — re-run after pulling.

## How deployment works

| | Linux | Windows |
|---|---|---|
| Mechanism | `stow` | directory junctions + env vars |
| Target | `$HOME` | `%USERPROFILE%` |
| Held back | `.stow-local-ignore` | `$LinuxOnlyConfig` in bootstrap.ps1 |

**Windows uses no symlinks and needs no admin.** Unprivileged symlinks require
Developer Mode, which is not always available on a managed machine. Directory
junctions never need privileges, so every directory under `.config/` is
junctioned into `%USERPROFILE%\.config`. Loose *files* can't be junctioned, so
they're reached by environment variable instead:

| Thing | How it's found |
|---|---|
| `.config/*/` | junction into `%USERPROFILE%\.config` |
| `.config/starship.toml` | `$STARSHIP_CONFIG` |
| `komorebi/` | `$KOMOREBI_CONFIG_HOME`, `$WHKD_CONFIG_HOME` |
| `powershell/profile.ps1` | one-line stub at `$PROFILE` that dot-sources it |
| `.config/git/config` | `$XDG_CONFIG_HOME` **and** an include stub at `~/.gitconfig` |

No hardlinks anywhere. A hardlink is a second directory entry to one inode, and
any editor that saves by writing a temp file and renaming it silently breaks the
link — leaving two files that look connected but aren't. Stubs can't break that
way.

`%USERPROFILE%` is the Windows deploy target rather than `$HOME` because that's
where the ecosystem already writes: 32 of 36 dotdirs live there. `$HOME`
(`~\home`) is a *workspace* root and is deliberately left alone.

### Why `~/.config` must be a real directory

Both bootstraps create `~/.config` before deploying. If it doesn't exist, stow
folds the tree and links `~/.config` itself at the repo — so every tool that
writes into its own config directory writes into the git tree. That is exactly
how `startup.log`, `.nvimlog`, `scoop/config.json`, `uv-receipt.json` and
`git/gitk` all ended up tracked. Keeping the parent real means only the
per-tool subdirectories are links, and tool-written state stays out of git.

## Machine-local overrides

Anything with a credential, a proxy or an absolute path belongs in a
`.local` file. All are gitignored; the bootstraps create them empty.

| File | For |
|---|---|
| `.config/git/config.local` | identity, credential helper |
| `~/.bashrc.local` | project shortcuts, PATH additions |
| `powershell/profile.local.ps1` | the same, on Windows |

## Packages

`install/packages.tsv` is the single manifest, with a column per package
manager. Linux needs two sources: **Homebrew on Linux ships no GUI or
display-server packages**, so i3, fonts and anything X/Wayland must come from
the distro, while the CLI tools come from brew to match the scoop versions on
Windows.

Fonts are not tracked as binaries. Windows installs CommitMono Nerd Font from
the scoop `nerd-fonts` bucket; Linux uses [`getnf`](https://github.com/getnf/getnf).

`komorebi/applications.json` is likewise not tracked — it is 62 KB of upstream
data that `komorebic fetch-app-specific-configuration` regenerates, and
bootstrap.ps1 fetches it.

## tmux / psmux

psmux reads the same `tmux.conf` as tmux, so the 219 shared lines are one file.
Only the plugin tail differs, and the bootstraps select it by copying
`plugins.{windows,linux}.conf` to the gitignored `plugins.conf`. The split is a
file swap rather than an `if-shell` so it doesn't depend on psmux implementing
that command.

One asymmetry worth knowing: psmux copies to the system clipboard natively, so
its plugin file adds nothing for that. tmux doesn't, so `plugins.linux.conf`
wires `y`/`Enter` to `wl-copy` or `xclip` by hand.

## Line endings

`core.autocrlf` is true on Windows, which would check `bootstrap.sh` out with
CRLF and break its shebang on Linux (`bad interpreter: /bin/bash^M`).
`.gitattributes` pins shell scripts and Unix-read configs to LF.

## Branches

`main` is the only branch, and carries both platforms. Per-OS branches were
tried and abandoned: they diverged on files that have nothing to do with the
operating system (the Neovim config had been rewritten on one side only), so
every shared improvement needed cherry-picking by hand. Platform differences
belong in the two bootstrap scripts and in `has('win32')`-style guards, not in
parallel histories.

Recovery tags, in case anything on the old branches is worth reviving:

| Tag | What it holds |
|---|---|
| `pre-cleanup` | this repo immediately before the restructure |
| `abandoned/arch` | the Arch/sway branch |
| `abandoned/master` | the previous trunk |
