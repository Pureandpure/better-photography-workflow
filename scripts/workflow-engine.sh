#!/bin/zsh
set -u
SCRIPT_DIR="${0:A:h}"
BPW_ROOT="${BPW_ROOT:-${SCRIPT_DIR:h}}"
source "$BPW_ROOT/lib/common.sh" || exit 1
bpw_load_config || exit 1
bpw_prepare_runtime_dirs || exit 1
export WORK_DIR BACKUP_DESTINATION
export BPW_PROJECT_SUBDIRECTORIES="$(printf '%s\n' "${PROJECT_SUBDIRECTORIES[@]}")"
engine="$BPW_ROOT/bin/bpw-engine"
if [[ ! -x "$engine" && -d "$BPW_ROOT/engine" ]]; then
  engine="$(swift build --scratch-path "$BPW_STATE_DIR/native-build" --package-path "$BPW_ROOT/engine" --show-bin-path)/bpw-engine" || exit 1
  if [[ ! -x "$engine" ]] || [[ -n "$(find "$BPW_ROOT/engine/Sources" -type f -newer "$engine" 2>/dev/null)" ]]; then
    swift build --scratch-path "$BPW_STATE_DIR/native-build" --package-path "$BPW_ROOT/engine" >&2 || exit 1
  fi
fi
[[ -x "$engine" ]] || { bpw_error '找不到原生导入后端，请重新运行 ./install.sh（需要 Xcode Command Line Tools）'; exit 1; }
if [[ "${1:-}" == migrate-media-layout ]]; then
  lock_dir="$BPW_STATE_DIR/ingest.lock"
  if ! bpw_acquire_lock "$lock_dir" migration; then bpw_error '另一个导入、迁移或备份正在运行'; exit 1; fi
  trap 'bpw_release_lock "$lock_dir" || true' EXIT
  "$engine" "$@"
  exit $?
fi
if [[ "${1:-}" != ingest ]]; then
  exec "$engine" "$@"
fi
lock_dir="$BPW_STATE_DIR/ingest.lock"
if ! bpw_acquire_lock "$lock_dir" ingest; then bpw_error '另一个 ingest 正在运行'; exit 1; fi
started="$(date +%s)"
trap 'bpw_release_lock "$lock_dir" || true' EXIT
bpw_log INFO "Ingest 开始"
bpw_rotate_log "$BPW_MAIN_LOG"
"$engine" "$@" 2>&1 | tee -a "$BPW_MAIN_LOG"
result="${pipestatus[1]}"
if (( result == 0 )) && [[ " $* " != *" --dry-run "* ]]; then
  imported_id="$(plutil -extract projectId raw -o - "$BPW_STATE_DIR/last-import.json" 2>/dev/null)"
  imported_paths="$(mktemp "${TMPDIR:-/tmp}/bpw-import-paths.XXXXXX")"
  if [[ -n "$imported_id" && -n "$imported_paths" ]] && "$engine" paths --project "$imported_id" > "$imported_paths"; then
    while IFS= read -r -d '' imported_path; do
      "$BPW_ROOT/scripts/scan-projects.sh" --project "$imported_path" || bpw_log WARN '素材已导入；提醒事项尚未完成，可稍后 bpw scan 重试'
    done < "$imported_paths"
  fi
  [[ -n "$imported_paths" ]] && rm -f "$imported_paths"
fi
outcome=failed
(( result == 0 )) && outcome=success
bpw_write_operation_status ingest "$outcome" "$result" "ingest_$outcome" "$(( $(date +%s) - started ))" || true
exit "$result"
