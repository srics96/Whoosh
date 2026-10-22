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
  ( cd Resources/ClaudeAdapter && npm install --no-fund --no-audit )
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
2. Open Applications and double-click Whoosh. macOS will say it "cannot be
   opened because Apple cannot check it for malicious software."
3. Open  > System Settings > Privacy & Security, scroll down, and click
   "Open Anyway" next to Whoosh. Confirm. (One time only.)
4. Whoosh lives in the menu bar (top-right). Press Cmd-Shift-Space to open it.

Whoosh moves a conversation between Claude and Codex. Those apps (and the Codex
CLI for the Codex side) must be installed on this Mac for it to have anything
to read from or open into. Whoosh never sends anything automatically — it opens
a pre-filled draft for you to review and press Send.
TXT

rm -f dist/Whoosh.dmg
hdiutil create -volname "Whoosh" -srcfolder "$STAGING" -ov -format UDZO -quiet dist/Whoosh.dmg
xattr -c dist/Whoosh.dmg 2>/dev/null || true

SIZE=$(du -h dist/Whoosh.dmg | cut -f1)
printf '\nBuilt distributable DMG: %s (%s)\n' "$PWD/dist/Whoosh.dmg" "$SIZE"
printf '%s\n' 'Ad-hoc signed; first launch on another Mac needs "Open Anyway" (see INSTALL note in the DMG).'
