# Shell Setup Clip Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a git-versioned, idempotent bootstrap tool (`install.sh` + dotfiles) that installs and configures a zsh + starship + antidote shell stack on any Ubuntu/Debian machine.

**Architecture:** A small library of pure bash helper functions (`scripts/lib.sh`, `scripts/packages.sh`) is tested in isolation with lightweight assertion scripts (no test framework, no Docker). `install.sh` orchestrates those helpers: detect OS, install missing packages, symlink dotfiles from the repo into `$HOME` (backing up anything pre-existing), set zsh as the default shell, and print a verification summary.

**Tech Stack:** bash, zsh, starship, antidote, fzf, zoxide, mise, apt, curl.

**Spec:** `docs/superpowers/specs/2026-09-19-shell-setup-design.md`

## Global Constraints

- Target OS: Ubuntu/Debian-based only — `install.sh` must detect and abort cleanly otherwise (spec: Pasos del `install.sh`, step 1).
- Every install step must be idempotent — safe to re-run without reinstalling or duplicating backups (spec: Idempotencia).
- Any pre-existing dotfile that isn't already a symlink to this repo must be backed up with a timestamp before being replaced (spec: Idempotencia, Manejo de errores).
- `install.sh` runs under `set -euo pipefail` (spec: Manejo de errores).
- No Docker-based or shellcheck-based testing in this iteration (spec: Fuera de alcance).
- No migration of existing `.bashrc` content beyond the 3 aliases `ll`, `la`, `l` (spec: Decisiones).
- Plugin manager is antidote; plugins are `zsh-users/zsh-autosuggestions` and `zsh-users/zsh-syntax-highlighting` (spec: Decisiones, `.zshrc`).
- Nerd Font install (JetBrainsMono) is automatic; font *selection* in the terminal app stays a manual step the script must print at the end (spec: Nerd Font).
- mise is installed and activated in `.zshrc` (`eval "$(mise activate zsh)"`); no global tool versions are predefined (spec: Decisiones, mise).

---

## File Structure

```
shell-setup/
├── install.sh                 # orchestrator: OS check, packages, symlinks, chsh, summary
├── scripts/
│   ├── lib.sh                 # log/is_installed/backup_if_exists/symlink_dotfile
│   └── packages.sh            # per-tool install functions, all idempotent
├── zsh/
│   ├── zshrc                  # -> ~/.zshrc
│   └── plugins.txt            # antidote plugin list
├── starship/
│   └── starship.toml          # -> ~/.config/starship.toml
└── tests/
    ├── test_lib.sh            # assertion-style tests for scripts/lib.sh
    └── test_packages.sh       # assertion-style tests for scripts/packages.sh
```

---

### Task 1: Shared helpers (`scripts/lib.sh`)

**Files:**
- Create: `scripts/lib.sh`
- Test: `tests/test_lib.sh`

