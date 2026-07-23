#!/bin/zsh
set -u

SOURCE_ROOT="${0:A:h}"
source "$SOURCE_ROOT/lib/common.sh" || exit 1
bpw_set_runtime_paths

if [[ "$(uname -s)" != Darwin ]]; then
  print -u2 -- "错误：better-photography-workflow 仅支持 macOS。"
  exit 1
fi

BIN_DIR="${BPW_BIN_DIR:-$HOME/.local/bin}"
AGENTS_DIR="$HOME/Library/LaunchAgents"
WATCH_PLIST="$AGENTS_DIR/$BPW_WATCH_LABEL.plist"
SYNC_PLIST="$AGENTS_DIR/$BPW_SYNC_LABEL.plist"
INSTALL_PARENT="${BPW_INSTALL_ROOT:h}"
mkdir -p "$INSTALL_PARENT" "$BIN_DIR" "$AGENTS_DIR" || exit 1

stage_root="$(mktemp -d "$INSTALL_PARENT/.bpw-install.XXXXXX")" || exit 1
watch_temp=""
sync_temp=""
old_root=""
watch_backup=""
sync_backup=""

cleanup_install() {
  [[ -n "$watch_temp" && -f "$watch_temp" ]] && rm -f "$watch_temp"
  [[ -n "$sync_temp" && -f "$sync_temp" ]] && rm -f "$sync_temp"
  if [[ -n "$stage_root" && -d "$stage_root" && "${stage_root:h}" == "$INSTALL_PARENT" ]]; then
    rm -rf "$stage_root"
  fi
}
trap cleanup_install EXIT

mkdir -p "$stage_root/bin" "$stage_root/lib" "$stage_root/scripts" "$stage_root/launchd" \
  "$stage_root/config" "$stage_root/docs" || exit 1
cp -f "$SOURCE_ROOT/bin/bpw" "$stage_root/bin/bpw" || exit 1
cp -f "$SOURCE_ROOT/lib/common.sh" "$stage_root/lib/common.sh" || exit 1
cp -f "$SOURCE_ROOT/scripts/scan-projects.sh" "$SOURCE_ROOT/scripts/sync-projects.sh" \
  "$SOURCE_ROOT/scripts/create-reminders.applescript" "$SOURCE_ROOT/scripts/doctor.sh" \
  "$stage_root/scripts/" || exit 1
cp -f "$SOURCE_ROOT/launchd/$BPW_WATCH_LABEL.plist.template" \
  "$SOURCE_ROOT/launchd/$BPW_SYNC_LABEL.plist.template" "$stage_root/launchd/" || exit 1
cp -f "$SOURCE_ROOT/config/config.example" "$stage_root/config/config.example" || exit 1
cp -f "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/README.zh-CN.md" "$SOURCE_ROOT/LICENSE" \
  "$SOURCE_ROOT/CHANGELOG.md" "$SOURCE_ROOT/install.sh" "$SOURCE_ROOT/uninstall.sh" \
  "$stage_root/" || exit 1
