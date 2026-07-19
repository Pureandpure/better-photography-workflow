#!/bin/zsh
set -u

SCRIPT_DIR="${0:A:h}"
BPW_ROOT="${BPW_ROOT:-${SCRIPT_DIR:h}}"
source "$BPW_ROOT/lib/common.sh" || exit 1

bpw_load_config || exit 1
bpw_prepare_runtime_dirs || { bpw_error "无法准备状态或日志目录"; exit 1; }

lock_dir="$BPW_STATE_DIR/scan.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  bpw_log INFO "另一个扫描任务正在运行，本次跳过"
  exit 0
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM HUP

process_project() {
  local project_path="$1" epoch result
  [[ -d "$project_path" ]] || { bpw_error "项目目录不存在：$project_path"; return 1; }
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
    "$TASK_4_NAME" "$TASK_4_DAYS" "$TASK_4_DESCRIPTION" 2>&1)"
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
if (( $# == 2 )) && [[ "$1" == "--project" ]]; then
  project_path="${2:A}"
  [[ "${project_path:h}" == "${WORK_DIR:A}" ]] || {
    bpw_error "指定目录不是 WORK_DIR 下的一级项目：$project_path"
    exit 2
  }
  process_project "$project_path" || failures=$((failures + 1))
elif (( $# == 0 )); then
  [[ -d "$WORK_DIR" ]] || { bpw_error "工作目录不存在：$WORK_DIR"; exit 1; }
  while IFS= read -r -d '' project_path; do
    process_project "$project_path" || failures=$((failures + 1))
  done < <(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0)
else
  bpw_error "scan-projects.sh 参数错误"
  exit 2
fi

(( failures == 0 )) || { bpw_error "$failures 个项目处理失败"; exit 1; }
bpw_log INFO "扫描完成"
