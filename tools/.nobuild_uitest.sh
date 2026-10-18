#!/usr/bin/env bash
# Runs the XCUITest journeys (sign-in, Home, layout, accessibility audits) on iPhone, iPhone Duo and
# iPad, one simulator at a time. Credentials are read at runtime from a local env file and passed as
# TEST_RUNNER_ variables; they are never printed or committed.
#
# Capacity: the app compiles once under a machine-wide `build` slot, then each family runs under its
# device gate plus a `simulator` slot (tools/devcap.py, shared with FestivalNativeApps). When the Mac is
# full the script waits its turn; `python3 tools/devcap.py status` shows who holds what.
#
# Usage: tools/ios_uitest.sh [--env path/to/temp.env] [--only iphone|duo|ipad] [--appearance light|dark] [extra xcodebuild args]
#   --appearance draws every sheet in that appearance (FENTON_APPEARANCE; pages stay dark). Without it sheets follow the
#   simulator's own setting.
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
    --appearance) export TEST_RUNNER_FENTON_APPEARANCE="$2"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

# Simulator names; override with FENTON_SIM_IPHONE / FENTON_SIM_DUO / FENTON_SIM_IPAD to pin one device.
# Without an override each family draws from a pool of identical simulators ("<name>", "<name> (pool 2)", …,
# FENTON_SIM_POOL members, default the simulator slot count), so lanes on the same device type run in
# parallel; a lane keeps its last (warm) pool member while it is free.
# (macOS ships bash 3.2: no associative arrays.)
pinned_name() {
  case "$1" in
    iphone) echo "${FENTON_SIM_IPHONE:-}" ;;
    duo) echo "${FENTON_SIM_DUO:-}" ;;
    ipad) echo "${FENTON_SIM_IPAD:-}" ;;
  esac
}
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

DEVCAP=(python3 "$ROOT/tools/devcap.py" run --hold "${FENTON_DEVCAP_HOLD:-3600}")
# Build settings (NAME=value) also apply to the compile; test options (-only-testing:…) only to the runs.
SETTINGS=()
for arg in ${EXTRA[@]+"${EXTRA[@]}"}; do
  [[ "$arg" =~ ^[A-Z_][A-Z0-9_]*= ]] && SETTINGS+=("$arg")
done
LANE="$(basename "$ROOT")"
FULL_SUITE=1
for arg in ${EXTRA[@]+"${EXTRA[@]}"}; do
  [[ "$arg" == -only-testing* || "$arg" == -skip-testing* ]] && FULL_SUITE=0
done

# Runs one family's journeys inside its devcap hold. The simulator stays booted (warm) afterwards so the
# lane's next run skips the boot; it still counts against the simulator slots, and devcap shuts it down
# after 60 s idle when another lane is waiting, or 5 min idle otherwise. A hung run (hold timeout) shuts it
# down at once. A full-suite run (no -only-testing/-skip-testing filter) ran every test for the device, so
# it shuts the simulator down when it finishes; so does FENTON_SHUTDOWN_SIM=1 (the lane is done with it).
run_family() {
  local family="$1" udid="$2" status=0
  xcodebuild test-without-building -project FentonHome.xcodeproj -scheme FentonHome \
    -destination "platform=iOS Simulator,id=$udid" \
    -resultBundlePath "$ROOT/apple/.build/uitest-$family.xcresult" \
    ${EXTRA[@]+"${EXTRA[@]}"} || status=1
  return $status
}
export -f run_family
export ROOT

cd "$ROOT/apple"
STATUS=0
for family in iphone duo ipad; do
  [[ -n "$ONLY" && "$ONLY" != "$family" ]] && continue
  name="$(device_name "$family")"
  if ! xcrun simctl list devices available | grep -q "    $name ("; then
    echo "GAP: no available simulator named '$name' for $family (a gap, not a pass)"; STATUS=1; continue
  fi
  last_file="$ROOT/apple/.build/uitest-$family.udid"
  if [[ -n "$(pinned_name "$family")" ]]; then
    # Resolve the UDID: xcodebuild's name= matcher misses names with parentheses ("iPhone 17 Pro (Rooms)").
    udid="$(xcrun simctl list devices available | NAME="$name" awk '{ line = $0; sub(/^ +/, "", line); if (match(line, / \([0-9A-F-]{36}\)/) && substr(line, 1, RSTART - 1) == ENVIRON["NAME"]) { print substr(line, RSTART + 2, 36); exit } }')"
  else
    prefer=()
    [[ -s "$last_file" ]] && prefer=(--prefer "$(cat "$last_file")")
    udid="$(python3 "$ROOT/tools/devcap.py" pick-sim --name "$name" --pool "${FENTON_SIM_POOL:-0}" ${prefer[@]+"${prefer[@]}"})"
  fi
  mkdir -p "$(dirname "$last_file")"; echo "$udid" > "$last_file"
  echo "== $family: $name pool ($udid)"
  rm -rf "$ROOT/apple/.build/uitest-$family.xcresult"
  SHUTDOWN=(--shutdown-on-timeout)
  [[ "${FENTON_SHUTDOWN_SIM:-}" == 1 || $FULL_SUITE == 1 ]] && SHUTDOWN=(--shutdown)
  "${DEVCAP[@]}" --sim "$udid" ${SHUTDOWN[@]+"${SHUTDOWN[@]}"} --purpose "Fenton uitest $family ($LANE)" -- \
    bash -c 'EXTRA=("${@:3}"); run_family "$1" "$2"' _ "$family" "$udid" ${EXTRA[@]+"${EXTRA[@]}"} || STATUS=1
done
exit $STATUS
