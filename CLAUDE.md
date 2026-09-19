# shell-setup

Personal Ubuntu/Debian shell bootstrap tool. Installs and wires up zsh,
starship, antidote, fzf, zoxide, mise, and a Nerd Font, then writes dotfiles
from this repo into `$HOME`. See `README.md` for user-facing usage.

## Repo layout

- `install.sh` — the entire tool. Single self-contained script: logging
  helpers, `is_installed`, `fetch_dotfile`, one idempotent `install_<tool>()`
  function per tool, `install_all_packages()`, OS detection, and the
  orchestration (`main`). No `scripts/` directory, no sibling files it
  depends on — it must work standalone when piped directly into `bash`
  (`curl -fsSL .../install.sh | bash`), so never add a `source` of another
  local file to it.
- `zsh/zshrc`, `zsh/plugins.txt`, `starship/starship.toml` — the source of
  truth for the dotfiles. `install.sh` downloads these three files directly
  from `raw.githubusercontent.com` at run time (via `fetch_dotfile`) and
  writes them to `~/.zshrc`, `~/.config/starship.toml`, and
  `~/.config/shell-setup/plugins.txt` — there is **no `git clone`** on the
  target machine, ever. `zsh/zshrc`'s antidote line points at that fixed
  `~/.config/shell-setup/plugins.txt` path, not at this repo's own location.
- `tests/test_install.sh` — sources `install.sh` (guarded so sourcing never
  runs `main`) and exercises its functions against stubs (fake `curl`,
  `apt-get`, `git`, `mise` binaries on `PATH`) — no network, no real
  installs.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — the design spec
  and implementation plan this repo was built from (via Claude's superpowers
  brainstorming/writing-plans/subagent-driven-development skills). Read the
  spec before making a design-level change; it's the binding source of
  truth over the plan. Note: the spec describes an earlier git-clone-based
  architecture in places — the "no clone" design in this file and the
  current code supersedes that; update the spec if you touch that section.

## Conventions

- Every install/config step must be **idempotent** — safe to re-run.
  Installers check `command -v` (or a directory/file existence check)
  before acting; `fetch_dotfile` compares downloaded content against the
  existing target (`cmp -s`) and only backs up + overwrites when it
  actually changed.
- `install.sh` runs under `set -euo pipefail`. Don't swallow errors.
- No Docker-based or shellcheck-based testing in this repo (explicit scope
  decision) — verify changes with `bash -n`/`zsh -n` syntax checks and
  `bash tests/test_install.sh`.
- Curl-pipe installs (starship, zoxide, mise, the dotfiles themselves) use
  `-fsSL` so an HTTP error doesn't get silently piped into `sh`/`bash` or
  written as a dotfile's content.
- Never run `./install.sh` (or call `main`) for real while iterating in an
  agent session — it installs system packages, downloads a font, and
  changes the login shell (`chsh`). Verify with syntax checks and by
  sourcing `install.sh` (which the test file already does safely) to
  confirm functions resolve, not by executing it.
- `install.sh` hardcodes its own GitHub raw-content URL
  (`REPO_RAW_BASE`) to fetch the dotfiles from. If the repo is ever
  renamed, forked, or moved, that constant must be updated — there's no
  way to infer it from a local clone since there isn't one.

## Making changes

For anything beyond a one-line fix, follow the existing spec → plan
pattern: update `docs/superpowers/specs/2026-09-19-shell-setup-design.md`
first if the change affects a design decision, then reflect it in code.
Small, self-contained fixes (typos, a missing apt dependency, a stale
comment) don't need a new spec entry.
