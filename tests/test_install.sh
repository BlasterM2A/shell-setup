#!/usr/bin/env bash
# Tests for the install.sh bootstrap. No network: curl and uname are stubbed
# and a fake release (tarball + checksums.txt) is served from a temp dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/fakebin"
export FAKE_RELEASE_DIR="$TMP/release"
mkdir -p "$FAKE_BIN" "$FAKE_RELEASE_DIR" "$TMP/build"

# Fake release: a tarball per arch containing a fake shell-setup binary.
printf '#!/bin/sh\necho fake-shell-setup "$@"\n' > "$TMP/build/shell-setup"
chmod +x "$TMP/build/shell-setup"
for arch in amd64 arm64; do
    tar -czf "$FAKE_RELEASE_DIR/shell-setup_linux_${arch}.tar.gz" -C "$TMP/build" shell-setup
done
(cd "$FAKE_RELEASE_DIR" && sha256sum shell-setup_linux_*.tar.gz > checksums.txt)

# Fake curl: copies $FAKE_RELEASE_DIR/<basename of URL> to the -o target.
cat > "$FAKE_BIN/curl" <<'EOS'
#!/usr/bin/env bash
out="" url="" prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ]; then out="$arg"; elif [[ "$arg" != -* ]]; then url="$arg"; fi
    prev="$arg"
done
cp "$FAKE_RELEASE_DIR/$(basename "$url")" "$out"
EOS
cat > "$FAKE_BIN/uname" <<'EOS'
#!/usr/bin/env bash
echo "${FAKE_ARCH:-x86_64}"
EOS
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/uname"
export PATH="$FAKE_BIN:$PATH"

export SHELL_SETUP_BIN_DIR="$TMP/bin"
export SHELL_SETUP_STATE_DIR="$TMP/state"
export SHELL_SETUP_RELEASE_BASE="https://example.invalid/download"
export SHELL_SETUP_OS_RELEASE="$TMP/os-release"

source "$SCRIPT_DIR/../install.sh"
set +e # install.sh enables -e; assertions must keep running

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
    if "$@"; then echo "PASS: $desc"; else echo "FAIL: $desc"; FAILURES=$((FAILURES + 1)); fi
}

assert_false() {
    local desc="$1"
    shift
    if "$@"; then echo "FAIL: $desc"; FAILURES=$((FAILURES + 1)); else echo "PASS: $desc"; fi
}

# --- detect_arch ---
assert_eq "amd64" "$(export FAKE_ARCH=x86_64; detect_arch)" "x86_64 maps to amd64"
assert_eq "arm64" "$(export FAKE_ARCH=aarch64; detect_arch)" "aarch64 maps to arm64"
assert_false "unsupported arch fails" bash -c "export FAKE_ARCH=mips64; source '$SCRIPT_DIR/../install.sh'; detect_arch" 2>/dev/null

# --- check_os ---
printf 'ID=ubuntu\nID_LIKE=debian\n' > "$SHELL_SETUP_OS_RELEASE"
assert_true "ubuntu is supported" check_os
printf 'ID=fedora\n' > "$SHELL_SETUP_OS_RELEASE"
assert_false "fedora is rejected" bash -c "source '$SCRIPT_DIR/../install.sh'; check_os" 2>/dev/null
printf 'ID=ubuntu\nID_LIKE=debian\n' > "$SHELL_SETUP_OS_RELEASE"

# --- install_binary ---
assert_true "installs the binary" bash -c "source '$SCRIPT_DIR/../install.sh'; install_binary amd64" >/dev/null
assert_eq "fake-shell-setup --version" "$("$SHELL_SETUP_BIN_DIR/shell-setup" --version)" "installed binary runs"

second="$(bash -c "source '$SCRIPT_DIR/../install.sh'; install_binary amd64")"
assert_true "re-run skips the download" grep -q "already up to date" <<<"$second"

# --- link_alias ---
assert_true "links the alias" bash -c "source '$SCRIPT_DIR/../install.sh'; link_alias" >/dev/null
assert_eq "shell-setup" "$(readlink "$SHELL_SETUP_BIN_DIR/shs")" "alias is a relative link to shell-setup"
assert_eq "fake-shell-setup --version" "$("$SHELL_SETUP_BIN_DIR/shs" --version)" "alias runs the binary"
assert_true "re-linking is idempotent" bash -c "source '$SCRIPT_DIR/../install.sh'; link_alias" >/dev/null
assert_eq "shell-setup" "$(readlink "$SHELL_SETUP_BIN_DIR/shs")" "alias unchanged after re-link"
rm -f "$SHELL_SETUP_BIN_DIR/shs"
printf '#!/bin/sh\necho mine\n' > "$SHELL_SETUP_BIN_DIR/shs"
chmod +x "$SHELL_SETUP_BIN_DIR/shs"
bash -c "source '$SCRIPT_DIR/../install.sh'; link_alias" >/dev/null 2>&1
assert_eq "mine" "$("$SHELL_SETUP_BIN_DIR/shs")" "a real file named shs is left alone"
rm -f "$SHELL_SETUP_BIN_DIR/shs"

# A corrupted checksum must abort and leave no new binary behind.
rm -f "$SHELL_SETUP_BIN_DIR/shell-setup" "$SHELL_SETUP_STATE_DIR/bootstrap.sha256"
sed -i "s/^[0-9a-f]*/$(printf '0%.0s' $(seq 64))/" "$FAKE_RELEASE_DIR/checksums.txt"
assert_false "bad checksum aborts" bash -c "source '$SCRIPT_DIR/../install.sh'; install_binary amd64" 2>/dev/null
assert_false "no binary after a bad checksum" test -e "$SHELL_SETUP_BIN_DIR/shell-setup"

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed"
    exit 1
fi
echo "All tests passed"
