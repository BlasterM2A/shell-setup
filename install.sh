#!/usr/bin/env bash
# shell-setup bootstrap: installs the shell-setup binary from the latest
# GitHub release (checksum verified) and runs `shell-setup init`.
#   curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
set -euo pipefail

REPO="BlasterM2A/shell-setup"
BIN_DIR="${SHELL_SETUP_BIN_DIR:-$HOME/.local/bin}"
STATE_DIR="${SHELL_SETUP_STATE_DIR:-$HOME/.local/state/shell-setup}"
OS_RELEASE="${SHELL_SETUP_OS_RELEASE:-/etc/os-release}"
RELEASE_BASE="${SHELL_SETUP_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"
STAMP_FILE="$STATE_DIR/bootstrap.sha256"

log() { printf '\033[1;34m•\033[0m %s\n' "$1"; }
die() {
    printf '\033[1;31m✗\033[0m %s\n' "$1" >&2
    exit 1
}

check_os() {
    [ -f "$OS_RELEASE" ] || die "Cannot detect the OS: $OS_RELEASE not found. Ubuntu/Debian only."
    local ids
    ids="$(. "$OS_RELEASE" && echo "${ID:-} ${ID_LIKE:-}")"
    case " $ids " in
        *" debian "* | *" ubuntu "*) ;;
        *) die "Unsupported OS (${ids% }). shell-setup supports Ubuntu/Debian only." ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

install_binary() {
    local arch="$1" asset tmp expected
    asset="shell-setup_linux_${arch}.tar.gz"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/checksums.txt" "$RELEASE_BASE/checksums.txt" ||
        { rm -rf "$tmp"; die "Could not download checksums.txt"; }
    expected="$(grep " ${asset}\$" "$tmp/checksums.txt" || true)"
    [ -n "$expected" ] || { rm -rf "$tmp"; die "No checksum for $asset in the latest release"; }

    if [ -x "$BIN_DIR/shell-setup" ] && [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$expected" ]; then
        rm -rf "$tmp"
        log "shell-setup is already up to date"
        return 0
    fi

    log "Downloading $asset..."
    curl -fsSL -o "$tmp/$asset" "$RELEASE_BASE/$asset" || { rm -rf "$tmp"; die "Could not download $asset"; }
    (cd "$tmp" && printf '%s\n' "$expected" | sha256sum -c --status) ||
        { rm -rf "$tmp"; die "Checksum verification failed for $asset"; }
    tar -xzf "$tmp/$asset" -C "$tmp" shell-setup
    mkdir -p "$BIN_DIR" "$STATE_DIR"
    install -m 0755 "$tmp/shell-setup" "$BIN_DIR/shell-setup"
    printf '%s\n' "$expected" > "$STAMP_FILE"
    rm -rf "$tmp"
    log "Installed $BIN_DIR/shell-setup"
}

# Short alias: shs → shell-setup. A real file named shs is never replaced.
link_alias() {
    local alias="$BIN_DIR/shs"
    if [ -e "$alias" ] && [ ! -L "$alias" ]; then
        log "$alias exists and is not a link; skipping the shs alias"
        return 0
    fi
    ln -sfn shell-setup "$alias"
}

main() {
    check_os
    local arch
    arch="$(detect_arch)"
    install_binary "$arch"
    link_alias
    # With `curl | bash`, stdin is the pipe: give init the real terminal.
    if (: </dev/tty) 2>/dev/null; then
        exec "$BIN_DIR/shell-setup" init </dev/tty
    fi
    exec "$BIN_DIR/shell-setup" init --plain
}

# Only run main when executed (./install.sh, bash install.sh, curl | bash),
# not when sourced by tests.
if ! (return 0 2>/dev/null); then
    main "$@"
fi
