#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../install.sh"

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

# --- is_installed ---

assert_true "is_installed detects an existing command (bash)" is_installed bash
assert_false "is_installed reports a missing command" is_installed definitely_not_a_real_command_xyz

# --- fetch_dotfile (stubbed curl, no network) ---

FAKE_BIN="$TMPDIR/fakebin"
mkdir -p "$FAKE_BIN"
DOTFILE_CONTENT_V1="line one"
DOTFILE_CONTENT_V2="line one changed"
CURRENT_CONTENT_FILE="$TMPDIR/current-content"
echo "$DOTFILE_CONTENT_V1" > "$CURRENT_CONTENT_FILE"
cat > "$FAKE_BIN/curl" <<EOS
#!/usr/bin/env bash
# fake curl: -o <target> as last two significant args, ignores the URL,
# writes back whatever is in \$CURRENT_CONTENT_FILE
out=""
prev=""
for arg in "\$@"; do
    if [ "\$prev" = "-o" ]; then
        out="\$arg"
    fi
    prev="\$arg"
done
cat "$CURRENT_CONTENT_FILE" > "\$out"
EOS
chmod +x "$FAKE_BIN/curl"
PATH="$FAKE_BIN:$PATH"

TARGET="$TMPDIR/fetched-dotfile"

PATH="$FAKE_BIN:$PATH" fetch_dotfile "http://example.invalid/dotfile" "$TARGET"
assert_eq "$DOTFILE_CONTENT_V1" "$(cat "$TARGET")" "fetch_dotfile writes new content when target doesn't exist"

# idempotency: re-fetching identical content makes no backup
PATH="$FAKE_BIN:$PATH" fetch_dotfile "http://example.invalid/dotfile" "$TARGET"
BACKUP_COUNT="$(find "$TMPDIR" -maxdepth 1 -name 'fetched-dotfile.bak.*' | wc -l)"
assert_eq "0" "$BACKUP_COUNT" "fetch_dotfile is idempotent (no backup when content unchanged)"

# changed content: backs up the old version, writes the new one
echo "$DOTFILE_CONTENT_V2" > "$CURRENT_CONTENT_FILE"
PATH="$FAKE_BIN:$PATH" fetch_dotfile "http://example.invalid/dotfile" "$TARGET"
BACKUP_COUNT_2="$(find "$TMPDIR" -maxdepth 1 -name 'fetched-dotfile.bak.*' | wc -l)"
assert_eq "1" "$BACKUP_COUNT_2" "fetch_dotfile backs up the old version when content changed"
assert_eq "$DOTFILE_CONTENT_V2" "$(cat "$TARGET")" "fetch_dotfile writes the updated content"

# --- apt_install_if_missing ---

cat > "$TMPDIR/apt-get" <<'EOS'
#!/usr/bin/env bash
echo "$@" >> "$CALL_LOG_PATH"
EOS
chmod +x "$TMPDIR/apt-get"
export CALL_LOG_PATH="$TMPDIR/apt-get-calls.log"
export APT_CMD="$TMPDIR/apt-get"

apt_install_if_missing bash fake-bash-package
if [ -f "$CALL_LOG_PATH" ]; then
    echo "FAIL: apt_install_if_missing called apt-get for an already-installed command"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: apt_install_if_missing skips an already-installed command"
fi

apt_install_if_missing definitely_not_a_real_command_xyz fake-missing-package
if grep -q "install -y fake-missing-package" "$CALL_LOG_PATH" 2>/dev/null; then
    echo "PASS: apt_install_if_missing installs a missing command via apt-get"
else
    echo "FAIL: apt_install_if_missing did not call apt-get install for a missing command"
    FAILURES=$((FAILURES + 1))
fi

# --- install_antidote idempotency ---

GIT_CALLED_FILE="$TMPDIR/git-called"
cat > "$FAKE_BIN/git" <<EOS
#!/usr/bin/env bash
touch "$GIT_CALLED_FILE"
EOS
chmod +x "$FAKE_BIN/git"
FAKE_HOME="$TMPDIR/home"
mkdir -p "$FAKE_HOME/.antidote"
PATH="$FAKE_BIN:$PATH" HOME="$FAKE_HOME" install_antidote
if [ -f "$GIT_CALLED_FILE" ]; then
    echo "FAIL: install_antidote invoked git clone when antidote dir already exists"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: install_antidote skips cloning when antidote dir already exists"
fi

# --- install_nerd_font idempotency (regression: grep -q + pipefail SIGPIPE) ---
#
# `fc-list | grep -qi ...` can make fc-list exit via SIGPIPE once grep -q
# finds its match and stops reading, and under `set -o pipefail` that
# non-zero exit fails the whole pipeline even though grep matched — so the
# idempotency check always looked "not installed". This test uses a large
# fake fc-list output so the same SIGPIPE condition reproduces reliably.

cat > "$FAKE_BIN/fc-list" <<'EOS'
#!/usr/bin/env bash
for i in $(seq 1 5000); do
    echo "/fake/font-$i.ttf: Fake Font $i:style=Regular"
done
echo "/fake/JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font:style=Regular"
EOS
chmod +x "$FAKE_BIN/fc-list"
NERD_FONT_CURL_CALLED_FILE="$TMPDIR/nerd-font-curl-called"
cat > "$FAKE_BIN/curl" <<EOS
#!/usr/bin/env bash
touch "$NERD_FONT_CURL_CALLED_FILE"
EOS
chmod +x "$FAKE_BIN/curl"
(set -o pipefail; PATH="$FAKE_BIN:$PATH" install_nerd_font)
if [ -f "$NERD_FONT_CURL_CALLED_FILE" ]; then
    echo "FAIL: install_nerd_font re-downloaded despite fc-list already listing it (pipefail/SIGPIPE regression)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: install_nerd_font skips download when fc-list already lists it, even under pipefail"
fi

# --- install_mise idempotency ---

cat > "$FAKE_BIN/mise" <<'EOS'
#!/usr/bin/env bash
echo "fake mise $@"
EOS
chmod +x "$FAKE_BIN/mise"
CURL_CALLED_FILE="$TMPDIR/mise-curl-called"
cat > "$FAKE_BIN/curl" <<EOS
#!/usr/bin/env bash
touch "$CURL_CALLED_FILE"
EOS
chmod +x "$FAKE_BIN/curl"
PATH="$FAKE_BIN:$PATH" install_mise
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