**Interfaces:**
- Produces: `log_info(msg)`, `log_warn(msg)`, `log_error(msg)` (print to stdout/stderr, no return value used); `is_installed(cmd)` (returns 0/1 via exit status); `backup_if_exists(target, source)` (renames `target` to `target.bak.<timestamp>` if it's a regular file/dir, removes a stale symlink if `target` is a symlink not already pointing at `source`, no-ops if `target` already points at `source`); `symlink_dotfile(source, target)` (calls `backup_if_exists`, then `mkdir -p` the parent dir and `ln -sf source target`).
- Consumes: nothing (no dependency on earlier tasks).

- [ ] **Step 1: Write the failing test**

Create `tests/test_lib.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib.sh"

FAILURES=0

assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc (expected '$expected', got '$actual')"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_true() {
    local desc="$1"
    shift
    if "$@"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_false() {
    local desc="$1"
    shift
    if "$@"; then
        echo "FAIL: $desc"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_true "is_installed detects an existing command (bash)" is_installed bash
assert_false "is_installed reports a missing command" is_installed definitely_not_a_real_command_xyz

# symlink_dotfile creates a new symlink when target doesn't exist
SOURCE_FILE="$TMPDIR/source.txt"
echo "hello" > "$SOURCE_FILE"
TARGET_FILE="$TMPDIR/target.txt"
symlink_dotfile "$SOURCE_FILE" "$TARGET_FILE"
assert_eq "$SOURCE_FILE" "$(readlink -f "$TARGET_FILE")" "symlink_dotfile points target at source"

# backup_if_exists backs up a pre-existing regular file before symlinking
EXISTING_FILE="$TMPDIR/existing.txt"
echo "old content" > "$EXISTING_FILE"
SOURCE2="$TMPDIR/source2.txt"
echo "new content" > "$SOURCE2"
symlink_dotfile "$SOURCE2" "$EXISTING_FILE"
BACKUP_COUNT="$(find "$TMPDIR" -maxdepth 1 -name 'existing.txt.bak.*' | wc -l)"
assert_eq "1" "$BACKUP_COUNT" "backup_if_exists creates exactly one backup of a pre-existing file"
assert_eq "$SOURCE2" "$(readlink -f "$EXISTING_FILE")" "symlink_dotfile replaces the backed-up file with a symlink"

# idempotency: re-running symlink_dotfile does not create a second backup
symlink_dotfile "$SOURCE2" "$EXISTING_FILE"
BACKUP_COUNT_2="$(find "$TMPDIR" -maxdepth 1 -name 'existing.txt.bak.*' | wc -l)"
assert_eq "1" "$BACKUP_COUNT_2" "re-running symlink_dotfile is idempotent (no new backup)"

if [ "$FAILURES" -eq 0 ]; then
    echo "All tests passed."
    exit 0
else
    echo "$FAILURES test(s) failed."
    exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_lib.sh`
Expected: FAIL — `scripts/lib.sh: No such file or directory` (the file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/lib.sh`:

```bash
#!/usr/bin/env bash
# shell-setup helpers: logging, install checks, backup, symlink

log_info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$1"
}

log_warn() {
    printf '\033[1;33m[WARN]\033[0m %s\n' "$1"
}

log_error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$1" >&2
}

is_installed() {
    command -v "$1" >/dev/null 2>&1
}

