#!/bin/zsh
set -u

APP_DIR="${0:A:h}"
OUTPUT_DIR="$APP_DIR/dist"
APP_BUNDLE="$OUTPUT_DIR/摄影工作流.app"

swift build -c release --package-path "$APP_DIR" || exit 1
BIN_DIR="$(swift build -c release --package-path "$APP_DIR" --show-bin-path)" || exit 1

if [[ -d "$APP_BUNDLE" && "${APP_BUNDLE:h}" == "$OUTPUT_DIR" ]]; then
  rm -rf "$APP_BUNDLE"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" || exit 1
cp "$BIN_DIR/BPWDesktop" "$APP_BUNDLE/Contents/MacOS/BPWDesktop" || exit 1
cp "$APP_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist" || exit 1
chmod 755 "$APP_BUNDLE/Contents/MacOS/BPWDesktop" || exit 1
codesign --force --sign - "$APP_BUNDLE" >/dev/null || exit 1

print -r -- "应用已生成：$APP_BUNDLE"
