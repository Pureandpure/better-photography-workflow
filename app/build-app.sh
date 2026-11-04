#!/bin/zsh
set -u

APP_DIR="${0:A:h}"
OUTPUT_DIR="${BPW_APP_OUTPUT_DIR:-$HOME/Library/Caches/better-photography-workflow/app}"
APP_BUNDLE="$OUTPUT_DIR/摄影工作流.app"

swift build -c release --scratch-path "${TMPDIR:-/tmp}/bpw-desktop-build-$(id -u)" --package-path "$APP_DIR" || exit 1
BIN_DIR="$(swift build -c release --scratch-path "${TMPDIR:-/tmp}/bpw-desktop-build-$(id -u)" --package-path "$APP_DIR" --show-bin-path)" || exit 1

if [[ -d "$APP_BUNDLE" && "${APP_BUNDLE:h}" == "$OUTPUT_DIR" ]]; then
  rm -rf "$APP_BUNDLE"
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" || exit 1
cp "$BIN_DIR/BPWDesktop" "$APP_BUNDLE/Contents/MacOS/BPWDesktop" || exit 1
cp "$APP_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist" || exit 1
chmod 755 "$APP_BUNDLE/Contents/MacOS/BPWDesktop" || exit 1
# Remove inherited Finder attributes only from the newly generated bundle.
xattr -cr "$APP_BUNDLE" || exit 1
codesign --force --sign - "$APP_BUNDLE" >/dev/null || exit 1

if ! codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
  # Some Documents File Providers continually recreate FinderInfo on app bundles.
  # Copy only this generated artifact outside that provider and verify it there.
  fallback_parent="$HOME/Library/Caches/better-photography-workflow/app"
  fallback_bundle="$fallback_parent/摄影工作流.app"
  mkdir -p "$fallback_parent" || exit 1
  [[ -d "$fallback_bundle" ]] && rm -rf "$fallback_bundle"
  ditto --norsrc --noextattr "$APP_BUNDLE" "$fallback_bundle" || exit 1
  codesign --verify --deep --strict "$fallback_bundle" || exit 1
  APP_BUNDLE="$fallback_bundle"
  print -r -- "Documents 文件提供者影响签名，已改为本机缓存输出。"
fi
print -r -- "应用已生成：$APP_BUNDLE"
