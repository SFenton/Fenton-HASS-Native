#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore) / 90% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
swift test --enable-code-coverage

# The profile data is merged across bundles, but swift test's own JSON export covers only one test
# binary, so re-export against every bundle (otherwise HassDesign and HassUI read as uncovered).
PROFDATA="$(dirname "$(swift test --show-codecov-path)")/default.profdata"
BIN="$(swift build --show-bin-path)"
OBJECTS=()
for bundle in "$BIN"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  OBJECTS+=("${#OBJECTS[@]}" "$bundle/Contents/MacOS/$name")
done
ARGS=("${OBJECTS[1]}")
for ((i = 3; i < ${#OBJECTS[@]}; i += 2)); do ARGS+=(-object "${OBJECTS[$i]}"); done
CODECOV_JSON="$BIN/codecov/all-bundles.json"
xcrun llvm-cov export -format=text -summary-only -instr-profile "$PROFDATA" "${ARGS[@]}" > "$CODECOV_JSON"
python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$CODECOV_JSON"
