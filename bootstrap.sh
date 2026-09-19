#!/usr/bin/env bash
# One-liner installer entry point:
#   curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/bootstrap.sh | bash
#
# Clones shell-setup to the required ~/shell-setup location (if not already
# there) and hands off to the real install.sh. This script has no
# dependencies of its own so it works standalone when piped into bash.
set -euo pipefail

REPO_URL="https://github.com/BlasterM2A/shell-setup.git"
REPO_DIR="$HOME/shell-setup"

if [ -d "$REPO_DIR" ]; then
    echo "[INFO] $REPO_DIR already exists, skipping clone"
else
    echo "[INFO] Cloning shell-setup to $REPO_DIR..."
    git clone "$REPO_URL" "$REPO_DIR"
fi

exec "$REPO_DIR/install.sh"
