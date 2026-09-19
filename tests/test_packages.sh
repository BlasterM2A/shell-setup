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
