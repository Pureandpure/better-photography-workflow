#!/bin/zsh
set -u

SCRIPT_ROOT="${0:A:h}"
if [[ -f "$SCRIPT_ROOT/lib/common.sh" ]]; then
  source "$SCRIPT_ROOT/lib/common.sh" || exit 1
else
  print -u2 -- "错误：找不到 common.sh"
  exit 1
fi
bpw_set_runtime_paths

purge=false
if (( $# == 1 )) && [[ "$1" == "--purge" ]]; then
  purge=true
elif (( $# != 0 )); then
  print -u2 -- "用法：uninstall.sh [--purge]"
  exit 2
fi
BIN_DIR="${BPW_BIN_DIR:-$HOME/.local/bin}"
AGENTS_DIR="$HOME/Library/LaunchAgents"
WATCH_PLIST="$AGENTS_DIR/$BPW_WATCH_LABEL.plist"
SYNC_PLIST="$AGENTS_DIR/$BPW_SYNC_LABEL.plist"
domain="gui/$(id -u)"

launchctl bootout "$domain" "$WATCH_PLIST" >/dev/null 2>&1 || true
launchctl bootout "$domain" "$SYNC_PLIST" >/dev/null 2>&1 || true
[[ -f "$WATCH_PLIST" ]] && rm -f "$WATCH_PLIST"
[[ -f "$SYNC_PLIST" ]] && rm -f "$SYNC_PLIST"
[[ -f "$BIN_DIR/bpw" ]] && rm -f "$BIN_DIR/bpw"

expected_install="${XDG_DATA_HOME:-$HOME/.local/share}/$BPW_APP_NAME"
if [[ "$BPW_INSTALL_ROOT" == "$expected_install" && -d "$BPW_INSTALL_ROOT" ]]; then
  rm -rf "$BPW_INSTALL_ROOT"
fi

if [[ "$purge" == true ]]; then
  expected_config="${XDG_CONFIG_HOME:-$HOME/.config}/$BPW_APP_NAME"
  expected_state="${XDG_STATE_HOME:-$HOME/.local/state}/$BPW_APP_NAME"
  [[ "${BPW_CONFIG_FILE:h}" == "$expected_config" && -d "$expected_config" ]] && rm -rf "$expected_config"
  [[ "$BPW_STATE_DIR" == "$expected_state" && -d "$expected_state" ]] && rm -rf "$expected_state"
  print -r -- "程序、配置、状态和日志已卸载。摄影项目与备份文件未删除。"
else
  print -r -- "程序与 launchd 服务已卸载。配置、状态、日志和摄影文件均已保留。"
  print -r -- "如需删除用户配置和状态，请运行 uninstall.sh --purge。"
fi
