# shell-setup

A personal shell bootstrap tool for Ubuntu/Debian. It installs and wires up:

- zsh (default login shell)
- [starship](https://starship.rs/) prompt
- [antidote](https://github.com/mattmc3/antidote) zsh plugin manager
- [fzf](https://github.com/junegunn/fzf) fuzzy finder
- [zoxide](https://github.com/ajeetdsouza/zoxide) smarter `cd`
- [mise](https://mise.jdx.dev/) runtime version manager
- JetBrainsMono Nerd Font

## Usage on a new machine

One command, no `git clone` required:

```bash
curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
```

`install.sh` is fully self-contained: it installs every tool above, then
downloads the three dotfiles it manages (`.zshrc`, `starship.toml`, the
antidote plugin list) directly from this repo and writes them into place.
Nothing is cloned or left behind on disk beyond those files and the tools
themselves.

During the run, expect two password prompts:

- a **sudo** password prompt, for `apt` package installs
- a **chsh** password prompt, for changing your default login shell to zsh

## After it finishes

1. **Log out and back in.** Restarting your terminal is not enough — changing
   the login shell only takes effect for a new login session.
2. Manually select **"JetBrainsMono Nerd Font"** in your terminal emulator's
   font preferences. `install.sh` installs the font but cannot change your
   terminal's font setting for you.

## Updating

Edit `zsh/zshrc`, `starship/starship.toml`, or `zsh/plugins.txt` in this
repo, commit, and push. On each device, updating is the same one-liner as
installing:

```bash
curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
```

It re-downloads the latest dotfiles (skipping any that are already
up to date) and re-runs the idempotent package installers, so it's always
safe to re-run.

## Development

`install.sh` is the single source of truth for install logic — there's no
separate `scripts/lib.sh`/`scripts/packages.sh` to keep in sync. Tests live
in `tests/test_install.sh` and source `install.sh` directly (sourcing is
guarded so it never runs `main`). Run them with:

```bash
bash tests/test_install.sh
```
