# shell-setup

A personal shell bootstrap tool for Ubuntu/Debian. It installs and wires up:

- zsh (default login shell)
- [starship](https://starship.rs/) prompt
- [antidote](https://github.com/mattmc3/antidote) zsh plugin manager
- [fzf](https://github.com/junegunn/fzf) fuzzy finder
- [zoxide](https://github.com/ajeetdsouza/zoxide) smarter `cd`
- [mise](https://mise.jdx.dev/) runtime version manager
- JetBrainsMono Nerd Font

## Important: clone location

This repo **must be cloned to exactly `~/shell-setup`**. `zsh/zshrc` loads
antidote plugins with a hardcoded path
(`antidote load "$HOME/shell-setup/zsh/plugins.txt"`), so anything other than
`~/shell-setup` will break plugin loading.

## Usage on a new machine

One-liner (clones the repo to `~/shell-setup` if it's not there yet, then
runs `install.sh`):

```bash
curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/bootstrap.sh | bash
```

Or manually:

```bash
git clone https://github.com/BlasterM2A/shell-setup.git ~/shell-setup
cd ~/shell-setup
./install.sh
```

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

Edit files in this repo, then:

```bash
git push
```

On other machines, `git pull`. Since `~/.zshrc` and the starship config are
symlinked into this repo, most changes (aliases, prompt config, plugin list)
take effect immediately in new shells. Re-run `./install.sh` only if you
added a new package to install.
