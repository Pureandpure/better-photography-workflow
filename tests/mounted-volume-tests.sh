#!/bin/zsh
# Opt-in integration test: creates and detaches only its own disposable disk images.
set -eu
ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d /private/tmp/bpw-mounted.XXXXXX)"
WORK_MOUNT=""
BACKUP_MOUNT=""
cleanup() {
  [[ -n "$WORK_MOUNT" ]] && hdiutil detach "$WORK_MOUNT" >/dev/null 2>&1 || true
  [[ -n "$BACKUP_MOUNT" ]] && hdiutil detach "$BACKUP_MOUNT" >/dev/null 2>&1 || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/config"
export XDG_STATE_HOME="$HOME/state"
export XDG_DATA_HOME="$HOME/data"
export BPW_CONFIG_FILE="$HOME/config/better-photography-workflow/config"
export BPW_PLIST_CONFIG_FILE="$HOME/config/better-photography-workflow/config.plist"
export BPW_STATE_DIR="$HOME/state/better-photography-workflow"
export BPW_ROOT="$ROOT"
mkdir -p "$HOME"
work_name="BPW_WORK_${TEST_ROOT:t}"
backup_name="BPW_BACKUP_${TEST_ROOT:t}"
hdiutil create -size 512m -fs ExFAT -type SPARSE -volname "$work_name" "$TEST_ROOT/work" >/dev/null
hdiutil create -size 512m -fs ExFAT -type SPARSE -volname "$backup_name" "$TEST_ROOT/backup" >/dev/null
hdiutil attach -nobrowse "$TEST_ROOT/work.sparseimage" >/dev/null
WORK_MOUNT="/Volumes/$work_name"
hdiutil attach -nobrowse "$TEST_ROOT/backup.sparseimage" >/dev/null
BACKUP_MOUNT="/Volumes/$backup_name"
"$ROOT/bin/bpw" init >/dev/null
cat >> "$BPW_CONFIG_FILE" <<CONFIG
ENABLE_BACKUP=true
BACKUP_VOLUME_NAME="$backup_name"
BACKUP_DESTINATION="$BACKUP_MOUNT/Backup"
CONFIG
"$ROOT/bin/bpw" workspace add portable "$WORK_MOUNT/Projects" --type external --name '测试 SSD' >/dev/null
mkdir -p "$TEST_ROOT/card/DCIM"
print -n -r -- 'fixture original' > "$TEST_ROOT/card/DCIM/DSC0001.ARW"
"$ROOT/bin/bpw" ingest "$TEST_ROOT/card" --new '旅行 测试' --device A7R5 > "$TEST_ROOT/ingest.log"
project="$WORK_MOUNT/Projects/$(date '+%Y')/$(date '+%Y-%m-%d')_旅行 测试"
id="$(plutil -extract id raw -o - "$project/.bpw-project.json")"
test -f "$project/01_MEDIA/PHOTO/$(date '+%Y-%m-%d')/A7R5/RAW/DSC0001.ARW"
print 'ok - real ExFAT exclusive publication works'
"$ROOT/bin/bpw" ingest "$TEST_ROOT/card" --project "$id" --device A7R5 > "$TEST_ROOT/retry.log"
grep -q 'skip DCIM/DSC0001.ARW' "$TEST_ROOT/retry.log"
print 'ok - ExFAT duplicate skip works'
"$ROOT/bin/bpw" sync --project "$id" > "$TEST_ROOT/sync.log"
backup_file="$BACKUP_MOUNT/Backup/$id/${project:t}/01_MEDIA/PHOTO/$(date '+%Y-%m-%d')/A7R5/RAW/DSC0001.ARW"
cmp "$backup_file" "$TEST_ROOT/card/DCIM/DSC0001.ARW"
print 'ok - real mounted backup content matches source'
print -n -r -- 'retained' > "$BACKUP_MOUNT/Backup/$id/${project:t}/retain.txt"
"$ROOT/bin/bpw" sync --project "$id" >/dev/null
test -f "$BACKUP_MOUNT/Backup/$id/${project:t}/retain.txt"
print 'ok - backup retains destination-only files'
if "$ROOT/bin/bpw" ingest "$BACKUP_MOUNT" --project "$id" >/dev/null 2>&1; then print -u2 'backup source accepted'; exit 1; fi
print 'ok - real backup volume excluded from explicit ingest'
if "$ROOT/bin/bpw" ingest "$WORK_MOUNT" --project "$id" >/dev/null 2>&1; then print -u2 'workspace source accepted'; exit 1; fi
print 'ok - real workspace volume excluded from explicit ingest'
new_name="${work_name}_renamed"
diskutil renameVolume "$WORK_MOUNT" "$new_name" >/dev/null
WORK_MOUNT="/Volumes/$new_name"
"$ROOT/bin/bpw" project show "$id" > "$TEST_ROOT/renamed.json"
test "$(plutil -extract status raw -o - "$TEST_ROOT/renamed.json")" = online
case "$(plutil -extract path raw -o - "$TEST_ROOT/renamed.json")" in "$WORK_MOUNT"/*) ;; *) exit 1 ;; esac
print 'ok - real volume rename preserves online Project ID'
hdiutil detach "$WORK_MOUNT" >/dev/null
WORK_MOUNT=""
"$ROOT/bin/bpw" project show "$id" > "$TEST_ROOT/offline.json"
test "$(plutil -extract status raw -o - "$TEST_ROOT/offline.json")" = offline
print 'ok - detached workspace retains offline project registry'
print '8 passed, 0 failed'
