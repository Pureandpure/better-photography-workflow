#!/bin/zsh

# Shared runtime for better-photography-workflow. This file is sourced only by
# project-owned scripts. The user config is treated as trusted local shell code;
# bpw_load_config applies basic ownership and permission checks before sourcing.

BPW_APP_NAME="better-photography-workflow"
BPW_WATCH_LABEL="com.better-photography-workflow.watch"
BPW_SYNC_LABEL="com.better-photography-workflow.sync"

bpw_set_runtime_paths() {
  : "${XDG_CONFIG_HOME:=$HOME/.config}"
  : "${XDG_STATE_HOME:=$HOME/.local/state}"
  : "${XDG_DATA_HOME:=$HOME/.local/share}"
  : "${BPW_CONFIG_FILE:=$XDG_CONFIG_HOME/$BPW_APP_NAME/config}"
  : "${BPW_STATE_DIR:=$XDG_STATE_HOME/$BPW_APP_NAME}"
  : "${BPW_LOG_DIR:=$BPW_STATE_DIR/logs}"
  : "${BPW_MAIN_LOG:=$BPW_LOG_DIR/bpw.log}"
  : "${BPW_INSTALL_ROOT:=$XDG_DATA_HOME/$BPW_APP_NAME}"
  export BPW_CONFIG_FILE BPW_STATE_DIR BPW_LOG_DIR BPW_MAIN_LOG BPW_INSTALL_ROOT
}

bpw_set_defaults() {
  WORK_DIR="$HOME/Pictures/Photography_Work"
  REMINDER_LIST_NAME="摄影工作流"
  AUTO_CREATE_PROJECT_STRUCTURE=true
  PROJECT_SUBDIRECTORIES=("01_RAW" "02_EXPORT" "03_PRINT" "99_REFERENCE")
  REMINDER_HOUR=20
  REMINDER_MINUTE=0
  TASK_1_NAME="① 初筛废片"
  TASK_1_DAYS=1
  TASK_1_DESCRIPTION="删除严重失焦、误触快门、明显重复和完全不可用的照片。"
  TASK_2_NAME="② 精选待修照片"
  TASK_2_DAYS=3
  TASK_2_DESCRIPTION="从保留照片中选出值得调色、精修和交付的照片。"
  TASK_3_NAME="③ 调色与精修"
  TASK_3_DAYS=7
  TASK_3_DESCRIPTION="完成调色、局部调整和必要的深度修图。"
  TASK_4_NAME="④ 导出、备份与归档"
  TASK_4_DAYS=10
  TASK_4_DESCRIPTION="导出最终成片，确认备份，并将精选照片加入作品集或 iCloud。"
  ENABLE_BACKUP=false
  BACKUP_VOLUME_NAME="PhotographySSD"
  BACKUP_DESTINATION="/Volumes/$BACKUP_VOLUME_NAME/Photography/01_Projects"
  BACKUP_ALLOW_DELETE=false
  SCAN_INTERVAL=300
  SYNC_INTERVAL=3600
}

bpw_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

bpw_prepare_runtime_dirs() {
  umask 077
  mkdir -p "$BPW_STATE_DIR" "$BPW_STATE_DIR/projects" "$BPW_LOG_DIR" || return 1
  touch "$BPW_MAIN_LOG" || return 1
}

bpw_log() {
  local level="$1"
  shift
  local line="$(bpw_timestamp) [$level] $*"
  print -r -- "$line"
  if [[ -n "${BPW_MAIN_LOG:-}" ]]; then
    mkdir -p "${BPW_MAIN_LOG:h}" 2>/dev/null || true
    print -r -- "$line" >> "$BPW_MAIN_LOG" 2>/dev/null || true
  fi
}

bpw_error() {
  bpw_log ERROR "$*" >&2
}

bpw_is_boolean() {
  [[ "$1" == true || "$1" == false ]]
}

bpw_is_unsigned_integer() {
  [[ "$1" == <-> ]]
}

