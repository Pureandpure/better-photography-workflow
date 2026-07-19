#!/bin/zsh
set -u

ROOT="${0:A:h:h}"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bpw-tests.XXXXXX")" || exit 1
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM HUP

passed=0
failed=0
pass() { print -r -- "ok - $*"; passed=$((passed + 1)); }
fail() { print -r -- "not ok - $*"; failed=$((failed + 1)); }
assert() {
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

export HOME="$TEST_DIR/home with spaces 中文"
export XDG_CONFIG_HOME="$HOME/config area"
export XDG_STATE_HOME="$HOME/state area"
export XDG_DATA_HOME="$HOME/data area"
export BPW_CONFIG_FILE="$XDG_CONFIG_HOME/better-photography-workflow/config"
export BPW_STATE_DIR="$XDG_STATE_HOME/better-photography-workflow"
export BPW_LOG_DIR="$BPW_STATE_DIR/logs"
export BPW_MAIN_LOG="$BPW_LOG_DIR/bpw.log"
export BPW_INSTALL_ROOT="$XDG_DATA_HOME/better-photography-workflow"
export BPW_ROOT="$ROOT"
mkdir -p "$HOME" "$TEST_DIR/mock-bin"

export BPW_TEST_OSASCRIPT_COUNT="$TEST_DIR/osascript-count"
print -r -- 0 > "$BPW_TEST_OSASCRIPT_COUNT"
cat > "$TEST_DIR/mock-bin/osascript" <<'MOCK'
#!/bin/zsh
if [[ "${1:-}" == "-e" ]]; then exit 0; fi
(( $# == 18 )) || { print -u2 -- "unexpected osascript argument count: $#"; exit 98; }
count="$(<"$BPW_TEST_OSASCRIPT_COUNT")"
print -r -- $((count + 1)) > "$BPW_TEST_OSASCRIPT_COUNT"
print -r -- "created=4 skipped=0"
MOCK
cat > "$TEST_DIR/mock-bin/rsync" <<'MOCK'
#!/bin/zsh
print -u2 -- "rsync must not run while backup is disabled"
exit 99
MOCK
chmod +x "$TEST_DIR/mock-bin/osascript" "$TEST_DIR/mock-bin/rsync"
export PATH="$TEST_DIR/mock-bin:$PATH"

if "$ROOT/bin/bpw" init >/dev/null; then pass "bpw init succeeds"; else fail "bpw init succeeds"; fi
assert "config mode is private" test "$(stat -f '%Lp' "$BPW_CONFIG_FILE")" = 600

WORK_DIR="$HOME/Pictures/Photography_Work"
if "$ROOT/bin/bpw" new "猫咪 写真 & 夏日" >/dev/null; then pass "new handles spaces Chinese and metacharacters"; else fail "new handles spaces Chinese and metacharacters"; fi
project="$WORK_DIR/$(date '+%Y-%m-%d')_猫咪 写真 & 夏日"
assert "project directory exists" test -d "$project"
assert "default RAW directory exists" test -d "$project/01_RAW"
assert "default export directory exists" test -d "$project/02_EXPORT"
assert "one AppleScript call was made" test "$(<"$BPW_TEST_OSASCRIPT_COUNT")" = 1
if "$ROOT/bin/bpw" new "猫咪 写真 & 夏日" >/dev/null 2>&1; then fail "existing project is rejected"; else pass "existing project is rejected"; fi
assert "existing project retry creates no reminders" test "$(<"$BPW_TEST_OSASCRIPT_COUNT")" = 1

if "$ROOT/bin/bpw" scan >/dev/null; then pass "second scan succeeds"; else fail "second scan succeeds"; fi
assert "local state makes scan idempotent" test "$(<"$BPW_TEST_OSASCRIPT_COUNT")" = 1

dated="2030-01-02_已有日期"
if "$ROOT/bin/bpw" new "$dated" >/dev/null; then pass "pre-dated project is accepted"; else fail "pre-dated project is accepted"; fi
assert "date prefix is not duplicated" test -d "$WORK_DIR/$dated"

mkdir -p "$WORK_DIR/.隐藏项目"
if "$ROOT/bin/bpw" scan >/dev/null; then pass "hidden directory scan succeeds"; else fail "hidden directory scan succeeds"; fi
assert "hidden first-level directory is ignored" test "$(<"$BPW_TEST_OSASCRIPT_COUNT")" = 2

if "$ROOT/bin/bpw" sync >/dev/null; then pass "disabled backup is a successful no-op"; else fail "disabled backup is a successful no-op"; fi

chmod 666 "$BPW_CONFIG_FILE"
if "$ROOT/bin/bpw" status >/dev/null 2>&1; then fail "unsafe config permissions are rejected"; else pass "unsafe config permissions are rejected"; fi
chmod 600 "$BPW_CONFIG_FILE"

source "$ROOT/lib/common.sh"
bpw_load_config >/dev/null 2>&1
if print -r -- '/dev/disk9s1 on /Volumes/摄影 SSD (apfs, local, nodev)' | bpw_mount_table_contains '/Volumes/摄影 SSD'; then pass "exact mounted volume with spaces is recognized"; else fail "exact mounted volume with spaces is recognized"; fi
if print -r -- '/dev/disk9s1 on /Volumes/摄影 SSD 2 (apfs, local, nodev)' | bpw_mount_table_contains '/Volumes/摄影 SSD'; then fail "different mount point is rejected"; else pass "different mount point is rejected"; fi
watch_plist="$TEST_DIR/watch.plist"
if bpw_render_launchd_plist "$ROOT/launchd/com.better-photography-workflow.watch.plist.template" "$watch_plist" 300 "$ROOT/bin/bpw" && plutil -lint "$watch_plist" >/dev/null; then
  pass "rendered launchd plist is valid"
else
  fail "rendered launchd plist is valid"
fi

if osacompile -o "$TEST_DIR/reminders.scpt" "$ROOT/scripts/create-reminders.applescript" >/dev/null 2>&1; then pass "AppleScript compiles"; else fail "AppleScript compiles"; fi

if grep -R -E --exclude=run-tests.sh '/Users/[A-Za-z0-9._-]+' "$ROOT" >/dev/null 2>&1; then fail "source contains no hard-coded user home"; else pass "source contains no hard-coded user home"; fi

cat > "$TEST_DIR/mock-bin/launchctl" <<'MOCK'
#!/bin/zsh
exit 0
MOCK
chmod +x "$TEST_DIR/mock-bin/launchctl"
export BPW_BIN_DIR="$HOME/custom bin"
print -r -- '# install-preserve-sentinel' >> "$BPW_CONFIG_FILE"
if "$ROOT/install.sh" >/dev/null; then pass "installer succeeds in isolated HOME"; else fail "installer succeeds in isolated HOME"; fi
assert "installer preserves existing config" grep -q 'install-preserve-sentinel' "$BPW_CONFIG_FILE"
assert "installer creates executable CLI" test -x "$BPW_BIN_DIR/bpw"
assert "installer renders watch LaunchAgent" plutil -lint "$HOME/Library/LaunchAgents/com.better-photography-workflow.watch.plist"
if "$BPW_BIN_DIR/bpw" doctor >/dev/null; then pass "doctor passes in isolated valid installation"; else fail "doctor passes in isolated valid installation"; fi
if "$BPW_BIN_DIR/bpw" logs >/dev/null; then pass "logs command succeeds"; else fail "logs command succeeds"; fi
if "$BPW_BIN_DIR/bpw" uninstall >/dev/null; then pass "default uninstall succeeds"; else fail "default uninstall succeeds"; fi
assert "default uninstall preserves config" test -f "$BPW_CONFIG_FILE"
if [[ ! -e "$BPW_BIN_DIR/bpw" ]]; then pass "uninstall removes CLI"; else fail "uninstall removes CLI"; fi

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
