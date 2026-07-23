#!/bin/zsh

# Shared runtime for better-photography-workflow. This file is sourced only by
# project-owned scripts. The user config is treated as trusted local shell code;
# bpw_load_config applies basic ownership and permission checks before sourcing.

BPW_APP_NAME="better-photography-workflow"
BPW_VERSION="0.3.1"
BPW_WATCH_LABEL="com.better-photography-workflow.watch"
BPW_SYNC_LABEL="com.better-photography-workflow.sync"
BPW_LOG_MAX_BYTES=1048576
BPW_LOG_BACKUP_COUNT=3

bpw_set_runtime_paths() {
  : "${XDG_CONFIG_HOME:=$HOME/.config}"
  : "${XDG_STATE_HOME:=$HOME/.local/state}"
  : "${XDG_DATA_HOME:=$HOME/.local/share}"
  : "${BPW_CONFIG_FILE:=$XDG_CONFIG_HOME/$BPW_APP_NAME/config}"
  : "${BPW_PLIST_CONFIG_FILE:=${BPW_CONFIG_FILE:h}/config.plist}"
  : "${BPW_STATE_DIR:=$XDG_STATE_HOME/$BPW_APP_NAME}"
  : "${BPW_LOG_DIR:=$BPW_STATE_DIR/logs}"
  : "${BPW_MAIN_LOG:=$BPW_LOG_DIR/bpw.log}"
  : "${BPW_INSTALL_ROOT:=$XDG_DATA_HOME/$BPW_APP_NAME}"
  export BPW_CONFIG_FILE BPW_PLIST_CONFIG_FILE BPW_STATE_DIR BPW_LOG_DIR BPW_MAIN_LOG BPW_INSTALL_ROOT
}

