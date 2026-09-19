#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_DIR/scripts/lib.sh"
source "$REPO_DIR/scripts/packages.sh"

export PATH="$HOME/.local/bin:$PATH"

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS: /etc/os-release not found. This script supports Ubuntu/Debian only."
        exit 1
    fi
    . /etc/os-release
    PRETTY_NAME="${PRETTY_NAME:-unknown}"
    ID="${ID:-unknown}"
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
    if ! chsh -s "$zsh_path" 2>/dev/null; then
        log_warn "chsh failed (no password set for PAM auth is common on SSH-key-only accounts), retrying with sudo..."
        sudo chsh -s "$zsh_path" "$(whoami)"
    fi
}

print_summary() {
    echo ""
    log_info "shell-setup complete. Versions installed:"
    local failures=0
    for cmd in zsh starship fzf zoxide mise; do
        if is_installed "$cmd"; then
            echo "  - $cmd: $($cmd --version | head -n1)"
        else
            log_error "  - $cmd: NOT FOUND"
            failures=$((failures + 1))
        fi
    done
    if [ -d "$HOME/.antidote" ]; then
        echo "  - antidote: installed"
    else
        log_error "  - antidote: NOT FOUND"
        failures=$((failures + 1))
    fi
    echo ""
    log_warn "Log out and back in, then manually select '$NERD_FONT_NAME' as the terminal font."
    if [ "$failures" -gt 0 ]; then
        log_error "shell-setup failed: $failures tool(s) missing after installation."
        exit 1
    fi
}

main() {
    check_os
    install_all_packages
    link_dotfiles
    set_default_shell
    print_summary
}

main "$@"
