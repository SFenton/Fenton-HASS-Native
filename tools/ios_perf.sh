#!/usr/bin/env bash
# Runs the fast-scroll performance tests (FastScrollPerformanceTests) on a physical iPhone or iPad, where hitch
# numbers mean something. Simulators report false data; the measured tests skip there.
#
# Usage:
#   tools/ios_perf.sh --device <udid|name> [--live --env path/to/temp.env] [--only testFlickRecipes] [extra xcodebuild args]
#
#   --device   A connected device (`xcrun xctrace list devices`). Signing uses the team in project.yml.
#   --live     Also flick the live tab pages (needs sign-in credentials from --env).
#   --only     One test method instead of the whole class.
#
# Results: apple/.build/perf-<timestamp>.xcresult. Open it in Xcode (Report navigator → the test → Metrics) to
# see each page's scroll hitch ratio, EntityUpdate/ImageDecode signposts, clock and CPU, and set baselines.
# The app's own measurements are on the device too: Settings → Performance → Export Telemetry.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DEVICE=""
ENV_FILE=""
LIVE=""
ONLY=""
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --env) ENV_FILE="$2"; shift 2 ;;
    --live) LIVE=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done
[[ -n "$DEVICE" ]] || { echo "usage: tools/ios_perf.sh --device <udid|name> [--live --env file] [--only testName]"; exit 2; }

if [[ -n "$ENV_FILE" ]]; then
  # Credentials are mapped onto runner variables without echoing them.
  set -a; source "$ENV_FILE"; set +a
  export TEST_RUNNER_FENTON_HASS_USERNAME="${FENTON_HASS_USERNAME:-${HASS_USERNAME:-${HA_USERNAME:-}}}"
  export TEST_RUNNER_FENTON_HASS_PASSWORD="${FENTON_HASS_PASSWORD:-${HASS_PASSWORD:-${HA_PASSWORD:-}}}"
  export TEST_RUNNER_FENTON_HASS_TOKEN="${FENTON_HASS_TOKEN:-${HASS_TOKEN:-}}"
  SERVER="${FENTON_HASS_SERVER:-${HASS_URL:-${HA_URL:-}}}"
  [[ -n "$SERVER" ]] && export TEST_RUNNER_FENTON_HASS_SERVER="$SERVER"
fi
[[ -n "$LIVE" ]] && export TEST_RUNNER_FENTON_PERF_LIVE=1

# A name resolves to its UDID.
if [[ ! "$DEVICE" =~ ^[0-9A-Fa-f-]{20,}$ ]]; then
  DEVICE="$(xcrun xctrace list devices 2>/dev/null | grep -v Simulator | grep -F "$DEVICE" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{20,})\)$/\1/')"
  [[ -n "$DEVICE" ]] || { echo "No connected device matches that name"; exit 2; }
fi

cd "$ROOT/apple"
xcodegen generate --quiet
TARGET="FentonHomeUITests/FastScrollPerformanceTests${ONLY:+/$ONLY}"
RESULT="$ROOT/apple/.build/perf-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild test -project FentonHome.xcodeproj -scheme FentonHome \
  -destination "platform=iOS,id=$DEVICE" -allowProvisioningUpdates \
  -only-testing:"$TARGET" -resultBundlePath "$RESULT" \
  ${EXTRA[@]+"${EXTRA[@]}"}
echo "Results: $RESULT"
