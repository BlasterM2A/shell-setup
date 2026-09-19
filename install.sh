#!/usr/bin/env bash
# shell-setup — one-shot installer, no git clone required on the target
# machine. Safe to run directly:
#   curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

REPO_RAW_BASE="https://raw.githubusercontent.com/BlasterM2A/shell-setup/master"
CONFIG_DIR="$HOME/.config/shell-setup"
APT_CMD="${APT_CMD:-sudo apt-get}"
NERD_FONT_DIR="${NERD_FONT_DIR:-$HOME/.local/share/fonts}"
NERD_FONT_NAME="JetBrainsMono Nerd Font"

# --- logging ---

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

# --- dotfile fetch (content-based, no symlinks, no local repo) ---

fetch_dotfile() {
    local url="$1"
    local target="$2"
    local tmp
    tmp="$(mktemp)"
    curl -fsSL -o "$tmp" "$url"
    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
        log_info "$target already up to date, skipping"
        rm -f "$tmp"
        return 0
    fi
    if [ -e "$target" ]; then
        local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
        mv "$target" "$backup"
        log_warn "Backed up existing $target to $backup"
    fi
    mkdir -p "$(dirname "$target")"
    mv "$tmp" "$target"
    log_info "Installed $target"
}

# --- package installers (every function is idempotent) ---

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
install_unzip() { apt_install_if_missing unzip unzip; }
install_fontconfig() { apt_install_if_missing fc-cache fontconfig; }

install_starship() {
    if is_installed starship; then
        log_info "starship already installed, skipping"
        return 0
    fi
    log_info "Installing starship..."
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$HOME/.local/bin"
}

install_zoxide() {
    if is_installed zoxide; then
        log_info "zoxide already installed, skipping"
        return 0
    fi
    log_info "Installing zoxide..."
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
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
    else
        log_info "Installing mise..."
        curl -fsSL https://mise.run | sh
    fi
    mise settings set auto_update true
}

install_nerd_font() {
    if fc-list 2>/dev/null | grep -i "JetBrainsMono Nerd Font" >/dev/null; then
        log_info "JetBrainsMono Nerd Font already installed, skipping"
        return 0
    fi
    log_info "Installing JetBrainsMono Nerd Font..."
    local tmp_zip
    tmp_zip="$(mktemp)"
    curl -fsSL -o "$tmp_zip" \
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
    install_unzip
    install_fontconfig
    install_nerd_font
}

# --- orchestration ---

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

install_dotfiles() {
    fetch_dotfile "$REPO_RAW_BASE/zsh/zshrc" "$HOME/.zshrc"
    fetch_dotfile "$REPO_RAW_BASE/starship/starship.toml" "$HOME/.config/starship.toml"
    fetch_dotfile "$REPO_RAW_BASE/zsh/plugins.txt" "$CONFIG_DIR/plugins.txt"
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
    install_dotfiles
    set_default_shell
    print_summary
}

# Only run main when executed directly (./install.sh, bash install.sh, or
# curl | bash) — not when sourced by tests.
if ! (return 0 2>/dev/null); then
    main "$@"
fi
