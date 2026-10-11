#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore) / 90% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
CODECOV_DIR="$(dirname "$(swift test --show-codecov-path)")"
rm -f "$CODECOV_DIR"/*.profraw
swift test --enable-code-coverage

# The swiftbuild backend builds one bundle per test target (HassCoreTests, HassDesignTests,
# HassUITests), and `swift test --show-codecov-path` exports only one of them, so HassDesign and
# HassUI went unmeasured. Merge every bundle's profiles and export all bundles together.
BIN="$(swift build --show-bin-path)"
PROFDATA="$CODECOV_DIR/all-bundles.profdata"
REPORT="$CODECOV_DIR/all-bundles.json"
xcrun llvm-profdata merge -sparse "$CODECOV_DIR"/*.profraw -o "$PROFDATA"
OBJECTS=()
for bundle in "$BIN"/*.xctest; do
  name="$(basename "$bundle" .xctest)"
  binary="$bundle/Contents/MacOS/$name"
  [[ -f "$binary" ]] || binary="$bundle"
  if [[ ${#OBJECTS[@]} -eq 0 ]]; then OBJECTS+=("$binary"); else OBJECTS+=(-object "$binary"); fi
done
xcrun llvm-cov export -format=text -summary-only -instr-profile "$PROFDATA" "${OBJECTS[@]}" > "$REPORT"
python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT"
