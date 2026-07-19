#!/bin/zsh
set -u

SCRIPT_DIR="${0:A:h}"
BPW_ROOT="${BPW_ROOT:-${SCRIPT_DIR:h}}"
source "$BPW_ROOT/lib/common.sh" || exit 1

bpw_load_config || exit 1
bpw_prepare_runtime_dirs || { bpw_error "无法准备状态或日志目录"; exit 1; }

if [[ "$ENABLE_BACKUP" != true ]]; then
  bpw_log INFO "备份未启用；如需使用，请在配置中设置 ENABLE_BACKUP=true"
  exit 0
fi
[[ -d "$WORK_DIR" ]] || { bpw_error "工作目录不存在：$WORK_DIR"; exit 1; }
if ! bpw_volume_is_mounted; then
  bpw_error "外接硬盘未真实挂载：/Volumes/$BACKUP_VOLUME_NAME"
  exit 3
fi

lock_dir="$BPW_STATE_DIR/sync.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  bpw_log INFO "另一个同步任务正在运行，本次跳过"
  exit 0
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT INT TERM HUP

mkdir -p "$BACKUP_DESTINATION" || { bpw_error "无法创建备份目标：$BACKUP_DESTINATION"; exit 1; }

rsync_args=(
  -a
  --human-readable
  --itemize-changes
  --partial
  --exclude=.DS_Store
  '--exclude=._*'
  '--exclude=*.download'
  '--exclude=*.crdownload'
  '--exclude=*.part'
  '--exclude=*.tmp'
)
if [[ "$BACKUP_ALLOW_DELETE" == true ]]; then
  rsync_args+=(--delete --delete-excluded)
  bpw_log WARN "已启用 BACKUP_ALLOW_DELETE：目标端多余文件可能被删除"
else
  bpw_log INFO "安全模式：仅新增和更新，不删除目标端任何文件"
fi

bpw_log INFO "开始同步：$WORK_DIR/ → $BACKUP_DESTINATION/"
rsync "${rsync_args[@]}" "$WORK_DIR/" "$BACKUP_DESTINATION/" 2>&1 | while IFS= read -r line; do
  bpw_log INFO "rsync: $line"
done
rsync_status=${pipestatus[1]}

if (( rsync_status == 0 )); then
  bpw_log INFO "同步完成"
  exit 0
fi
case "$rsync_status" in
  20) bpw_error "同步被信号中断（rsync 退出码 20）；已传输文件保留，下次可继续" ;;
  23) bpw_error "部分文件未传输（rsync 退出码 23）；请查看上方日志" ;;
  24) bpw_error "部分源文件在同步过程中消失（rsync 退出码 24）；建议重试" ;;
  *) bpw_error "同步失败（rsync 退出码 $rsync_status）" ;;
esac
exit "$rsync_status"