bpw_set_defaults() {
  WORK_DIR="$HOME/Pictures/Photography_Work"
  REMINDER_LIST_NAME="🍎摄影工作流"
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

bpw_file_size() {
  local file="$1"
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%z' "$file" 2>/dev/null
  else
    stat -c '%s' "$file" 2>/dev/null
  fi
}

bpw_file_mtime() {
  local file="$1"
  if [[ "$(uname -s)" == Darwin ]]; then
    stat -f '%m' "$file" 2>/dev/null
  else
    stat -c '%Y' "$file" 2>/dev/null
  fi
}

bpw_rotate_log() {
  local file="$1" size index
  [[ -f "$file" ]] || return 0
  size="$(bpw_file_size "$file")" || return 0
  (( size >= BPW_LOG_MAX_BYTES )) || return 0

  local rotation_lock="$BPW_LOG_DIR/.rotation.lock"
  mkdir "$rotation_lock" 2>/dev/null || return 0
  size="$(bpw_file_size "$file")" || size=0
  if (( size >= BPW_LOG_MAX_BYTES )); then
    for (( index = BPW_LOG_BACKUP_COUNT; index >= 2; index-- )); do
      [[ -f "$file.$((index - 1))" ]] && mv -f "$file.$((index - 1))" "$file.$index"
    done
    mv -f "$file" "$file.1" && touch "$file"
    chmod 600 "$file" 2>/dev/null || true
  fi
  rmdir "$rotation_lock" 2>/dev/null || true
}

bpw_log() {
  local level="$1"
  shift
  local line="$(bpw_timestamp) [$level] $*"
  print -r -- "$line"
  if [[ -n "${BPW_MAIN_LOG:-}" ]]; then
    mkdir -p "${BPW_MAIN_LOG:h}" 2>/dev/null || true
    bpw_rotate_log "$BPW_MAIN_LOG"
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
  if [[ -e "$BPW_PLIST_CONFIG_FILE" ]]; then
    bpw_config_file_is_trusted "$BPW_PLIST_CONFIG_FILE" || return 1
    plutil -lint "$BPW_PLIST_CONFIG_FILE" >/dev/null 2>&1 || {
      bpw_error "plist 配置文件无效：$BPW_PLIST_CONFIG_FILE"
      return 1
    }
    bpw_load_plist_values "$BPW_PLIST_CONFIG_FILE" || return 1
    bpw_validate_config
    return
  fi
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

bpw_plist_value() {
  local file="$1" key="$2"
  plutil -extract "$key" raw -o - "$file" 2>/dev/null
}

bpw_load_plist_values() {
  local file="$1" schema count index
  schema="$(bpw_plist_value "$file" SCHEMA_VERSION)" || return 1
  [[ "$schema" == 1 ]] || { bpw_error "不支持的配置版本：$schema"; return 1; }

  WORK_DIR="$(bpw_plist_value "$file" WORK_DIR)" || return 1
  REMINDER_LIST_NAME="$(bpw_plist_value "$file" REMINDER_LIST_NAME)" || return 1
  AUTO_CREATE_PROJECT_STRUCTURE="$(bpw_plist_value "$file" AUTO_CREATE_PROJECT_STRUCTURE)" || return 1
  REMINDER_HOUR="$(bpw_plist_value "$file" REMINDER_HOUR)" || return 1
  REMINDER_MINUTE="$(bpw_plist_value "$file" REMINDER_MINUTE)" || return 1
  TASK_1_NAME="$(bpw_plist_value "$file" TASK_1_NAME)" || return 1
  TASK_1_DAYS="$(bpw_plist_value "$file" TASK_1_DAYS)" || return 1
  TASK_1_DESCRIPTION="$(bpw_plist_value "$file" TASK_1_DESCRIPTION)" || return 1
  TASK_2_NAME="$(bpw_plist_value "$file" TASK_2_NAME)" || return 1
  TASK_2_DAYS="$(bpw_plist_value "$file" TASK_2_DAYS)" || return 1
  TASK_2_DESCRIPTION="$(bpw_plist_value "$file" TASK_2_DESCRIPTION)" || return 1
  TASK_3_NAME="$(bpw_plist_value "$file" TASK_3_NAME)" || return 1
  TASK_3_DAYS="$(bpw_plist_value "$file" TASK_3_DAYS)" || return 1
  TASK_3_DESCRIPTION="$(bpw_plist_value "$file" TASK_3_DESCRIPTION)" || return 1
  TASK_4_NAME="$(bpw_plist_value "$file" TASK_4_NAME)" || return 1
  TASK_4_DAYS="$(bpw_plist_value "$file" TASK_4_DAYS)" || return 1
  TASK_4_DESCRIPTION="$(bpw_plist_value "$file" TASK_4_DESCRIPTION)" || return 1
  ENABLE_BACKUP="$(bpw_plist_value "$file" ENABLE_BACKUP)" || return 1
  BACKUP_VOLUME_NAME="$(bpw_plist_value "$file" BACKUP_VOLUME_NAME)" || return 1
  BACKUP_DESTINATION="$(bpw_plist_value "$file" BACKUP_DESTINATION)" || return 1
  BACKUP_ALLOW_DELETE="$(bpw_plist_value "$file" BACKUP_ALLOW_DELETE)" || return 1
  SCAN_INTERVAL="$(bpw_plist_value "$file" SCAN_INTERVAL)" || return 1
  SYNC_INTERVAL="$(bpw_plist_value "$file" SYNC_INTERVAL)" || return 1

  count="$(plutil -extract PROJECT_SUBDIRECTORIES raw -o - "$file" 2>/dev/null)" || return 1
  bpw_is_unsigned_integer "$count" || return 1
  PROJECT_SUBDIRECTORIES=()
  for (( index = 0; index < count; index++ )); do
    PROJECT_SUBDIRECTORIES+=("$(bpw_plist_value "$file" "PROJECT_SUBDIRECTORIES.$index")") || return 1
  done
}

bpw_plist_insert_string() {
  plutil -insert "$2" -string "$3" "$1" >/dev/null
}

bpw_plist_insert_integer() {
  plutil -insert "$2" -integer "$3" "$1" >/dev/null
}

bpw_plist_insert_boolean() {
  plutil -insert "$2" -bool "$3" "$1" >/dev/null
}

bpw_emit_effective_config_json() {
  bpw_load_config || return 1
  local temp subdir
  temp="$(mktemp "${TMPDIR:-/tmp}/bpw-config.XXXXXX")" || return 1
  plutil -create xml1 "$temp" || { rm -f "$temp"; return 1; }
  bpw_plist_insert_integer "$temp" SCHEMA_VERSION 1 || return 1
  bpw_plist_insert_string "$temp" WORK_DIR "$WORK_DIR" || return 1
  bpw_plist_insert_string "$temp" REMINDER_LIST_NAME "$REMINDER_LIST_NAME" || return 1
  bpw_plist_insert_boolean "$temp" AUTO_CREATE_PROJECT_STRUCTURE "$AUTO_CREATE_PROJECT_STRUCTURE" || return 1
  plutil -insert PROJECT_SUBDIRECTORIES -array "$temp" >/dev/null || return 1
  for subdir in "${PROJECT_SUBDIRECTORIES[@]}"; do
    plutil -insert PROJECT_SUBDIRECTORIES -string "$subdir" -append "$temp" >/dev/null || return 1
  done
  bpw_plist_insert_integer "$temp" REMINDER_HOUR "$REMINDER_HOUR" || return 1
  bpw_plist_insert_integer "$temp" REMINDER_MINUTE "$REMINDER_MINUTE" || return 1
  bpw_plist_insert_string "$temp" TASK_1_NAME "$TASK_1_NAME" || return 1
  bpw_plist_insert_integer "$temp" TASK_1_DAYS "$TASK_1_DAYS" || return 1
  bpw_plist_insert_string "$temp" TASK_1_DESCRIPTION "$TASK_1_DESCRIPTION" || return 1
  bpw_plist_insert_string "$temp" TASK_2_NAME "$TASK_2_NAME" || return 1
  bpw_plist_insert_integer "$temp" TASK_2_DAYS "$TASK_2_DAYS" || return 1
  bpw_plist_insert_string "$temp" TASK_2_DESCRIPTION "$TASK_2_DESCRIPTION" || return 1
  bpw_plist_insert_string "$temp" TASK_3_NAME "$TASK_3_NAME" || return 1
  bpw_plist_insert_integer "$temp" TASK_3_DAYS "$TASK_3_DAYS" || return 1
  bpw_plist_insert_string "$temp" TASK_3_DESCRIPTION "$TASK_3_DESCRIPTION" || return 1
  bpw_plist_insert_string "$temp" TASK_4_NAME "$TASK_4_NAME" || return 1
  bpw_plist_insert_integer "$temp" TASK_4_DAYS "$TASK_4_DAYS" || return 1
  bpw_plist_insert_string "$temp" TASK_4_DESCRIPTION "$TASK_4_DESCRIPTION" || return 1
  bpw_plist_insert_boolean "$temp" ENABLE_BACKUP "$ENABLE_BACKUP" || return 1
  bpw_plist_insert_string "$temp" BACKUP_VOLUME_NAME "$BACKUP_VOLUME_NAME" || return 1
  bpw_plist_insert_string "$temp" BACKUP_DESTINATION "$BACKUP_DESTINATION" || return 1
  bpw_plist_insert_boolean "$temp" BACKUP_ALLOW_DELETE "$BACKUP_ALLOW_DELETE" || return 1
  bpw_plist_insert_integer "$temp" SCAN_INTERVAL "$SCAN_INTERVAL" || return 1
  bpw_plist_insert_integer "$temp" SYNC_INTERVAL "$SYNC_INTERVAL" || return 1
  plutil -convert json -o - "$temp"
  local command_status=$?
  rm -f "$temp"
  return "$command_status"
}

bpw_apply_plist_config() {
  local source_file="$1" temp
  [[ -f "$source_file" && ! -L "$source_file" ]] || { bpw_error "配置输入必须是普通文件"; return 1; }
  mkdir -p "${BPW_PLIST_CONFIG_FILE:h}" || return 1
  temp="$BPW_PLIST_CONFIG_FILE.tmp.$$"
  cp "$source_file" "$temp" || return 1
  plutil -convert xml1 "$temp" >/dev/null 2>&1 || { rm -f "$temp"; bpw_error "配置输入不是有效 plist 或 JSON"; return 1; }
  plutil -lint "$temp" >/dev/null 2>&1 || { rm -f "$temp"; bpw_error "配置输入不是有效 plist 或 JSON"; return 1; }
  bpw_set_defaults
  bpw_load_plist_values "$temp" || { rm -f "$temp"; bpw_error "配置字段不完整或类型错误"; return 1; }
  bpw_validate_config || { rm -f "$temp"; return 1; }
  chmod 600 "$temp" || { rm -f "$temp"; return 1; }
  mv -f "$temp" "$BPW_PLIST_CONFIG_FILE" || return 1
  print -r -- "配置已保存：$BPW_PLIST_CONFIG_FILE"
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

bpw_process_identity() {
  local pid="$1" identity
  identity="$(ps -p "$pid" -o lstart= 2>/dev/null)" || return 1
  identity="$(print -r -- "$identity" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$identity" ]] || return 1
  print -r -- "$identity"
}

bpw_lock_is_active() {
  local lock_dir="$1" pid stored_identity current_identity
  local owner_file="$lock_dir/owner"
  [[ -f "$owner_file" && ! -L "$owner_file" ]] || return 1
  pid="$(sed -n 's/^pid=//p' "$owner_file" | head -n 1)"
  stored_identity="$(sed -n 's/^identity=//p' "$owner_file" | head -n 1)"
  bpw_is_unsigned_integer "$pid" || return 1
  current_identity="$(bpw_process_identity "$pid")" || return 1
  [[ -n "$stored_identity" && "$current_identity" == "$stored_identity" ]]
}

bpw_acquire_lock() {
  local lock_dir="$1" purpose="$2" attempt owner_file identity
  for attempt in 1 2; do
    if mkdir "$lock_dir" 2>/dev/null; then
      owner_file="$lock_dir/owner"
      identity="$(bpw_process_identity $$)" || identity="unknown-$$"
      {
        print -r -- "pid=$$"
        print -r -- "identity=$identity"
        print -r -- "purpose=$purpose"
        print -r -- "started_at=$(bpw_timestamp)"
      } > "$owner_file" || {
        rmdir "$lock_dir" 2>/dev/null || true
        return 1
      }
      chmod 600 "$owner_file" 2>/dev/null || true
      return 0
    fi
    bpw_lock_is_active "$lock_dir" && return 1
    if [[ ! -e "$lock_dir/owner" ]]; then
      local lock_mtime now
      lock_mtime="$(bpw_file_mtime "$lock_dir")" || return 1
      now="$(date +%s)"
      (( now - lock_mtime >= 10 )) || return 1
    fi
    rm -f "$lock_dir/owner" 2>/dev/null || return 1
    rmdir "$lock_dir" 2>/dev/null || return 1
    bpw_log WARN "已回收失效锁：$lock_dir"
  done
  return 1
}

bpw_release_lock() {
  local lock_dir="$1" pid
  local owner_file="$lock_dir/owner"
  [[ -d "$lock_dir" && -f "$owner_file" ]] || return 0
  pid="$(sed -n 's/^pid=//p' "$owner_file" | head -n 1)"
  [[ "$pid" == "$$" ]] || return 0
  rm -f "$owner_file" 2>/dev/null || return 1
  rmdir "$lock_dir" 2>/dev/null || return 1
}

bpw_write_operation_status() {
  local operation="$1" outcome="$2" exit_code="$3" detail="$4" duration="$5"
  local file="$BPW_STATE_DIR/last-$operation.status" temp now
  now="$(bpw_timestamp)"
  detail="${detail//$'\n'/ }"
  temp="$file.tmp.$$"
  umask 077
  {
    print -r -- "timestamp=$now"
    print -r -- "outcome=$outcome"
    print -r -- "exit_code=$exit_code"
    print -r -- "duration_seconds=$duration"
    print -r -- "detail=$detail"
  } > "$temp" || return 1
  mv -f "$temp" "$file" || return 1
  if [[ "$outcome" == success ]]; then
    cp -f "$file" "$BPW_STATE_DIR/last-$operation-success.status" 2>/dev/null || true
  fi
}

bpw_operation_status_summary() {
  local operation="$1"
  local file="$BPW_STATE_DIR/last-$operation.status"
  local timestamp outcome duration detail
  [[ -f "$file" ]] || { print -r -- "从未运行"; return 0; }
  timestamp="$(sed -n 's/^timestamp=//p' "$file" | head -n 1)"
  outcome="$(sed -n 's/^outcome=//p' "$file" | head -n 1)"
  duration="$(sed -n 's/^duration_seconds=//p' "$file" | head -n 1)"
  detail="$(sed -n 's/^detail=//p' "$file" | head -n 1)"
  print -r -- "$timestamp；$outcome；${duration:-0}s；$detail"
}

bpw_last_success_timestamp() {
  local operation="$1"
  local file="$BPW_STATE_DIR/last-$operation-success.status"
  [[ -f "$file" ]] || { print -r -- "从未成功"; return 0; }
  sed -n 's/^timestamp=//p' "$file" | head -n 1
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

bpw_prepare_destination_within_volume() {
  local volume_root="$1" destination="$2"
  local relative current component volume_real current_real
  local volume_device current_device

  [[ -d "$volume_root" && ! -L "$volume_root" ]] || {
    bpw_error "外接卷挂载点无效或为符号链接：$volume_root"
    return 1
  }
  [[ "$destination" == "$volume_root" || "$destination" == "$volume_root"/* ]] || {
    bpw_error "备份目标不在配置的外接卷中：$destination"
    return 1
  }
  volume_real="${volume_root:A}"
  volume_device="$(stat -f '%d' "$volume_root" 2>/dev/null)" || return 1
  relative="${destination#$volume_root}"
  current="$volume_root"

  local -a components
  components=("${(@s:/:)relative}")
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || continue
    current="$current/$component"
    if [[ -L "$current" ]]; then
      bpw_error "备份目标路径包含符号链接，拒绝同步：$current"
      return 1
    fi
    if [[ -e "$current" ]]; then
      [[ -d "$current" ]] || { bpw_error "备份目标路径不是目录：$current"; return 1; }
    else
      mkdir "$current" || { bpw_error "无法创建备份目标：$current"; return 1; }
    fi
    current_real="${current:A}"
    [[ "$current_real" == "$volume_real" || "$current_real" == "$volume_real"/* ]] || {
      bpw_error "备份目标真实路径逃离外接卷：$current_real"
      return 1
    }
    current_device="$(stat -f '%d' "$current" 2>/dev/null)" || return 1
    [[ "$current_device" == "$volume_device" ]] || {
      bpw_error "备份目标不属于配置的外接卷：$current"
      return 1
    }
  done
  [[ -d "$destination" && ! -L "$destination" ]]
}

bpw_prepare_backup_destination() {
  bpw_prepare_destination_within_volume "/Volumes/$BACKUP_VOLUME_NAME" "$BACKUP_DESTINATION"
}

bpw_run_rsync() {
  local source_dir="$1" destination="$2" allow_delete="$3"
  local -a rsync_args
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
  if [[ "$allow_delete" == true ]]; then
    rsync_args+=(--delete --delete-excluded)
  fi
  rsync "${rsync_args[@]}" "$source_dir/" "$destination/" 2>&1 | while IFS= read -r line; do
    bpw_log INFO "rsync: $line"
  done
  return "${pipestatus[1]}"
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
