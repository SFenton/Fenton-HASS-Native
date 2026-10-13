#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore) / 90% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Compile and test under a machine-wide `build` slot (tools/devcap.py), waiting when the Mac is full.
if [[ ",${DEVCAP_HELD:-}," != *",build,"* ]]; then
  exec python3 "$ROOT/tools/devcap.py" run --pool build --hold "${FENTON_DEVCAP_HOLD:-3600}" \
    --purpose "Fenton coverage ($(basename "$ROOT"))" -- bash "$0" "$@"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
swift test --enable-code-coverage

# swift test merges every bundle's profile into default.profdata, but its own JSON export reads only
# one test binary, which drops HassDesign and HassUI. Export once against every test binary instead.
CODECOV_DIR="$(dirname "$(swift test --show-codecov-path)")"
BIN_DIR="$(swift build --show-bin-path)"
OBJECTS=()
for bundle in "$BIN_DIR"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  OBJECTS+=(${OBJECTS[@]+-object} "$bundle/Contents/MacOS/$name")
done
REPORT="$CODECOV_DIR/all-bundles.json"
xcrun llvm-cov export -format=text -instr-profile "$CODECOV_DIR/default.profdata" "${OBJECTS[@]}" > "$REPORT"
python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT"
