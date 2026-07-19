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

mkdir -p "$BPW_INSTALL_ROOT/bin" "$BPW_INSTALL_ROOT/lib" "$BPW_INSTALL_ROOT/scripts" \
  "$BPW_INSTALL_ROOT/launchd" "$BPW_INSTALL_ROOT/config" "$BPW_INSTALL_ROOT/docs" \
  "$BIN_DIR" "$AGENTS_DIR" || exit 1

if [[ "${SOURCE_ROOT:A}" != "${BPW_INSTALL_ROOT:A}" ]]; then
  cp -f "$SOURCE_ROOT/bin/bpw" "$BPW_INSTALL_ROOT/bin/bpw" || exit 1
  cp -f "$SOURCE_ROOT/lib/common.sh" "$BPW_INSTALL_ROOT/lib/common.sh" || exit 1
  cp -f "$SOURCE_ROOT/scripts/scan-projects.sh" "$SOURCE_ROOT/scripts/sync-projects.sh" \
    "$SOURCE_ROOT/scripts/create-reminders.applescript" "$SOURCE_ROOT/scripts/doctor.sh" \
    "$BPW_INSTALL_ROOT/scripts/" || exit 1
  cp -f "$SOURCE_ROOT/launchd/$BPW_WATCH_LABEL.plist.template" \
    "$SOURCE_ROOT/launchd/$BPW_SYNC_LABEL.plist.template" "$BPW_INSTALL_ROOT/launchd/" || exit 1
  cp -f "$SOURCE_ROOT/config/config.example" "$BPW_INSTALL_ROOT/config/config.example" || exit 1
  cp -f "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/README.zh-CN.md" "$SOURCE_ROOT/LICENSE" \
    "$SOURCE_ROOT/CHANGELOG.md" "$SOURCE_ROOT/install.sh" "$SOURCE_ROOT/uninstall.sh" \
    "$BPW_INSTALL_ROOT/" || exit 1
  for doc in "$SOURCE_ROOT"/docs/*.md; do cp -f "$doc" "$BPW_INSTALL_ROOT/docs/" || exit 1; done
fi

chmod 755 "$BPW_INSTALL_ROOT/bin/bpw" "$BPW_INSTALL_ROOT/scripts/scan-projects.sh" \
  "$BPW_INSTALL_ROOT/scripts/sync-projects.sh" "$BPW_INSTALL_ROOT/scripts/doctor.sh" \
  "$BPW_INSTALL_ROOT/install.sh" "$BPW_INSTALL_ROOT/uninstall.sh" || exit 1
cp -f "$BPW_INSTALL_ROOT/bin/bpw" "$BIN_DIR/bpw" || exit 1
chmod 755 "$BIN_DIR/bpw" || exit 1

BPW_ROOT="$BPW_INSTALL_ROOT" "$BIN_DIR/bpw" init || exit 1
bpw_load_config || exit 1
bpw_prepare_runtime_dirs || exit 1

bpw_render_launchd_plist "$BPW_INSTALL_ROOT/launchd/$BPW_WATCH_LABEL.plist.template" \
  "$WATCH_PLIST" "$SCAN_INTERVAL" "$BIN_DIR/bpw" || exit 1
bpw_render_launchd_plist "$BPW_INSTALL_ROOT/launchd/$BPW_SYNC_LABEL.plist.template" \
  "$SYNC_PLIST" "$SYNC_INTERVAL" "$BIN_DIR/bpw" || exit 1
plutil -lint "$WATCH_PLIST" >/dev/null || exit 1
plutil -lint "$SYNC_PLIST" >/dev/null || exit 1

domain="gui/$(id -u)"
launchctl bootout "$domain" "$WATCH_PLIST" >/dev/null 2>&1 || true
launchctl bootout "$domain" "$SYNC_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "$domain" "$WATCH_PLIST" || { print -u2 -- "扫描服务加载失败：$WATCH_PLIST"; exit 1; }
launchctl bootstrap "$domain" "$SYNC_PLIST" || { print -u2 -- "备份服务加载失败：$SYNC_PLIST"; exit 1; }
launchctl enable "$domain/$BPW_WATCH_LABEL" >/dev/null 2>&1 || true
launchctl enable "$domain/$BPW_SYNC_LABEL" >/dev/null 2>&1 || true

print -r -- "安装完成。"
print -r -- "命令位置：$BIN_DIR/bpw"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  print -r -- "请将以下内容加入 ~/.zshrc，然后重新打开终端："
  print -r -- "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
print -r -- "建议现在运行：$BIN_DIR/bpw doctor"
