#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-contracts.py
if command -v swift >/dev/null 2>&1; then
  swift test
else
  printf '%s\n' 'Swift not installed: Swift compilation and tests were NOT RUN.'
fi