bpw_config_file_is_trusted() {
  local file="$1" owner mode current_uid
  [[ -f "$file" && ! -L "$file" ]] || {
    bpw_error "配置文件必须是普通文件且不能是符号链接：$file"
    return 1
  }
  current_uid="$(id -u)"
  if [[ "$(uname -s)" == Darwin ]]; then
    owner="$(stat -f '%u' "$file" 2>/dev/null)" || return 1
    mode="$(stat -f '%Lp' "$file" 2>/dev/null)" || return 1
  else
    owner="$(stat -c '%u' "$file" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$file" 2>/dev/null)" || return 1
  fi
  [[ "$owner" == "$current_uid" ]] || {
    bpw_error "配置文件不属于当前用户，拒绝加载：$file"
    return 1
  }
  local mode_value=$(( 8#$mode ))
  (( (mode_value & 022) == 0 )) || {
    bpw_error "配置文件可被组或其他用户写入，拒绝加载；请执行：chmod 600 ${(q)file}"
    return 1
  }
}

bpw_validate_config() {
  local failed=0 value
  [[ "$WORK_DIR" == /* && "$WORK_DIR" != *$'\n'* ]] || {
    bpw_error "WORK_DIR 必须是无换行的绝对路径"
    failed=1
  }
  [[ "$WORK_DIR" != *"/../"* && "$WORK_DIR" != */.. ]] || {
    bpw_error "WORK_DIR 不能包含父目录跳转"
    failed=1
  }
  [[ -n "$REMINDER_LIST_NAME" && "$REMINDER_LIST_NAME" != *$'\n'* ]] || {
    bpw_error "REMINDER_LIST_NAME 不能为空或包含换行"
    failed=1
  }
  bpw_is_boolean "$AUTO_CREATE_PROJECT_STRUCTURE" || {
    bpw_error "AUTO_CREATE_PROJECT_STRUCTURE 必须是 true 或 false"
    failed=1
  }
  bpw_is_boolean "$ENABLE_BACKUP" || { bpw_error "ENABLE_BACKUP 必须是 true 或 false"; failed=1; }
  bpw_is_boolean "$BACKUP_ALLOW_DELETE" || { bpw_error "BACKUP_ALLOW_DELETE 必须是 true 或 false"; failed=1; }
  bpw_is_unsigned_integer "$REMINDER_HOUR" && (( 10#$REMINDER_HOUR <= 23 )) || {
    bpw_error "REMINDER_HOUR 必须在 0 到 23 之间"
    failed=1
  }
  bpw_is_unsigned_integer "$REMINDER_MINUTE" && (( 10#$REMINDER_MINUTE <= 59 )) || {
    bpw_error "REMINDER_MINUTE 必须在 0 到 59 之间"
    failed=1
  }
  for value in "$TASK_1_DAYS" "$TASK_2_DAYS" "$TASK_3_DAYS" "$TASK_4_DAYS" "$SCAN_INTERVAL" "$SYNC_INTERVAL"; do
    bpw_is_unsigned_integer "$value" || { bpw_error "任务天数和扫描间隔必须是非负整数"; failed=1; break; }
  done
  (( 10#$SCAN_INTERVAL > 0 && 10#$SYNC_INTERVAL > 0 )) || { bpw_error "SCAN_INTERVAL 与 SYNC_INTERVAL 必须大于 0"; failed=1; }
  for value in "$TASK_1_NAME" "$TASK_2_NAME" "$TASK_3_NAME" "$TASK_4_NAME"; do
    [[ -n "$value" && "$value" != *$'\n'* ]] || { bpw_error "任务名称不能为空或包含换行"; failed=1; }
  done
  for value in "$TASK_1_DESCRIPTION" "$TASK_2_DESCRIPTION" "$TASK_3_DESCRIPTION" "$TASK_4_DESCRIPTION"; do
    [[ -n "$value" ]] || { bpw_error "任务说明不能为空"; failed=1; }
  done
  (( ${#PROJECT_SUBDIRECTORIES[@]} > 0 )) || { bpw_error "PROJECT_SUBDIRECTORIES 不能为空"; failed=1; }
  for value in "${PROJECT_SUBDIRECTORIES[@]}"; do
    [[ -n "$value" && "$value" != /* && "$value" != "." && "$value" != ".." && "$value" != *"/../"* && "$value" != ../* && "$value" != */.. && "$value" != *$'\n'* ]] || {
      bpw_error "不安全的项目子目录：$value"
      failed=1
    }
  done
  if [[ "$ENABLE_BACKUP" == true ]]; then
    [[ -n "$BACKUP_VOLUME_NAME" && "$BACKUP_VOLUME_NAME" != */* && "$BACKUP_VOLUME_NAME" != *$'\n'* ]] || {
      bpw_error "BACKUP_VOLUME_NAME 不能为空、包含斜杠或换行"
      failed=1
    }
    local volume_root="/Volumes/$BACKUP_VOLUME_NAME"
    [[ "$BACKUP_DESTINATION" == "$volume_root" || "$BACKUP_DESTINATION" == "$volume_root"/* ]] || {
      bpw_error "BACKUP_DESTINATION 必须位于配置的外接卷内：$volume_root"
      failed=1
    }
    [[ "$BACKUP_DESTINATION" != *"/../"* && "$BACKUP_DESTINATION" != */.. && "$BACKUP_DESTINATION" != *$'\n'* ]] || {
      bpw_error "BACKUP_DESTINATION 不能包含父目录跳转或换行"
      failed=1
    }
    if [[ "$BACKUP_DESTINATION" == "$WORK_DIR" || "$BACKUP_DESTINATION" == "$WORK_DIR"/* || "$WORK_DIR" == "$BACKUP_DESTINATION"/* ]]; then
      bpw_error "WORK_DIR 与 BACKUP_DESTINATION 不能相同或互相包含"
      failed=1
    fi
  fi
  (( failed == 0 ))
}

bpw_load_config() {
  bpw_set_runtime_paths
  bpw_set_defaults
  [[ -f "$BPW_CONFIG_FILE" ]] || {
    bpw_error "找不到配置文件：$BPW_CONFIG_FILE（请先运行 bpw init）"
    return 1
  }
  bpw_config_file_is_trusted "$BPW_CONFIG_FILE" || return 1
  zsh -n "$BPW_CONFIG_FILE" >/dev/null 2>&1 || {
    bpw_error "配置文件存在 shell 语法错误：$BPW_CONFIG_FILE"
    return 1
  }
  # The config is explicitly a trusted, user-owned local zsh configuration.
  source "$BPW_CONFIG_FILE" || {
    bpw_error "加载配置文件失败：$BPW_CONFIG_FILE"
    return 1
  }
  bpw_validate_config
}

bpw_state_id() {
  local project_path="$1" digest
  if [[ -e "$project_path" ]]; then
    project_path="${project_path:A}"
  fi
  if command -v shasum >/dev/null 2>&1; then
    digest="$(printf '%s' "$project_path" | shasum -a 256)" || return 1
    print -r -- "${digest%% *}"
  else
    digest="$(printf '%s' "$project_path" | cksum)" || return 1
    print -r -- "cksum-${digest// /-}"
  fi
}

bpw_project_marker() {
  print -r -- "$BPW_STATE_DIR/projects/$(bpw_state_id "$1").done"
}

bpw_project_is_processed() {
  [[ -f "$(bpw_project_marker "$1")" ]]
}

bpw_mark_project_processed() {
  local project_path="$1" marker temp
  marker="$(bpw_project_marker "$project_path")" || return 1
  temp="$marker.tmp.$$"
  umask 077
  {
    print -r -- "project_path=$project_path"
    print -r -- "processed_at=$(bpw_timestamp)"
  } > "$temp" || return 1
  mv -f "$temp" "$marker"
}

bpw_project_epoch() {
  local project_dir="$1" epoch
  if [[ "$(uname -s)" == Darwin ]]; then
    epoch="$(stat -f '%B' "$project_dir" 2>/dev/null)" || return 1
    if [[ "$epoch" == "0" || "$epoch" == "-1" ]]; then
      epoch="$(stat -f '%m' "$project_dir")" || return 1
    fi
  else
    epoch="$(stat -c '%W' "$project_dir" 2>/dev/null)" || return 1
    if [[ "$epoch" == "0" || "$epoch" == "-1" ]]; then
      epoch="$(stat -c '%Y' "$project_dir")" || return 1
    fi
  fi
  print -r -- "$epoch"
}

bpw_ensure_project_structure() {
  local project_path="$1" subdir
  [[ "$AUTO_CREATE_PROJECT_STRUCTURE" == true ]] || return 0
  for subdir in "${PROJECT_SUBDIRECTORIES[@]}"; do
    mkdir -p "$project_path/$subdir" || return 1
  done
}

bpw_volume_is_mounted() {
  local volume_root="/Volumes/$BACKUP_VOLUME_NAME"
  [[ "$(uname -s)" == Darwin ]] || return 1
  command -v diskutil >/dev/null 2>&1 || return 1
  diskutil info "$volume_root" >/dev/null 2>&1 || return 1
  bpw_mount_table_contains "$volume_root" < <(/sbin/mount)
}

bpw_mount_table_contains() {
  local volume_root="$1" line
  while IFS= read -r line; do
    if [[ "$line" == *" on $volume_root ("* ]]; then
      return 0
    fi
  done
  return 1
}

bpw_launchd_loaded() {
  launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1
}

bpw_xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  print -r -- "$value"
}

bpw_sed_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  print -r -- "$value"
}

bpw_render_launchd_plist() {
  local template="$1" output="$2" interval="$3" cli_path="$4"
  local cli work output_log err root config_file state_dir log_dir main_log tmp
  cli="$(bpw_sed_replacement "$(bpw_xml_escape "$cli_path")")"
  work="$(bpw_sed_replacement "$(bpw_xml_escape "$WORK_DIR")")"
  output_log="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_LOG_DIR/launchd-output.log")")"
  err="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_LOG_DIR/launchd-error.log")")"
  root="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_INSTALL_ROOT")")"
  config_file="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_CONFIG_FILE")")"
  state_dir="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_STATE_DIR")")"
  log_dir="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_LOG_DIR")")"
  main_log="$(bpw_sed_replacement "$(bpw_xml_escape "$BPW_MAIN_LOG")")"
  tmp="$output.tmp.$$"
  sed \
    -e "s|__BPW_CLI__|$cli|g" \
    -e "s|__WORK_DIR__|$work|g" \
    -e "s|__OUTPUT_LOG__|$output_log|g" \
    -e "s|__ERROR_LOG__|$err|g" \
    -e "s|__BPW_ROOT__|$root|g" \
    -e "s|__CONFIG_FILE__|$config_file|g" \
    -e "s|__STATE_DIR__|$state_dir|g" \
    -e "s|__LOG_DIR__|$log_dir|g" \
    -e "s|__MAIN_LOG__|$main_log|g" \
    -e "s|__INTERVAL__|$interval|g" \
    "$template" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$output"
}

bpw_set_runtime_paths
