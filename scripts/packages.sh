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
        return 0
    fi
    log_info "Installing mise..."
    curl -fsSL https://mise.run | sh
}

install_nerd_font() {
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
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