backup_if_exists() {
    local target="$1"
    local source="$2"

    if [ -L "$target" ]; then
        if [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
            return 0
        fi
        rm "$target"
        log_warn "Removed stale symlink at $target"
        return 0
    fi

    if [ -e "$target" ]; then
        local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
        mv "$target" "$backup"
        log_warn "Backed up existing $target to $backup"
    fi
}

symlink_dotfile() {
    local source="$1"
    local target="$2"
    backup_if_exists "$target" "$source"
    mkdir -p "$(dirname "$target")"
    ln -sf "$source" "$target"
    log_info "Symlinked $target -> $source"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_lib.sh`
Expected: PASS — `All tests passed.` with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib.sh tests/test_lib.sh
git commit -m "Add shell-setup helper library with tests"
```

---

### Task 2: Dotfile content (`zsh/zshrc`, `zsh/plugins.txt`, `starship/starship.toml`)

**Files:**
- Create: `zsh/zshrc`
- Create: `zsh/plugins.txt`
- Create: `starship/starship.toml`

**Interfaces:**
- Consumes: nothing (static config, no dependency on Task 1's shell functions — sourced by the user's real zsh session, not by `install.sh`).
- Produces: the exact file paths `link_dotfiles()` in Task 4 will symlink from (`$REPO_DIR/zsh/zshrc`, `$REPO_DIR/starship/starship.toml`).

- [ ] **Step 1: Create the antidote plugin list**

Create `zsh/plugins.txt`:

```
zsh-users/zsh-autosuggestions
zsh-users/zsh-syntax-highlighting
```

- [ ] **Step 2: Create the zshrc**

Create `zsh/zshrc`:

```bash
# ~/.zshrc — managed by shell-setup, do not edit ~/.zshrc directly.
# Edit files in ~/shell-setup instead, then `git push` to share the change.

# --- antidote plugin manager ---
ANTIDOTE_DIR="$HOME/.antidote"
if [ -f "$ANTIDOTE_DIR/antidote.zsh" ]; then
    source "$ANTIDOTE_DIR/antidote.zsh"
    antidote load "$HOME/shell-setup/zsh/plugins.txt"
fi

# --- prompt ---
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# --- fzf ---
if command -v fzf >/dev/null 2>&1; then
    source <(fzf --zsh)
fi

# --- zoxide ---
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

# --- aliases (migrated from ~/.bashrc) ---
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"
```

- [ ] **Step 3: Create the starship preset**

Create `starship/starship.toml`:

```toml
# Minimal starship preset — directory, git, language, command duration.
# Requires a Nerd Font for icons to render correctly.

format = """
$directory\
$git_branch\
$git_status\
$nodejs\
$python\
$rust\
$golang\
$cmd_duration\
$line_break\
$character"""

[directory]
style = "cyan bold"
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "
style = "purple bold"

[git_status]
style = "red bold"

[nodejs]
symbol = " "
style = "green bold"

[python]
symbol = " "
style = "yellow bold"

[rust]
symbol = " "
style = "red bold"

[golang]
symbol = " "
style = "cyan bold"

[cmd_duration]
min_time = 2000
format = "took [$duration]($style) "
style = "yellow bold"

[character]
success_symbol = "[❯](green bold)"
error_symbol = "[❯](red bold)"
```

- [ ] **Step 4: Verify syntax**

Run: `bash -c 'command -v zsh >/dev/null && zsh -n zsh/zshrc && echo "zshrc syntax OK" || echo "zsh not installed on this machine yet, skipping syntax check"'`
Expected: `zshrc syntax OK` (or the skip message if zsh isn't installed on the dev machine yet — not a failure, since Task 4/5 install zsh).

Run: `python3 -c "import tomllib; tomllib.load(open('starship/starship.toml', 'rb')); print('starship.toml syntax OK')"`
Expected: `starship.toml syntax OK`. (If `tomllib` is unavailable because Python is older than 3.11, this step is informational only — skip it and move on.)

- [ ] **Step 5: Commit**

```bash
git add zsh/zshrc zsh/plugins.txt starship/starship.toml
git commit -m "Add zsh, antidote, and starship dotfile content"
```

---

### Task 3: Package installers (`scripts/packages.sh`)

**Files:**
- Create: `scripts/packages.sh`
- Test: `tests/test_packages.sh`
- Modify: `zsh/zshrc:20-25` (add mise activation block, between the zoxide block and the aliases)

**Interfaces:**
- Consumes: `log_info`, `log_warn`, `is_installed` from `scripts/lib.sh` (Task 1).
- Produces: `install_all_packages()` (calls every installer below in order); `install_git`, `install_curl`, `install_zsh`, `install_fzf`, `install_starship`, `install_zoxide`, `install_mise`, `install_antidote`, `install_nerd_font` (each idempotent, no args); `NERD_FONT_NAME` (string constant, consumed by `print_summary` in Task 4).

- [ ] **Step 1: Write the failing test**

Create `tests/test_packages.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib.sh"
source "$SCRIPT_DIR/../scripts/packages.sh"

FAILURES=0
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Stub apt-get so tests never touch the real package manager.
cat > "$TMPDIR/apt-get" <<'EOS'
#!/usr/bin/env bash
echo "$@" >> "$CALL_LOG_PATH"
EOS
chmod +x "$TMPDIR/apt-get"
export CALL_LOG_PATH="$TMPDIR/apt-get-calls.log"
export APT_CMD="$TMPDIR/apt-get"

# apt_install_if_missing skips apt-get when the command is already present
apt_install_if_missing bash fake-bash-package
if [ -f "$CALL_LOG_PATH" ]; then
    echo "FAIL: apt_install_if_missing called apt-get for an already-installed command"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: apt_install_if_missing skips an already-installed command"
fi

# apt_install_if_missing calls apt-get install when the command is missing
apt_install_if_missing definitely_not_a_real_command_xyz fake-missing-package
if grep -q "install -y fake-missing-package" "$CALL_LOG_PATH" 2>/dev/null; then
    echo "PASS: apt_install_if_missing installs a missing command via apt-get"
else
    echo "FAIL: apt_install_if_missing did not call apt-get install for a missing command"
    FAILURES=$((FAILURES + 1))
fi

# install_antidote skips cloning when ~/.antidote-equivalent already exists
FAKE_HOME="$TMPDIR/home"
mkdir -p "$FAKE_HOME/.antidote"
HOME="$FAKE_HOME" install_antidote
echo "PASS: install_antidote does not error when antidote dir already exists"

# install_mise skips installation when mise is already present
PATH_WITH_FAKE_MISE="$TMPDIR/fakebin:$PATH"
mkdir -p "$TMPDIR/fakebin"
cat > "$TMPDIR/fakebin/mise" <<'EOS'
#!/usr/bin/env bash
echo "fake mise $@"
EOS
chmod +x "$TMPDIR/fakebin/mise"
CURL_CALLED_FILE="$TMPDIR/curl-called"
cat > "$TMPDIR/fakebin/curl" <<EOS
#!/usr/bin/env bash
touch "$CURL_CALLED_FILE"
EOS
chmod +x "$TMPDIR/fakebin/curl"
PATH="$PATH_WITH_FAKE_MISE" install_mise
if [ -f "$CURL_CALLED_FILE" ]; then
    echo "FAIL: install_mise invoked curl when mise was already installed"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: install_mise skips installation when mise is already present"
fi

if [ "$FAILURES" -eq 0 ]; then
    echo "All tests passed."
    exit 0
else
    echo "$FAILURES test(s) failed."
    exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_packages.sh`
Expected: FAIL — `scripts/packages.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/packages.sh`:

```bash
#!/usr/bin/env bash
# shell-setup package installers — every function is idempotent.

APT_CMD="${APT_CMD:-sudo apt-get}"
NERD_FONT_DIR="${NERD_FONT_DIR:-$HOME/.local/share/fonts}"
NERD_FONT_NAME="JetBrainsMono Nerd Font"

apt_install_if_missing() {
    local cmd="$1"
    local package="$2"
    if is_installed "$cmd"; then
        log_info "$cmd already installed, skipping"
        return 0
    fi
    log_info "Installing $package via apt..."
    $APT_CMD update -qq
    $APT_CMD install -y "$package"
}

install_git() { apt_install_if_missing git git; }
install_curl() { apt_install_if_missing curl curl; }
install_zsh() { apt_install_if_missing zsh zsh; }
install_fzf() { apt_install_if_missing fzf fzf; }

install_starship() {
    if is_installed starship; then
        log_info "starship already installed, skipping"
        return 0
    fi
    log_info "Installing starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
}

install_zoxide() {
    if is_installed zoxide; then
        log_info "zoxide already installed, skipping"
        return 0
    fi
    log_info "Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
}

install_antidote() {
    local antidote_dir="$HOME/.antidote"
    if [ -d "$antidote_dir" ]; then
        log_info "antidote already installed, skipping"
        return 0
    fi
    log_info "Installing antidote..."
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$antidote_dir"
}

install_mise() {
    if is_installed mise; then
        log_info "mise already installed, skipping"
        return 0
    fi
    log_info "Installing mise..."
    curl https://mise.run | sh
}

install_nerd_font() {
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
        log_info "JetBrainsMono Nerd Font already installed, skipping"
        return 0
    fi
    log_info "Installing JetBrainsMono Nerd Font..."
    local tmp_zip
    tmp_zip="$(mktemp)"
    curl -sSL -o "$tmp_zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    mkdir -p "$NERD_FONT_DIR"
    unzip -oq "$tmp_zip" -d "$NERD_FONT_DIR"
    rm -f "$tmp_zip"
    fc-cache -f "$NERD_FONT_DIR" >/dev/null
    log_info "Nerd Font installed. Remember to select '$NERD_FONT_NAME' in your terminal preferences."
}

install_all_packages() {
    install_git
    install_curl
    install_zsh
    install_fzf
    install_starship
    install_zoxide
    install_mise
    install_antidote
    install_nerd_font
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_packages.sh`
Expected: PASS — `All tests passed.` with exit code 0.

- [ ] **Step 5: Add mise activation to zshrc**

Edit `zsh/zshrc`, inserting a mise block between the zoxide block and the aliases block (so the file reads, in order: antidote, prompt, fzf, zoxide, mise, aliases, PATH):

```bash
# --- zoxide ---
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

# --- mise (runtime version manager) ---
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi

# --- aliases (migrated from ~/.bashrc) ---
```

Run: `bash -c 'command -v zsh >/dev/null && zsh -n zsh/zshrc && echo "zshrc syntax OK" || echo "zsh not installed on this machine yet, skipping syntax check"'`
Expected: `zshrc syntax OK` (or the skip message — not a failure).

- [ ] **Step 6: Commit**

```bash
git add scripts/packages.sh tests/test_packages.sh zsh/zshrc
git commit -m "Add idempotent package installers with tests, wire up mise"
```

---

### Task 4: Orchestrator (`install.sh`)

**Files:**
- Create: `install.sh`

**Interfaces:**
- Consumes: `log_info`, `log_warn`, `log_error`, `is_installed`, `symlink_dotfile` from `scripts/lib.sh` (Task 1); `install_all_packages`, `NERD_FONT_NAME` from `scripts/packages.sh` (Task 3); `zsh/zshrc`, `starship/starship.toml` paths from Task 2.
- Produces: the `install.sh` entry point end users run (`./install.sh`).

- [ ] **Step 1: Write install.sh**

Create `install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/packages.sh"

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS: /etc/os-release not found. This script supports Ubuntu/Debian only."
        exit 1
    fi
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
        *debian*)
            log_info "Detected Debian-based OS ($PRETTY_NAME)"
            ;;
        *)
            log_error "Unsupported OS: $PRETTY_NAME. This script supports Ubuntu/Debian only."
            exit 1
            ;;
    esac
}

link_dotfiles() {
    symlink_dotfile "$REPO_DIR/zsh/zshrc" "$HOME/.zshrc"
    symlink_dotfile "$REPO_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
}

set_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [ "${SHELL:-}" = "$zsh_path" ]; then
        log_info "zsh is already the default shell, skipping"
        return 0
    fi
    log_info "Changing default shell to zsh..."
    chsh -s "$zsh_path"
}

print_summary() {
    echo ""
    log_info "shell-setup complete. Versions installed:"
    for cmd in zsh starship fzf zoxide; do
        if is_installed "$cmd"; then
            echo "  - $cmd: $($cmd --version | head -n1)"
        else
            log_error "  - $cmd: NOT FOUND"
        fi
    done
    echo ""
    log_warn "Restart your terminal, then manually select '$NERD_FONT_NAME' as the terminal font."
}

main() {
    check_os
    install_all_packages
    link_dotfiles
    set_default_shell
    print_summary
}

main "$@"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n install.sh`
Expected: no output, exit code 0 (syntax is valid; this does not execute the script).

- [ ] **Step 4: Verify sourcing works end-to-end without executing side effects**

Run:
```bash
bash -c '
REPO_DIR="$(pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/packages.sh"
type install_all_packages >/dev/null && echo "install_all_packages defined: OK"
type symlink_dotfile >/dev/null && echo "symlink_dotfile defined: OK"
'
```
Expected: both `OK` lines printed, no errors — confirms `install.sh`'s sourced dependencies resolve correctly.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "Add install.sh orchestrator wiring OS check, packages, dotfiles, and shell change"
```

> **Note for the human running this plan:** `install.sh` installs system packages, downloads a font, and changes your login shell (`chsh`). Do not run `./install.sh` for real as part of implementing this plan — that's a deliberate, separate action you take when you're ready to actually convert this machine. This task only verifies the script is syntactically correct and its functions resolve; it does not execute `main`.

---

## Self-Review Notes

- **Spec coverage:** OS detection (Task 4), package install list incl. zoxide, mise, and Nerd Font (Task 3), dotfile symlinking with backup (Task 1 + Task 4), antidote plugin wiring (Task 2's `zshrc` + Task 3's `install_antidote`), mise install + activation (Task 3), `chsh` default shell change (Task 4), idempotency (Task 1 + Task 3 tests), error handling via `set -euo pipefail` (Task 4), final verification summary (Task 4), migrated aliases (Task 2), starship minimal preset (Task 2), Nerd Font manual-selection reminder (Task 3 + Task 4) — all covered. Docker/shellcheck testing, global mise tool versions, and other dotfiles/Claude Code config are explicitly out of scope per the spec and are not tasked here.
- **Placeholder scan:** no TBD/TODO, no "add error handling" hand-waving — every step has literal code.
- **Type/name consistency:** `symlink_dotfile(source, target)` signature matches between Task 1's definition and Task 4's calls; `install_all_packages` and `NERD_FONT_NAME` match between Task 3's definition and Task 4's usage; `APT_CMD` and `CALL_LOG_PATH` env seams match between Task 3's implementation and its test.
