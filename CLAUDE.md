# shell-setup

Go CLI/TUI that bootstraps and maintains a zsh environment on Ubuntu/Debian
(zsh, mise, starship, zoxide, fzf, antidote, Nerd Font, AI CLIs). Distributed
as a GitHub Release binary; `install.sh` only downloads it and runs `init`.
See `README.md` for usage and
`docs/superpowers/specs/2026-10-10-shell-setup-cli-design.md` for the design.

## Repo layout

- `main.go` → `internal/cmd` (cobra). `cmd` is the only integration layer: it
  reads flags, builds UI components and binds domain events to them. No
  business logic, no styles.
- `internal/shellsetup` — the whole domain in one package (chezmoi-style):
  `Engine` (`Init`, `Update`, `Doctor`), tool manifests + catalog, backends
  (`apt`, `mise`, `script`, `archive`, `font`), zsh config composition,
  managed files + state. All I/O goes through the `System` interface.
- `internal/shellsetup/registry/*.toml` — one manifest per tool, embedded.
  `registry/files/` holds the config files they ship and the zsh profile.
- `internal/ui` — components (`steplist`, `statustable`, `notice`, `model`).
  `internal/ui/styles` is the ONLY place that defines colors/icons.
- `internal/iostreams`, `internal/log`, `internal/config`, `internal/selfupdate`.
- `install.sh` + `tests/test_install.sh` — bootstrap and its tests.

## Conventions

- Dependency rules are enforced by depguard (`.golangci.yml`): `ui`,
  `iostreams` and `log` never import `shellsetup`/`cmd`; `shellsetup`,
  `selfupdate` and `config` never import `ui`/`iostreams`/`cmd`/`charm.land`.
- Every operation is idempotent. Managed files are never overwritten if the
  user edited them unless `--force`; anything replaced is backed up.
- The domain never prints: it sends `Event`s on a channel and returns a
  `Report`.
- Never run `shell-setup init`/`update` against your own `$HOME` while
  developing (installs packages, chsh). Verify with `task test` and
  `task lint`; manual runs only `doctor`/`--version` with `HOME=$(mktemp -d)`.
- No Docker- or shellcheck-based testing (explicit scope decision).
- The GitHub slug `BlasterM2A/shell-setup` is injected by goreleaser ldflags
  and hardcoded in `install.sh`; update both if the repo moves.

## Making changes

Design changes: update the spec first, then the code. Adding a tool is a new
manifest in `registry/` (plus a backend in Go only if none fits).
