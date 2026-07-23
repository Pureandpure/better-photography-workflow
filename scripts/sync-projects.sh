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
lock_dir="$BPW_STATE_DIR/sync.lock"
finish_sync() {
  local exit_code=$? now duration
  now="$(date +%s)"
  duration=$((now - operation_started))
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
[[ -d "$WORK_DIR" ]] || { operation_detail="work_dir_missing"; bpw_error "工作目录不存在：$WORK_DIR"; exit 1; }
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
if [[ "$BACKUP_ALLOW_DELETE" == true ]]; then
  bpw_log WARN "已启用 BACKUP_ALLOW_DELETE：目标端多余文件可能被删除"
else
  bpw_log INFO "安全模式：仅新增和更新，不删除目标端任何文件"
fi

bpw_log INFO "开始同步：$WORK_DIR/ → $BACKUP_DESTINATION/"
bpw_run_rsync "$WORK_DIR" "$BACKUP_DESTINATION" "$BACKUP_ALLOW_DELETE"
rsync_status=$?

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
