#!/usr/bin/env bash
# Runs the XCUITest journeys (sign-in, Home, layout, accessibility audits) on iPhone, iPhone Duo and
# iPad, one simulator at a time. Credentials are read at runtime from a local env file and passed as
# TEST_RUNNER_ variables; they are never printed or committed.
#
# Usage: tools/ios_uitest.sh [--env path/to/temp.env] [--only iphone|duo|ipad] [extra xcodebuild args]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ENV_FILE=""
ONLY=""
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

# Simulator names; override with FENTON_SIM_IPHONE / FENTON_SIM_DUO / FENTON_SIM_IPAD.
# (macOS ships bash 3.2: no associative arrays.)
device_name() {
  case "$1" in
    iphone) echo "${FENTON_SIM_IPHONE:-iPhone 17 Pro}" ;;
    duo) echo "${FENTON_SIM_DUO:-iPhone Duo}" ;;
    ipad) echo "${FENTON_SIM_IPAD:-iPad Pro 11-inch (M5)}" ;;
  esac
}

if [[ -n "$ENV_FILE" ]]; then
  # Accept KEY=VALUE lines; map common names onto the runner variables without echoing them.
  set -a; source "$ENV_FILE"; set +a
  export TEST_RUNNER_FENTON_HASS_USERNAME="${FENTON_HASS_USERNAME:-${HASS_USERNAME:-${HA_USERNAME:-${USERNAME:-}}}}"
  export TEST_RUNNER_FENTON_HASS_PASSWORD="${FENTON_HASS_PASSWORD:-${HASS_PASSWORD:-${HA_PASSWORD:-${PASSWORD:-}}}}"
  # FENTON_UITEST_NO_TOKEN=1 forces the password login flow.
  [[ "${FENTON_UITEST_NO_TOKEN:-}" == 1 ]] || export TEST_RUNNER_FENTON_HASS_TOKEN="${FENTON_HASS_TOKEN:-${HASS_TOKEN:-${TOKEN:-}}}"
  SERVER="${FENTON_HASS_SERVER:-${HASS_URL:-${HA_URL:-}}}"
  [[ -n "$SERVER" ]] && export TEST_RUNNER_FENTON_HASS_SERVER="$SERVER"
fi

cd "$ROOT/apple"
xcodegen generate --quiet
STATUS=0
for family in iphone duo ipad; do
  [[ -n "$ONLY" && "$ONLY" != "$family" ]] && continue
  name="$(device_name "$family")"
  if ! xcrun simctl list devices available | grep -q "    $name ("; then
    echo "GAP: no available simulator named '$name' for $family (a gap, not a pass)"; STATUS=1; continue
  fi
  # Resolve the UDID: xcodebuild's name= matcher misses names with parentheses ("iPhone 17 Pro (Rooms)").
  udid="$(xcrun simctl list devices available | NAME="$name" awk '{ line = $0; sub(/^ +/, "", line); if (match(line, / \([0-9A-F-]{36}\)/) && substr(line, 1, RSTART - 1) == ENVIRON["NAME"]) { print substr(line, RSTART + 2, 36); exit } }')"
  echo "== $family: $name ($udid)"
  rm -rf "$ROOT/apple/.build/uitest-$family.xcresult"
  xcodebuild test -project FentonHome.xcodeproj -scheme FentonHome \
    -destination "platform=iOS Simulator,id=$udid" \
    -resultBundlePath "$ROOT/apple/.build/uitest-$family.xcresult" \
    ${EXTRA[@]+"${EXTRA[@]}"} || STATUS=1
  [[ -n "${FENTON_KEEP_SIM:-}" ]] || xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
done
exit $STATUS
