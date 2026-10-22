#!/bin/bash
# Direct swiftc build that bypasses SwiftPM.
#
# Use this when `swift build` fails at the manifest step on a Command Line Tools
# install whose bundled libPackageDescription.dylib does not match its own
# PackageDescription.swiftinterface (an "Invalid manifest / Undefined symbols:
# PackageDescription.Package.__allocating_init" link error). The application
# sources themselves compile fine with swiftc; only SwiftPM's manifest runner is
# broken, so this compiles the two targets directly and assembles dist/Whoosh.app.
#
# It produces the same bundle layout as scripts/build-app.sh and ad-hoc signs it
# for local testing. It does not install, launch, upload or notarize anything.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Whoosh is a macOS app. Build on macOS 13+ with the Xcode Command Line Tools.' >&2
  exit 1
fi

B=".build-direct"
rm -rf "$B"
mkdir -p "$B"

CORE_SOURCES=$(find Sources/RelayCore -name '*.swift' | sort)
APP_SOURCES=$(find Sources/RelayApp -name '*.swift' | sort)

echo "Compiling RelayCore…"
# shellcheck disable=SC2086
xcrun swiftc -O -wmo -parse-as-library \
  -module-name RelayCore \
  -emit-module -emit-module-path "$B/RelayCore.swiftmodule" \
  -emit-library -static -o "$B/libRelayCore.a" \
  $CORE_SOURCES

echo "Compiling Whoosh (RelayApp)…"
# shellcheck disable=SC2086
xcrun swiftc -O -wmo \
  -module-name Whoosh \
  -I "$B" \
  -o "$B/Whoosh" \
  $APP_SOURCES \
  "$B/libRelayCore.a"

APP="$PWD/dist/Whoosh.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$B/Whoosh" "$APP/Contents/MacOS/Whoosh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Whoosh.icns "$APP/Contents/Resources/Whoosh.icns"
cp -R Resources/ClaudeAdapter "$APP/Contents/Resources/"

# Wire up the "From Claude Code" source if its SDK has been installed into the
# adapter resources (run `npm install` inside Resources/ClaudeAdapter first).
# This writes runtime.json pointing at the local Node; with no SDK present the
# Claude source stays disabled and only the Codex source is available.
ADAPTER="$APP/Contents/Resources/ClaudeAdapter"
SDK_REL="node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs"
if [[ -f "$ADAPTER/$SDK_REL" ]]; then
  NODE_BIN="${BLINK_NODE:-$(command -v node || true)}"
  if [[ -n "$NODE_BIN" && -x "$NODE_BIN" ]]; then
    printf '{"node":"%s","sdkModule":"./%s"}\n' "$NODE_BIN" "$SDK_REL" > "$ADAPTER/runtime.json"
    printf 'Claude Code source: wired up (node=%s)\n' "$NODE_BIN"
  else
    rm -f "$ADAPTER/runtime.json"
    printf 'Claude Code source: SDK present but no node found; set BLINK_NODE. Claude source disabled.\n'
  fi
else
  rm -f "$ADAPTER/runtime.json"
  printf 'Claude Code source: SDK not installed; Claude source disabled (Codex source still works).\n'
fi

chmod +x "$APP/Contents/MacOS/Whoosh"

# Ad-hoc signing is local-only. No identity, upload, installer or notarization is used.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

printf '\nBuilt local prototype: %s\n' "$APP"
printf '%s\n' 'Not launched or installed. Open this bundle manually when ready.'
