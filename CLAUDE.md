# shell-setup

Personal Ubuntu/Debian shell bootstrap tool. Installs and wires up zsh,
starship, antidote, fzf, zoxide, mise, and a Nerd Font, then symlinks
dotfiles from this repo into `$HOME`. See `README.md` for user-facing usage.

## Repo layout

- `install.sh` — orchestrator entry point. Sources `scripts/lib.sh` and
  `scripts/packages.sh`, never contains installer logic itself.
- `bootstrap.sh` — standalone, dependency-free entry point for the
  curl-pipe one-liner. Clones the repo to `~/shell-setup` if missing, then
  execs `install.sh`. Keep it dependency-free — it must work before the
  rest of the repo exists on disk.
- `scripts/lib.sh` — generic helpers (`log_info`/`log_warn`/`log_error`,
  `is_installed`, `backup_if_exists`, `symlink_dotfile`). No package- or
  tool-specific logic here.
- `scripts/packages.sh` — one idempotent `install_<tool>()` function per
  tool, plus `install_all_packages()`. Every installer must check
  `is_installed` (or an equivalent) before acting.
- `zsh/zshrc`, `zsh/plugins.txt`, `starship/starship.toml` — the actual
  dotfiles, symlinked into `$HOME` by `install.sh`. `zsh/zshrc` hardcodes
  `$HOME/shell-setup` as the antidote plugin path — this repo **must** be
  cloned to exactly `~/shell-setup`.
- `tests/` — lightweight bash assertion scripts (no framework, no Docker).
  Run with `bash tests/test_lib.sh` / `bash tests/test_packages.sh`.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — the design
  spec and implementation plan this repo was built from (via Claude's
  superpowers brainstorming/writing-plans/subagent-driven-development
  skills). Read the spec before making a design-level change; it's the
  binding source of truth over the plan.

## Conventions

- Every install/config step must be **idempotent** — safe to re-run.
  Installers check `command -v` (or a directory/file existence check)
  before acting; `symlink_dotfile` backs up anything pre-existing that
  isn't already the expected symlink.
- `install.sh` runs under `set -euo pipefail`. Don't swallow errors.
- No Docker-based or shellcheck-based testing in this repo (explicit
  scope decision, see the spec's "Fuera de alcance" section) — verify
  changes with `bash -n`/`zsh -n` syntax checks and the existing test
  scripts.
- Curl-pipe installs (starship, zoxide, mise) use `-fsSL` so an HTTP
  error doesn't get silently piped into `sh`/`bash`.
- Never run `./install.sh` or call `main` for real while iterating in an
  agent session — it installs system packages, downloads a font, and
  changes the login shell (`chsh`). Verify with syntax checks and by
  sourcing the scripts to confirm functions resolve, not by executing it.

## Making changes

For anything beyond a one-line fix, follow the existing spec → plan
pattern: update `docs/superpowers/specs/2026-09-19-shell-setup-design.md`
first if the change affects a design decision, then reflect it in code.
Small, self-contained fixes (typos, a missing apt dependency, a stale
comment) don't need a new spec entry.