for doc in "$SOURCE_ROOT"/docs/*.md; do cp -f "$doc" "$stage_root/docs/" || exit 1; done

chmod 755 "$stage_root/bin/bpw" "$stage_root/scripts/scan-projects.sh" \
  "$stage_root/scripts/sync-projects.sh" "$stage_root/scripts/doctor.sh" \
  "$stage_root/install.sh" "$stage_root/uninstall.sh" || exit 1
for script in "$stage_root/bin/bpw" "$stage_root/lib/common.sh" "$stage_root/scripts/scan-projects.sh" \
  "$stage_root/scripts/sync-projects.sh" "$stage_root/scripts/doctor.sh" \
  "$stage_root/install.sh" "$stage_root/uninstall.sh"; do
  zsh -n "$script" || { print -u2 -- "脚本语法检查失败：$script"; exit 1; }
done
osacompile -o "$stage_root/reminders.scpt" "$stage_root/scripts/create-reminders.applescript" >/dev/null 2>&1 || {
  print -u2 -- "AppleScript 编译检查失败"
  exit 1
}
rm -f "$stage_root/reminders.scpt"

BPW_ROOT="$stage_root" "$stage_root/bin/bpw" init || exit 1
bpw_load_config || exit 1
bpw_prepare_runtime_dirs || exit 1

watch_temp="$(mktemp "$AGENTS_DIR/.bpw-watch.XXXXXX")" || exit 1
sync_temp="$(mktemp "$AGENTS_DIR/.bpw-sync.XXXXXX")" || exit 1
bpw_render_launchd_plist "$stage_root/launchd/$BPW_WATCH_LABEL.plist.template" \
  "$watch_temp" "$SCAN_INTERVAL" "$BIN_DIR/bpw" || exit 1
bpw_render_launchd_plist "$stage_root/launchd/$BPW_SYNC_LABEL.plist.template" \
  "$sync_temp" "$SYNC_INTERVAL" "$BIN_DIR/bpw" || exit 1
plutil -lint "$watch_temp" >/dev/null || exit 1
plutil -lint "$sync_temp" >/dev/null || exit 1

old_root="$INSTALL_PARENT/.bpw-previous.$$"
if [[ -d "$BPW_INSTALL_ROOT" ]]; then
  mv "$BPW_INSTALL_ROOT" "$old_root" || exit 1
else
  old_root=""
fi
if ! mv "$stage_root" "$BPW_INSTALL_ROOT"; then
  [[ -n "$old_root" && -d "$old_root" ]] && mv "$old_root" "$BPW_INSTALL_ROOT"
  exit 1
fi
stage_root=""

cli_temp="$(mktemp "$BIN_DIR/.bpw.XXXXXX")" || exit 1
cp -f "$BPW_INSTALL_ROOT/bin/bpw" "$cli_temp" || exit 1
chmod 755 "$cli_temp" || exit 1
mv -f "$cli_temp" "$BIN_DIR/bpw" || exit 1

watch_existed=false
sync_existed=false
if [[ -f "$WATCH_PLIST" ]]; then
  watch_existed=true
  watch_backup="$AGENTS_DIR/.bpw-watch-previous.$$"
  cp -p "$WATCH_PLIST" "$watch_backup" || exit 1
fi
if [[ -f "$SYNC_PLIST" ]]; then
  sync_existed=true
  sync_backup="$AGENTS_DIR/.bpw-sync-previous.$$"
  cp -p "$SYNC_PLIST" "$sync_backup" || exit 1
fi
mv -f "$watch_temp" "$WATCH_PLIST" || exit 1
watch_temp=""
mv -f "$sync_temp" "$SYNC_PLIST" || exit 1
sync_temp=""

domain="gui/$(id -u)"
rollback_install() {
  launchctl bootout "$domain" "$WATCH_PLIST" >/dev/null 2>&1 || true
  launchctl bootout "$domain" "$SYNC_PLIST" >/dev/null 2>&1 || true
  if [[ "$watch_existed" == true && -f "$watch_backup" ]]; then mv -f "$watch_backup" "$WATCH_PLIST"; else rm -f "$WATCH_PLIST"; fi
  if [[ "$sync_existed" == true && -f "$sync_backup" ]]; then mv -f "$sync_backup" "$SYNC_PLIST"; else rm -f "$SYNC_PLIST"; fi
  if [[ -n "$old_root" && -d "$old_root" ]]; then
    rm -rf "$BPW_INSTALL_ROOT"
    mv "$old_root" "$BPW_INSTALL_ROOT"
    cli_temp="$(mktemp "$BIN_DIR/.bpw-rollback.XXXXXX")" || return 1
    cp -f "$BPW_INSTALL_ROOT/bin/bpw" "$cli_temp" && chmod 755 "$cli_temp" && mv -f "$cli_temp" "$BIN_DIR/bpw"
  else
    rm -rf "$BPW_INSTALL_ROOT"
    rm -f "$BIN_DIR/bpw"
  fi
  [[ "$watch_existed" == true ]] && launchctl bootstrap "$domain" "$WATCH_PLIST" >/dev/null 2>&1 || true
  [[ "$sync_existed" == true ]] && launchctl bootstrap "$domain" "$SYNC_PLIST" >/dev/null 2>&1 || true
}

launchctl bootout "$domain" "$WATCH_PLIST" >/dev/null 2>&1 || true
launchctl bootout "$domain" "$SYNC_PLIST" >/dev/null 2>&1 || true
if ! launchctl bootstrap "$domain" "$WATCH_PLIST"; then
  print -u2 -- "扫描服务加载失败，正在恢复旧版本：$WATCH_PLIST"
  rollback_install
  exit 1
fi
if ! launchctl bootstrap "$domain" "$SYNC_PLIST"; then
  print -u2 -- "备份服务加载失败，正在恢复旧版本：$SYNC_PLIST"
  rollback_install
  exit 1
fi
launchctl enable "$domain/$BPW_WATCH_LABEL" >/dev/null 2>&1 || true
launchctl enable "$domain/$BPW_SYNC_LABEL" >/dev/null 2>&1 || true

[[ -n "$old_root" && -d "$old_root" ]] && rm -rf "$old_root"
[[ -n "$watch_backup" && -f "$watch_backup" ]] && rm -f "$watch_backup"
[[ -n "$sync_backup" && -f "$sync_backup" ]] && rm -f "$sync_backup"

print -r -- "安装完成。"
print -r -- "命令位置：$BIN_DIR/bpw"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  print -r -- "请将以下内容加入 ~/.zshrc，然后重新打开终端："
  print -r -- "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
print -r -- "建议现在运行：$BIN_DIR/bpw doctor"
