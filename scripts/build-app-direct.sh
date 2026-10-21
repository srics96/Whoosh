#!/bin/bash
# Direct swiftc build that bypasses SwiftPM.
#
# Use this when `swift build` fails at the manifest step on a Command Line Tools
# install whose bundled libPackageDescription.dylib does not match its own
# PackageDescription.swiftinterface (an "Invalid manifest / Undefined symbols:
# PackageDescription.Package.__allocating_init" link error). The application
# sources themselves compile fine with swiftc; only SwiftPM's manifest runner is
# broken, so this compiles the two targets directly and assembles dist/Blink.app.
#
# It produces the same bundle layout as scripts/build-app.sh and ad-hoc signs it
# for local testing. It does not install, launch, upload or notarize anything.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Blink is a macOS app. Build on macOS 13+ with the Xcode Command Line Tools.' >&2
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

echo "Compiling Blink (RelayApp)…"
# shellcheck disable=SC2086
xcrun swiftc -O -wmo \
  -module-name Blink \
  -I "$B" \
  -o "$B/Blink" \
  $APP_SOURCES \
  "$B/libRelayCore.a"

APP="$PWD/dist/Blink.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$B/Blink" "$APP/Contents/MacOS/Blink"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Blink.icns "$APP/Contents/Resources/Blink.icns"
cp -R Resources/ClaudeAdapter "$APP/Contents/Resources/"
chmod +x "$APP/Contents/MacOS/Blink"

# Ad-hoc signing is local-only. No identity, upload, installer or notarization is used.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

printf '\nBuilt local prototype: %s\n' "$APP"
printf '%s\n' 'Not launched or installed. Open this bundle manually when ready.'
