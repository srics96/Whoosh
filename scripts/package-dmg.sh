#!/bin/bash
# Package a self-contained, distributable Whoosh.dmg for Apple Silicon.
#
# The resulting app carries its own Node runtime and the read-only Claude Agent
# SDK, so it has NO dependency on the build machine's Homebrew/Node/toolchain.
# It is ad-hoc signed (no Apple Developer ID), so the first launch on another Mac
# needs a one-time System Settings -> Privacy & Security -> "Open Anyway".
#
# Whoosh still requires the Claude and/or Codex apps (and the Codex CLI for the
# Codex source) to be installed on the destination Mac — it moves chats between
# them; it cannot replace them.
#
# Usage: bash scripts/package-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then echo 'macOS only.' >&2; exit 1; fi

NODE_VERSION="v22.23.4"
ARCH="arm64"
CACHE=".dmg-cache"
NODE_DIR="$CACHE/node-$NODE_VERSION-darwin-$ARCH"
mkdir -p "$CACHE"

# 1. Portable Node runtime (official build; self-contained, links only system libs).
if [[ ! -x "$NODE_DIR/bin/node" ]]; then
  echo "Fetching Node $NODE_VERSION ($ARCH)…"
  curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-$ARCH.tar.gz" -o "$CACHE/node.tgz"
  tar xzf "$CACHE/node.tgz" -C "$CACHE"
fi

# 2. Claude Agent SDK present in adapter resources (read-only session reader).
if [[ ! -f Resources/ClaudeAdapter/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs ]]; then
  echo "Installing Claude Agent SDK…"
  ( cd Resources/ClaudeAdapter && npm ci --no-fund --no-audit )
fi

# 3. Build the app bundle (copies Resources/ClaudeAdapter, including node_modules).
bash scripts/build-app-direct.sh

APP="dist/Whoosh.app"
ADAPTER="$APP/Contents/Resources/ClaudeAdapter"

# 4. Prune the SDK's native `claude` CLI (~266 MB). The adapter is read-only and
#    never executes it (no query/resume/mutation), verified by list+read smoke tests.
rm -rf "$ADAPTER"/node_modules/@anthropic-ai/claude-agent-sdk-darwin-* \
       "$ADAPTER"/node_modules/@anthropic-ai/claude-agent-sdk-linux-* \
       "$ADAPTER"/node_modules/@anthropic-ai/claude-agent-sdk-win32-* 2>/dev/null || true

# 5. Bundle the portable Node and point the adapter at it with a RELATIVE path,
#    so it resolves inside the app wherever it is installed.
rm -rf "$ADAPTER/node-runtime"
mkdir -p "$ADAPTER/node-runtime/bin"
cp "$NODE_DIR/bin/node" "$ADAPTER/node-runtime/bin/node"
# Keep the complete version-matched Node and bundled-component notices.
test -s "$NODE_DIR/LICENSE"
cp "$NODE_DIR/LICENSE" "$ADAPTER/node-runtime/LICENSE"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
test -s "$ADAPTER/node_modules/@anthropic-ai/claude-agent-sdk/LICENSE.md"
chmod +x "$ADAPTER/node-runtime/bin/node"
printf '{"node":"node-runtime/bin/node","sdkModule":"./node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs"}\n' > "$ADAPTER/runtime.json"

# 6. Ad-hoc sign the bundled Node and any nested Mach-O, then the whole app.
codesign --force --timestamp=none --sign - "$ADAPTER/node-runtime/bin/node"
while IFS= read -r m; do codesign --force --timestamp=none --sign - "$m" 2>/dev/null || true; done < <(
  find "$ADAPTER/node_modules" -type f -perm +111 -exec sh -c 'file "$1" | grep -q "Mach-O" && echo "$1"' _ {} \;
)
codesign --force --deep --timestamp=none --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature: ok"

# 7. Assemble the DMG (app + Applications shortcut + install notes).
STAGING="$CACHE/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/Whoosh.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/INSTALL — read me.txt" <<'TXT'
Whoosh — install

1. Drag Whoosh into the Applications folder (shown here).
2. Open Applications and double-click Whoosh. This app is ad-hoc signed,
   not Developer ID signed or Apple-notarized. Expect a first-launch warning.
3. Only if you trust the official download and believe it was not tampered with,
   use System Settings > Privacy & Security > Open Anyway for Whoosh (if offered),
   then review and confirm Open. This exception does not verify malware safety.
   See https://support.apple.com/en-ie/102445 . Keep Gatekeeper enabled.
4. Whoosh lives in the menu bar (top-right). Press Cmd-Shift-Space to open it.

Whoosh carries local coding context between Claude Code and Codex. Desktop mode
needs the destination desktop app; Terminal (manual) needs its installed, signed-in
CLI. Codex reading needs its signed CLI, including the desktop app bundled copy.
Whoosh never sends anything automatically. Review the desktop draft, or run the
separately copied Terminal command and paste the handoff prompt, then send.
TXT

rm -f dist/Whoosh.dmg
hdiutil create -volname "Whoosh" -srcfolder "$STAGING" -ov -format UDZO -quiet dist/Whoosh.dmg

SIZE=$(du -h dist/Whoosh.dmg | cut -f1)
printf '\nBuilt distributable DMG: %s (%s)\n' "$PWD/dist/Whoosh.dmg" "$SIZE"
printf '%s\n' 'Ad-hoc signed; first launch on another Mac needs "Open Anyway" (see INSTALL note in the DMG).'
