#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore) / 90% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
swift test --enable-code-coverage

CODECOV_JSON="$(swift test --show-codecov-path)"
# swift test writes one merged export for every test bundle in the package.
python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$CODECOV_JSON"
