#!/bin/bash
# Synthetic fallback checks; does not install, launch the GUI, or read real histories.
set -euo pipefail
cd "$(dirname "$0")/.."
B=.build-audit
CACHE="${TMPDIR:-/tmp}/whoosh-regression-module-cache"
mkdir -p "$B" "$CACHE"
swiftc -O -wmo -enable-testing -parse-as-library -module-cache-path "$CACHE" \
  -module-name RelayCore -emit-module -emit-module-path "$B/RelayCore.swiftmodule" \
  -emit-library -static -o "$B/libRelayCore.a" Sources/RelayCore/*.swift Sources/RelayCore/Providers/*.swift
swiftc -O -wmo -module-cache-path "$CACHE" -I "$B" \
  Sources/RelayApp/*.swift "$B/libRelayCore.a" -o "$B/Whoosh"
for TEST in performance-smoke native-pagination-smoke; do
  swiftc -module-cache-path "$CACHE" -I "$B" -parse-as-library \
    "scripts/$TEST.swift" "$B/libRelayCore.a" -o "$B/$TEST"
  "$B/$TEST"
done
export WHOOSH_TEST_NODE="${WHOOSH_TEST_NODE:-$(command -v node || true)}"
if [[ -n "$WHOOSH_TEST_NODE" ]]; then
  swiftc -O -wmo -parse-as-library -module-cache-path "$CACHE" -I "$B" \
    Sources/RelayApp/RelayModel.swift Sources/RelayApp/ClaudeSessionAdapter.swift \
    Sources/RelayApp/CodexInstallation.swift scripts/model-smoke.swift "$B/libRelayCore.a" -o "$B/model-smoke"
  "$B/model-smoke"
  if [[ -n "${WHOOSH_TEST_SDK:-}" ]]; then
    "$WHOOSH_TEST_NODE" scripts/claude-adapter-smoke.mjs "$WHOOSH_TEST_SDK"
  else
    echo 'SDK bridge test skipped: set WHOOSH_TEST_SDK to an existing sdk.mjs.'
  fi
else
  echo 'Model subprocess checks skipped: supply an existing Node via WHOOSH_TEST_NODE.'
fi
python3 scripts/check-contracts.py
