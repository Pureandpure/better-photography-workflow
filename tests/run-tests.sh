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
export BPW_PLIST_CONFIG_FILE="$XDG_CONFIG_HOME/better-photography-workflow/config.plist"
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
(( $# == 20 )) || { print -u2 -- "unexpected osascript argument count: $#"; exit 98; }
count="$(<"$BPW_TEST_OSASCRIPT_COUNT")"
print -r -- $((count + 1)) > "$BPW_TEST_OSASCRIPT_COUNT"
print -r -- "created=4 skipped=0"
MOCK
cat > "$TEST_DIR/mock-bin/rsync" <<'MOCK'
#!/bin/zsh
if [[ -n "${BPW_TEST_RSYNC_CAPTURE:-}" ]]; then
  print -rl -- "$@" > "$BPW_TEST_RSYNC_CAPTURE"
  exit "${BPW_TEST_RSYNC_EXIT:-0}"
fi
print -u2 -- "rsync must not run while backup is disabled"
exit 99
MOCK
chmod +x "$TEST_DIR/mock-bin/osascript" "$TEST_DIR/mock-bin/rsync"
export PATH="$TEST_DIR/mock-bin:$PATH"

if "$ROOT/bin/bpw" init >/dev/null; then pass "bpw init succeeds"; else fail "bpw init succeeds"; fi
assert "config mode is private" test "$(stat -f '%Lp' "$BPW_CONFIG_FILE")" = 600

WORK_DIR="$HOME/Pictures/Photography_Work"
if "$ROOT/bin/bpw" new "猫咪 写真 & 夏日" >/dev/null; then pass "new handles spaces Chinese and metacharacters"; else fail "new handles spaces Chinese and metacharacters"; fi
project="$WORK_DIR/$(date '+%Y')/$(date '+%Y-%m-%d')_猫咪 写真 & 夏日"
assert "project directory exists" test -d "$project"
assert "default media directory exists" test -d "$project/01_MEDIA"
assert "default export directory exists" test -d "$project/05_EXPORTS"
assert "one AppleScript call was made" test "$(sed -n '1p' "$BPW_TEST_OSASCRIPT_COUNT")" = 1
if "$ROOT/bin/bpw" new "猫咪 写真 & 夏日" >/dev/null 2>&1; then fail "existing project is rejected"; else pass "existing project is rejected"; fi
assert "existing project retry creates no reminders" test "$(sed -n '1p' "$BPW_TEST_OSASCRIPT_COUNT")" = 1

if "$ROOT/bin/bpw" scan >/dev/null; then pass "second scan succeeds"; else fail "second scan succeeds"; fi
assert "local state makes scan idempotent" test "$(sed -n '1p' "$BPW_TEST_OSASCRIPT_COUNT")" = 1

dated="2030-01-02_已有日期"
if "$ROOT/bin/bpw" new "$dated" >/dev/null; then pass "pre-dated project is accepted"; else fail "pre-dated project is accepted"; fi
assert "date prefix is not duplicated" test -d "$WORK_DIR/2030/$dated"

mkdir -p "$WORK_DIR/.隐藏项目"
if "$ROOT/bin/bpw" scan >/dev/null; then pass "hidden directory scan succeeds"; else fail "hidden directory scan succeeds"; fi
assert "hidden first-level directory is ignored" test "$(sed -n '1p' "$BPW_TEST_OSASCRIPT_COUNT")" = 2

if "$ROOT/bin/bpw" sync >/dev/null; then pass "disabled backup is a successful no-op"; else fail "disabled backup is a successful no-op"; fi
assert "disabled backup records operation status" grep -q '^outcome=disabled$' "$BPW_STATE_DIR/last-sync.status"
if "$ROOT/bin/bpw" status | grep -q '最近同步：.*disabled'; then pass "status summarizes latest sync"; else fail "status summarizes latest sync"; fi
assert "version command reports 0.4.0" test "$("$ROOT/bin/bpw" version)" = "bpw 0.4.0"

card="$TEST_DIR/A7R5 card"
mkdir -p "$card/DCIM"
print -n -r -- 'fixture original' > "$card/DCIM/DSC0001.ARW"
if "$ROOT/bin/bpw" ingest "$card" --new "旅行 导入 & 测试" --device A7R5 >/dev/null; then pass "CLI ingest creates project and imports"; else fail "CLI ingest creates project and imports"; fi
import_project="$WORK_DIR/$(date '+%Y')/$(date '+%Y-%m-%d')_旅行 导入 & 测试"
assert "ingest preserves source" test "$(cat "$card/DCIM/DSC0001.ARW")" = 'fixture original'
assert "ingest creates stable identity" plutil -extract id raw -o - "$import_project/.bpw-project.json"
import_id="$(plutil -extract id raw -o - "$import_project/.bpw-project.json")"
import_dest="$import_project/01_MEDIA/PHOTO/$(date '+%Y-%m-%d')/A7R5/RAW/DSC0001.ARW"
assert "ingest keeps original filename and device hierarchy" test -f "$import_dest"
assert "import manifest exists" test "$(find "$import_project/.bpw/imports" -name '*.json' | wc -l | tr -d ' ')" = 1
assert "ingest records success" grep -q '^outcome=success$' "$BPW_STATE_DIR/last-ingest.status"
if "$ROOT/bin/bpw" cancel-ingest >/dev/null; then pass "safe cancel command is available"; else fail "safe cancel command is available"; fi
assert "safe cancel requests are persisted for the active engine" test -f "$BPW_STATE_DIR/ingest.cancel"
rm -f "$BPW_STATE_DIR/ingest.cancel"
assert "CLI project show accepts ID" "$ROOT/bin/bpw" project show "$import_id"
if "$ROOT/bin/bpw" ingest "$card" --project "$import_id" --device A7R5 >/dev/null; then pass "duplicate CLI ingest succeeds"; else fail "duplicate CLI ingest succeeds"; fi
assert "duplicate creates no extra media files" test "$(find "$import_project/01_MEDIA" -type f | wc -l | tr -d ' ')" = 1
print -n -r -- 'unknown conflict' > "$import_dest"
if "$ROOT/bin/bpw" ingest "$card" --project "$import_id" --device A7R5 >/dev/null 2>&1; then fail "CLI refuses same-size unknown conflict"; else pass "CLI refuses same-size unknown conflict"; fi
assert "conflict preserves destination" test "$(cat "$import_dest")" = 'unknown conflict'
assert "conflict preserves source" test "$(cat "$card/DCIM/DSC0001.ARW")" = 'fixture original'
if "$ROOT/bin/bpw" ingest "$card" --new "dry-run 不创建" --device A7R5 --dry-run >/dev/null; then pass "CLI dry-run succeeds without choosing project"; else fail "CLI dry-run succeeds without choosing project"; fi
if "$ROOT/bin/bpw" migrate-media-layout --project "$import_id" > "$TEST_DIR/migration-plan.json"; then pass "migration CLI defaults to plan"; else fail "migration CLI defaults to plan"; fi
assert "migration preview does not create reports" test ! -e "$import_project/.bpw/media-layout-migrations"
assert "migration preview retains imported file" test -f "$import_dest"
assert "dry-run creates no project" test ! -e "$WORK_DIR/$(date '+%Y')/$(date '+%Y-%m-%d')_dry-run 不创建"
assert "workspace list succeeds" "$ROOT/bin/bpw" workspace list
if "$ROOT/bin/bpw" ingest "$WORK_DIR" --project "$import_id" >/dev/null 2>&1; then fail "CLI rejects workspace as source"; else pass "CLI rejects workspace as source"; fi
# Existing project-list ordering assertions remain scoped to the original two projects.
mv "$import_project" "$TEST_DIR/retained imported project"

projects_json="$TEST_DIR/projects.json"
if "$ROOT/bin/bpw" projects list > "$projects_json"; then pass "projects list emits JSON"; else fail "projects list emits JSON"; fi
projects_plist="$TEST_DIR/projects.plist"
if plutil -convert xml1 -o "$projects_plist" "$projects_json" >/dev/null 2>&1; then pass "projects list output is valid JSON"; else fail "projects list output is valid JSON"; fi
assert "projects list includes real project directories" test "$(plutil -extract 0.directoryName raw -o - "$projects_json")" = "${project:t}"
assert "new project starts at ingest" test "$(plutil -extract 0.currentStageID raw -o - "$projects_json")" = ingest
mkdir -p "$project/01_MEDIA/2000-01-01/Pocket3" "$project/01_MEDIA/2000-01-01/A7R5"
if "$ROOT/bin/bpw" projects set-stage "$project" edit >/dev/null; then pass "project stage can be persisted"; else fail "project stage can be persisted"; fi
if "$ROOT/bin/bpw" projects set-favorite "$project" true >/dev/null; then pass "project favorite can be persisted"; else fail "project favorite can be persisted"; fi
"$ROOT/bin/bpw" projects list > "$projects_json"
assert "persisted project stage is returned" test "$(plutil -extract 0.currentStageID raw -o - "$projects_json")" = edit
assert "persisted project favorite is returned" test "$(plutil -extract 0.isFavorite raw -o - "$projects_json")" = true
assert "project devices are inferred from source hierarchy" test "$(plutil -extract 0.deviceNames raw -o - "$projects_json")" = 2
if "$ROOT/bin/bpw" projects set-stage "$TEST_DIR" done >/dev/null 2>&1; then fail "project state rejects paths outside WORK_DIR"; else pass "project state rejects paths outside WORK_DIR"; fi
app_bundle="$TEST_DIR/摄影工作流.app"
mkdir -p "$app_bundle"
cat > "$TEST_DIR/mock-bin/open" <<'MOCK'
#!/bin/zsh
print -r -- "$1" > "$BPW_TEST_OPENED_APP"
MOCK
chmod +x "$TEST_DIR/mock-bin/open"
export BPW_TEST_OPENED_APP="$TEST_DIR/opened-app"
if BPW_APP_BUNDLE="$app_bundle" "$ROOT/bin/bpw" app >/dev/null; then pass "app command opens configured bundle"; else fail "app command opens configured bundle"; fi
assert "app command opens the expected bundle" test "$(sed -n '1p' "$BPW_TEST_OPENED_APP")" = "$app_bundle"
unset BPW_TEST_OPENED_APP

chmod 666 "$BPW_CONFIG_FILE"
if "$ROOT/bin/bpw" status >/dev/null 2>&1; then fail "unsafe config permissions are rejected"; else pass "unsafe config permissions are rejected"; fi
chmod 600 "$BPW_CONFIG_FILE"

exported_config="$TEST_DIR/exported-config.json"
if "$ROOT/bin/bpw" config export > "$exported_config"; then pass "config export emits JSON"; else fail "config export emits JSON"; fi
normalized_config="$TEST_DIR/exported-config.plist"
if plutil -convert xml1 -o "$normalized_config" "$exported_config"; then pass "exported config is valid JSON"; else fail "exported config is valid JSON"; fi
plutil -replace REMINDER_LIST_NAME -string '图形界面测试列表' "$normalized_config"
if "$ROOT/bin/bpw" config apply "$normalized_config" >/dev/null; then pass "config apply accepts validated plist"; else fail "config apply accepts validated plist"; fi
assert "plist config is private" test "$(stat -f '%Lp' "$BPW_PLIST_CONFIG_FILE")" = 600
assert "applied plist config becomes effective" test "$("$ROOT/bin/bpw" config export | plutil -extract REMINDER_LIST_NAME raw -o - -)" = '图形界面测试列表'
assert "config path reports canonical plist" test "$("$ROOT/bin/bpw" config path)" = "$BPW_PLIST_CONFIG_FILE"

source "$ROOT/lib/common.sh"
bpw_load_config >/dev/null 2>&1
if print -r -- '/dev/disk9s1 on /Volumes/摄影 SSD (apfs, local, nodev)' | bpw_mount_table_contains '/Volumes/摄影 SSD'; then pass "exact mounted volume with spaces is recognized"; else fail "exact mounted volume with spaces is recognized"; fi
if print -r -- '/dev/disk9s1 on /Volumes/摄影 SSD 2 (apfs, local, nodev)' | bpw_mount_table_contains '/Volumes/摄影 SSD'; then fail "different mount point is rejected"; else pass "different mount point is rejected"; fi

active_lock="$BPW_STATE_DIR/test-active.lock"
if bpw_acquire_lock "$active_lock" test; then pass "first lock acquisition succeeds"; else fail "first lock acquisition succeeds"; fi
if bpw_acquire_lock "$active_lock" test; then fail "active lock is preserved"; else pass "active lock is preserved"; fi
assert "owned lock releases cleanly" bpw_release_lock "$active_lock"
fresh_lock="$BPW_STATE_DIR/test-fresh.lock"
mkdir "$fresh_lock"
if bpw_acquire_lock "$fresh_lock" test; then fail "fresh ownerless lock is preserved"; else pass "fresh ownerless lock is preserved"; fi
assert "fresh ownerless lock remains intact" test -d "$fresh_lock"
rmdir "$fresh_lock"
stale_lock="$BPW_STATE_DIR/test-stale.lock"
mkdir "$stale_lock"
{
  print -r -- 'pid=99999999'
  print -r -- 'identity=stale-process'
} > "$stale_lock/owner"
if bpw_acquire_lock "$stale_lock" test; then pass "stale lock is recovered"; else fail "stale lock is recovered"; fi
assert "recovered lock releases cleanly" bpw_release_lock "$stale_lock"

fake_volume="$TEST_DIR/fake-volume"
safe_destination="$fake_volume/Photography/Projects"
mkdir -p "$fake_volume"
if bpw_prepare_destination_within_volume "$fake_volume" "$safe_destination"; then pass "safe backup destination is prepared"; else fail "safe backup destination is prepared"; fi
if bpw_prepare_destination_within_volume "$fake_volume" "$TEST_DIR/outside-volume" >/dev/null 2>&1; then fail "backup destination outside volume is rejected"; else pass "backup destination outside volume is rejected"; fi
escape_target="$TEST_DIR/escape-target"
mkdir -p "$escape_target"
ln -s "$escape_target" "$fake_volume/Escape"
if bpw_prepare_destination_within_volume "$fake_volume" "$fake_volume/Escape/Projects" >/dev/null 2>&1; then fail "backup symlink escape is rejected"; else pass "backup symlink escape is rejected"; fi

export BPW_TEST_RSYNC_CAPTURE="$TEST_DIR/rsync-args"
export BPW_TEST_RSYNC_EXIT=0
if bpw_run_rsync "$WORK_DIR" "$safe_destination" false >/dev/null; then pass "safe rsync invocation succeeds"; else fail "safe rsync invocation succeeds"; fi
if grep -qx -- '--delete' "$BPW_TEST_RSYNC_CAPTURE"; then fail "safe rsync omits delete"; else pass "safe rsync omits delete"; fi
if bpw_run_rsync "$WORK_DIR" "$safe_destination" true >/dev/null; then pass "delete-enabled rsync invocation succeeds"; else fail "delete-enabled rsync invocation succeeds"; fi
assert "delete-enabled rsync passes delete" grep -qx -- '--delete' "$BPW_TEST_RSYNC_CAPTURE"
export BPW_TEST_RSYNC_EXIT=23
if bpw_run_rsync "$WORK_DIR" "$safe_destination" false >/dev/null; then fail "rsync exit 23 is propagated"; else
  assert "rsync exit 23 is propagated" test $? = 23
fi
unset BPW_TEST_RSYNC_CAPTURE BPW_TEST_RSYNC_EXIT

rotation_log="$BPW_LOG_DIR/rotation-test.log"
original_main_log="$BPW_MAIN_LOG"
BPW_MAIN_LOG="$rotation_log"
print -r -- 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-padding' > "$rotation_log"
BPW_LOG_MAX_BYTES=32
bpw_log INFO "rotation trigger" >/dev/null
assert "oversized log is rotated" test -f "$rotation_log.1"
BPW_MAIN_LOG="$original_main_log"
BPW_LOG_MAX_BYTES=1048576
watch_plist="$TEST_DIR/watch.plist"
if bpw_render_launchd_plist "$ROOT/launchd/com.better-photography-workflow.watch.plist.template" "$watch_plist" 300 "$ROOT/bin/bpw" && plutil -lint "$watch_plist" >/dev/null; then
  pass "rendered launchd plist is valid"
else
  fail "rendered launchd plist is valid"
fi

if osacompile -o "$TEST_DIR/reminders.scpt" "$ROOT/scripts/create-reminders.applescript" >/dev/null 2>&1; then pass "AppleScript compiles"; else fail "AppleScript compiles"; fi

if grep -R -E --exclude=run-tests.sh --exclude=design-qa.md --exclude='design-qa-*.png' --exclude-dir=.git --exclude-dir=.build --exclude-dir=dist '/Users/[A-Za-z0-9._-]+' "$ROOT" >/dev/null 2>&1; then fail "source contains no hard-coded user home"; else pass "source contains no hard-coded user home"; fi

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
print -r -- '# rollback-preserve-sentinel' >> "$BPW_INSTALL_ROOT/README.md"
cat > "$TEST_DIR/mock-bin/launchctl" <<'MOCK'
#!/bin/zsh
if [[ "${1:-}" == bootstrap && "${3:-}" == *com.better-photography-workflow.sync.plist ]]; then exit 7; fi
exit 0
MOCK
chmod +x "$TEST_DIR/mock-bin/launchctl"
if "$ROOT/install.sh" >/dev/null 2>&1; then fail "installer reports service reload failure"; else pass "installer reports service reload failure"; fi
assert "failed update restores previous installation" grep -q 'rollback-preserve-sentinel' "$BPW_INSTALL_ROOT/README.md"
cat > "$TEST_DIR/mock-bin/launchctl" <<'MOCK'
#!/bin/zsh
exit 0
MOCK
chmod +x "$TEST_DIR/mock-bin/launchctl"
if "$BPW_BIN_DIR/bpw" doctor >/dev/null; then pass "doctor passes in isolated valid installation"; else fail "doctor passes in isolated valid installation"; fi
if "$BPW_BIN_DIR/bpw" logs >/dev/null; then pass "logs command succeeds"; else fail "logs command succeeds"; fi
if "$BPW_BIN_DIR/bpw" uninstall >/dev/null; then pass "default uninstall succeeds"; else fail "default uninstall succeeds"; fi
assert "default uninstall preserves config" test -f "$BPW_CONFIG_FILE"
if [[ ! -e "$BPW_BIN_DIR/bpw" ]]; then pass "uninstall removes CLI"; else fail "uninstall removes CLI"; fi

print -r -- "$passed passed, $failed failed"
(( failed == 0 ))
