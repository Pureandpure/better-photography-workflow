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
ingest_lock_acquired=false
ingest_lock_dir="$BPW_STATE_DIR/ingest.lock"
lock_dir="$BPW_STATE_DIR/sync.lock"
finish_sync() {
  local exit_code=$? now duration
  now="$(date +%s)"
  duration=$((now - operation_started))
  [[ "$ingest_lock_acquired" == true ]] && bpw_release_lock "$ingest_lock_dir" || true
  [[ "$lock_acquired" == true ]] && bpw_release_lock "$lock_dir" || true
  bpw_write_operation_status sync "$operation_outcome" "$exit_code" "$operation_detail" "$duration" || true
}
trap finish_sync EXIT

if [[ "$ENABLE_BACKUP" != true ]]; then
  operation_outcome="disabled"
  operation_detail="backup_disabled"
  bpw_log INFO "备份未启用；如需使用，请在配置中设置 ENABLE_BACKUP=true"
  exit 0
fi
(( $# == 0 )) || { (( $# == 2 )) && [[ "$1" == --project ]] || { bpw_error '用法：bpw sync [--project id]'; exit 2; }; }
if ! bpw_volume_is_mounted; then
  operation_detail="volume_not_mounted"
  bpw_error "外接硬盘未真实挂载：/Volumes/$BACKUP_VOLUME_NAME"
  exit 3
fi

if ! bpw_acquire_lock "$lock_dir" sync; then
  operation_outcome="skipped"
  operation_detail="active_lock"
  bpw_log INFO "另一个同步任务正在运行，本次跳过"
  exit 0
fi
lock_acquired=true

if ! bpw_prepare_backup_destination; then
  operation_detail="unsafe_backup_destination"
  exit 1
fi
if ! bpw_acquire_lock "$ingest_lock_dir" backup-source; then
  operation_detail="ingest_active"
  bpw_error 'Ingest 正在运行，完成后再备份'
  exit 1
fi
ingest_lock_acquired=true
paths_file="$(mktemp "${TMPDIR:-/tmp}/bpw-sync-paths.XXXXXX")" || exit 1
"$BPW_ROOT/scripts/workflow-engine.sh" paths "$@" > "$paths_file" || { rm -f "$paths_file"; exit 1; }
bpw_log INFO "Primary 项目安全备份：不删除目标文件"
rsync_status=0
synced_projects=0
while IFS= read -r -d '' project_path; do
  project_id="$(bpw_state_id "$project_path")" || { rsync_status=1; break; }
  destination="$BACKUP_DESTINATION/$project_id/${project_path:t}"
  if [[ "${project_path:A}" == "${destination:A}" || "${destination:A}" == "${project_path:A}"/* || "${project_path:A}" == "${destination:A}"/* ]]; then
    bpw_error '备份与 Primary 路径不能重叠'
    rsync_status=1
    break
  fi
  bpw_prepare_destination_within_volume "/Volumes/$BACKUP_VOLUME_NAME" "$destination" || { rsync_status=1; break; }
  bpw_log INFO "同步：$project_path/ → $destination/"
  bpw_run_rsync "$project_path" "$destination" false
  current_status=$?
  (( current_status == 0 )) && synced_projects=$((synced_projects + 1))
  if (( current_status != 0 )); then rsync_status=$current_status; break; fi
done < "$paths_file"
rm -f "$paths_file"

if (( rsync_status == 0 && synced_projects == 0 )); then
  operation_outcome="skipped"
  operation_detail="no_online_primary_projects"
  bpw_log INFO "没有 online Primary 项目可备份"
  exit 0
fi
if (( rsync_status == 0 )); then
  operation_outcome="success"
  operation_detail="sync_completed"
  bpw_log INFO "同步完成"
  exit 0
fi
operation_detail="rsync_exit_$rsync_status"
case "$rsync_status" in
  20) bpw_error "同步被信号中断（rsync 退出码 20）；已传输文件保留，下次可继续" ;;
  23) bpw_error "部分文件未传输（rsync 退出码 23）；请查看上方日志" ;;
  24) bpw_error "部分源文件在同步过程中消失（rsync 退出码 24）；建议重试" ;;
  *) bpw_error "同步失败（rsync 退出码 $rsync_status）" ;;
esac
exit "$rsync_status"
