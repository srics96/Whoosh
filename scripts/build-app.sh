#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Blink is a macOS app. Build on macOS 13+ with Xcode Command Line Tools.' >&2
  exit 1
fi
swift test
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Blink.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Blink" "$APP/Contents/MacOS/Blink"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Blink.icns "$APP/Contents/Resources/Blink.icns"
cp -R Resources/ClaudeAdapter "$APP/Contents/Resources/"
# Optional, already-installed SDK only. This script never installs packages.
if [[ -n "${BLINK_CLAUDE_SDK_MODULE:-}" && -n "${BLINK_NODE:-}" ]]; then
  python3 scripts/configure-claude-adapter.py "$APP" "$BLINK_NODE" "$BLINK_CLAUDE_SDK_MODULE"
fi
chmod +x "$APP/Contents/MacOS/Blink"
# Ad-hoc signing is local-only. No identity, upload, installer or notarization is used.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '\nBuilt local prototype: %s\n' "$APP"
printf '%s\n' 'Not launched or installed. Open this bundle manually when ready.'
