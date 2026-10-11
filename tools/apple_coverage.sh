#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore) / 90% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
swift test --enable-code-coverage

# `swift test`'s own export covers only the first test bundle, so export every bundle together
# (one merged report: a file shared by two bundles is counted once, with hits from both).
CODECOV_JSON="$(swift test --show-codecov-path)"
CODECOV_DIR="$(dirname "$CODECOV_JSON")"
PRODUCTS="$(dirname "$CODECOV_DIR")"
OBJECTS=()
for bundle in "$PRODUCTS"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  OBJECTS+=(-object "$bundle/Contents/MacOS/$name")
done
MERGED="$CODECOV_DIR/all-bundles.json"
xcrun llvm-cov export -format=text -instr-profile "$CODECOV_DIR/default.profdata" "${OBJECTS[@]}" > "$MERGED"
python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$MERGED"
