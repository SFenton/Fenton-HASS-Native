#!/usr/bin/env bash
# SwiftPM coverage gate: runs every package test bundle with LLVM coverage on the macOS host and
# requires 95% logic (HassCore + HassTelemetry) / 95% UX (HassDesign + HassUI) lines. Ported from FestivalNativeApps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Every file under apple/Sources must be classified in contracts/coverage-rules.json. Check before taking a
# build slot, so a new module or file fails here by name instead of as missing coverage after the build.
python3 "$ROOT/tools/coverage_gate.py" --language swift --classify-only
# Compile and test under a machine-wide `build` slot (tools/devcap.py), waiting when the Mac is full.
if [[ ",${DEVCAP_HELD:-}," != *",build,"* ]]; then
  exec python3 "$ROOT/tools/devcap.py" run --pool build --hold "${FENTON_DEVCAP_HOLD:-3600}" \
    --purpose "Fenton coverage ($(basename "$ROOT"))" -- bash "$0" "$@"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT/apple"
CODECOV_DIR="$(dirname "$(swift test --show-codecov-path)")"
# Merge this run's raw profiles ourselves: swift test skips its merge when a test fails, and a stale
# default.profdata would then be exported against new binaries.
rm -f "$CODECOV_DIR"/*.profraw "$CODECOV_DIR/default.profdata"
TEST_STATUS=0
swift test --enable-code-coverage || TEST_STATUS=$?
shopt -s nullglob
PROFILES=("$CODECOV_DIR"/*.profraw)
if (( ${#PROFILES[@]} == 0 )); then
  echo "ERROR: swift test (exit $TEST_STATUS) wrote no coverage profiles to $CODECOV_DIR" >&2
  exit 1
fi
xcrun llvm-profdata merge -sparse "${PROFILES[@]}" -o "$CODECOV_DIR/default.profdata"

# swift test's own JSON export reads only one test binary, which drops HassDesign and HassUI. Export
# once against every test binary instead.
BIN_DIR="$(swift build --show-bin-path)"
OBJECTS=()
for bundle in "$BIN_DIR"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  OBJECTS+=(${OBJECTS[@]+-object} "$bundle/Contents/MacOS/$name")
done
REPORT="$CODECOV_DIR/all-bundles.json"
xcrun llvm-cov export -format=text -instr-profile "$CODECOV_DIR/default.profdata" "${OBJECTS[@]}" > "$REPORT"
GATE_STATUS=0
python3 "$ROOT/tools/coverage_gate.py" --language swift --report "$REPORT" || GATE_STATUS=$?
# A failing test fails the gate even when the numbers pass; the numbers above still come from this run.
if (( TEST_STATUS != 0 )); then
  echo "ERROR: swift test failed (exit $TEST_STATUS); coverage above is from a run with failing tests" >&2
  exit "$TEST_STATUS"
fi
exit "$GATE_STATUS"
