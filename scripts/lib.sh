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
