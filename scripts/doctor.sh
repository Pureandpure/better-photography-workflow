#!/bin/zsh
set -u

SCRIPT_DIR="${0:A:h}"
BPW_ROOT="${BPW_ROOT:-${SCRIPT_DIR:h}}"
source "$BPW_ROOT/lib/common.sh" || exit 1

failures=0
warnings=0
ok() { print -r -- "[OK] $*"; }
fail() { print -r -- "[FAIL] $*"; failures=$((failures + 1)); }
warn() { print -r -- "[WARN] $*"; warnings=$((warnings + 1)); }

if [[ "$(uname -s)" == Darwin ]]; then ok "运行环境为 macOS"; else fail "仅支持 macOS"; fi

for command_name in zsh osascript osacompile rsync launchctl plutil find shasum ps stat; do
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "已找到 $command_name：$(command -v "$command_name")"
  else
    fail "缺少系统命令：$command_name"
  fi
done

config_valid=false
if bpw_load_config; then
  config_valid=true
  ok "配置文件有效：$BPW_CONFIG_FILE"
else
  fail "配置文件无效"
fi

if [[ "$config_valid" == true ]]; then
  if [[ -d "$WORK_DIR" && -w "$WORK_DIR" ]]; then ok "工作目录存在且可写：$WORK_DIR"; else fail "工作目录不存在或不可写：$WORK_DIR"; fi
fi

if bpw_prepare_runtime_dirs && [[ -w "$BPW_LOG_DIR" ]]; then ok "日志目录可写：$BPW_LOG_DIR"; else fail "日志目录不可写：$BPW_LOG_DIR"; fi

if [[ "$config_valid" == true ]]; then
  if "$BPW_ROOT/scripts/workflow-engine.sh" workspace list; then ok "Workspace UUID/online 检查完成"; else fail "Workspace 配置或后端无效"; fi
fi

for lock_name in scan sync ingest; do
  lock_dir="$BPW_STATE_DIR/$lock_name.lock"
  if [[ -d "$lock_dir" ]]; then
    if bpw_lock_is_active "$lock_dir"; then
      warn "$lock_name 任务当前持有运行锁"
    else
      warn "发现失效的 $lock_name 锁；下次运行会自动回收"
    fi
  fi
done

if [[ -f "$BPW_MAIN_LOG" ]]; then
  log_size="$(bpw_file_size "$BPW_MAIN_LOG")" || log_size=0
  (( log_size < BPW_LOG_MAX_BYTES )) || warn "主日志将在下次写入时轮转"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bpw-doctor.XXXXXX")" || exit 1
trap 'rm -rf "$tmp_dir"' EXIT INT TERM HUP
if command -v osacompile >/dev/null 2>&1 && osacompile -o "$tmp_dir/reminders.scpt" "$BPW_ROOT/scripts/create-reminders.applescript" >/dev/null 2>&1; then
  ok "AppleScript 可以编译"
else
  fail "AppleScript 编译失败"
fi

if [[ "$config_valid" == true ]]; then
  cli_path="${BPW_CLI_PATH:-$BPW_ROOT/bin/bpw}"
  plist_failures=0
  bpw_render_launchd_plist "$BPW_ROOT/launchd/$BPW_WATCH_LABEL.plist.template" "$tmp_dir/watch.plist" "$SCAN_INTERVAL" "$cli_path" || plist_failures=$((plist_failures + 1))
  bpw_render_launchd_plist "$BPW_ROOT/launchd/$BPW_SYNC_LABEL.plist.template" "$tmp_dir/sync.plist" "$SYNC_INTERVAL" "$cli_path" || plist_failures=$((plist_failures + 1))
  plutil -lint "$tmp_dir/watch.plist" >/dev/null 2>&1 || plist_failures=$((plist_failures + 1))
  plutil -lint "$tmp_dir/sync.plist" >/dev/null 2>&1 || plist_failures=$((plist_failures + 1))
  if (( plist_failures == 0 )); then ok "launchd plist 模板有效"; else fail "launchd plist 模板无效"; fi
fi

if bpw_launchd_loaded "$BPW_WATCH_LABEL"; then ok "扫描后台任务已加载"; else warn "扫描后台任务未加载；运行 bpw install 重新安装"; fi
if bpw_launchd_loaded "$BPW_SYNC_LABEL"; then ok "备份后台任务已加载"; else warn "备份后台任务未加载；运行 bpw install 重新安装"; fi

if [[ "$(uname -s)" == Darwin ]] && command -v osascript >/dev/null 2>&1; then
  if osascript -e 'tell application "Reminders" to get name' >/dev/null 2>&1; then
    ok "可以访问 Apple 提醒事项"
  else
    warn "无法访问 Apple 提醒事项。请检查："
    print -r -- "       系统设置 → 隐私与安全性 → 提醒事项"
    print -r -- "       系统设置 → 隐私与安全性 → 自动化"
  fi
fi

if [[ "$config_valid" == true ]]; then
  if [[ "$ENABLE_BACKUP" == true ]]; then
    [[ "$BACKUP_DESTINATION" == "/Volumes/$BACKUP_VOLUME_NAME"(|/*) ]] && ok "外接硬盘目标配置合理" || fail "外接硬盘目标不在配置卷中"
    if bpw_volume_is_mounted; then ok "外接硬盘已真实挂载"; else warn "外接硬盘当前未挂载：/Volumes/$BACKUP_VOLUME_NAME"; fi
    [[ -f "$BPW_STATE_DIR/last-sync-success.status" ]] || warn "备份已启用，但尚无成功同步记录"
  else
    ok "外接硬盘备份未启用"
  fi
fi

print -r -- "检查完成：$failures 个失败，$warnings 个警告"
(( failures == 0 ))
