#!/bin/zsh
set -u

SCRIPT_DIR="${0:A:h}"
BPW_ROOT="${BPW_ROOT:-${SCRIPT_DIR:h}}"
source "$BPW_ROOT/lib/common.sh" || exit 1

bpw_load_config || exit 1
bpw_prepare_runtime_dirs || { bpw_error "无法准备状态或日志目录"; exit 1; }

operation_started="$(date +%s)"
operation_outcome="failed"
operation_detail="unexpected_exit"
lock_acquired=false
lock_dir="$BPW_STATE_DIR/scan.lock"
finish_scan() {
  local exit_code=$? now duration
  now="$(date +%s)"
  duration=$((now - operation_started))
  [[ "$lock_acquired" == true ]] && bpw_release_lock "$lock_dir" || true
  bpw_write_operation_status scan "$operation_outcome" "$exit_code" "$operation_detail" "$duration" || true
}
trap finish_scan EXIT

if ! bpw_acquire_lock "$lock_dir" scan; then
  operation_outcome="skipped"
  operation_detail="active_lock"
  bpw_log INFO "另一个扫描任务正在运行，本次跳过"
  exit 0
fi
lock_acquired=true

process_project() {
  local project_path="$1" epoch result
  [[ ! -L "$project_path" && -d "$project_path" ]] || { bpw_error "项目目录不存在：$project_path"; return 1; }
  project_path="${project_path:A}"
  bpw_ensure_project_structure "$project_path" || { bpw_error "无法补齐项目目录结构：$project_path"; return 1; }

  if bpw_project_is_processed "$project_path"; then
    bpw_log INFO "已处理，跳过：$project_path"
    return 0
  fi

  epoch="$(bpw_project_epoch "$project_path")" || { bpw_error "无法读取项目创建时间：$project_path"; return 1; }
  bpw_log INFO "正在为项目创建提醒事项：$project_path"
  result="$(osascript "$BPW_ROOT/scripts/create-reminders.applescript" \
    "$REMINDER_LIST_NAME" "$project_path" "$epoch" "$REMINDER_HOUR" "$REMINDER_MINUTE" \
    "$TASK_1_NAME" "$TASK_1_DAYS" "$TASK_1_DESCRIPTION" \
    "$TASK_2_NAME" "$TASK_2_DAYS" "$TASK_2_DESCRIPTION" \
    "$TASK_3_NAME" "$TASK_3_DAYS" "$TASK_3_DESCRIPTION" \
    "$TASK_4_NAME" "$TASK_4_DAYS" "$TASK_4_DESCRIPTION" \
    "$(bpw_state_id "$project_path")" \
    "$(plutil -extract reminderOriginalPath raw -o - "$project_path/.bpw-project.json" 2>/dev/null || print -r -- "$project_path")" 2>&1)"
  local command_status=$?
  if (( command_status != 0 )); then
    bpw_error "提醒事项创建失败（osascript 退出码 $command_status）：$result"
    bpw_error "请检查：系统设置 → 隐私与安全性 → 提醒事项，以及 自动化"
    return "$command_status"
  fi
  bpw_mark_project_processed "$project_path" || { bpw_error "提醒已创建，但本地状态写入失败：$project_path"; return 1; }
  bpw_log INFO "项目处理完成：$project_path（$result）"
}

failures=0
paths_file="$(mktemp "${TMPDIR:-/tmp}/bpw-scan-paths.XXXXXX")" || exit 1
if (( $# == 2 )) && [[ "$1" == --project ]]; then
  "$BPW_ROOT/scripts/workflow-engine.sh" paths --project "$2" > "$paths_file" || { rm -f "$paths_file"; exit 1; }
elif (( $# == 0 )); then
  "$BPW_ROOT/scripts/workflow-engine.sh" paths > "$paths_file" || { rm -f "$paths_file"; exit 1; }
else
  bpw_error "scan-projects.sh 参数错误"
  rm -f "$paths_file"
  exit 2
fi
while IFS= read -r -d '' project_path; do
  process_project "$project_path" || failures=$((failures + 1))
done < "$paths_file"
rm -f "$paths_file"

if (( failures != 0 )); then
  operation_detail="project_failures=$failures"
  bpw_error "$failures 个项目处理失败"
  exit 1
fi
operation_outcome="success"
operation_detail="scan_completed"
bpw_log INFO "扫描完成"
