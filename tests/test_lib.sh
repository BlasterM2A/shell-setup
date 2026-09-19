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
