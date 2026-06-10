#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.apple.reproduce-xtrace-bug"
SCHEME="basic-swift-ios-app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT_DIR/basic-swift-ios-app.xcodeproj"
DERIVED_DATA="$ROOT_DIR/DerivedData"
TRACE_PATH="$ROOT_DIR/xctrace-app-launch-repro.trace"
LOG_DIR="$ROOT_DIR/repro-logs-$(date +%Y%m%d-%H%M%S)"
HOST_LOG_PID=""
SIM_LOG_PID=""
XCTRACE_PID=""

find_newest_ios_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

data = json.load(sys.stdin)
devices_by_runtime = data.get("devices", {})

def runtime_version(runtime):
    match = re.search(r"SimRuntime\.iOS-(\d+(?:-\d+)*)$", runtime)
    if not match:
        return None
    return tuple(int(part) for part in match.group(1).split("-"))

ios_runtimes = [runtime for runtime in devices_by_runtime if runtime_version(runtime) is not None]
for runtime in sorted(ios_runtimes, key=runtime_version, reverse=True):
    devices = [device for device in devices_by_runtime.get(runtime, []) if device.get("isAvailable")]
    if devices:
        print(devices[0]["udid"])
        sys.exit(0)

sys.exit("No available iOS Simulator devices found")
'
}

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
  UDID="$(find_newest_ios_simulator)"
fi

stop_log_streams() {
  if [[ -n "$HOST_LOG_PID" ]]; then
    kill -TERM "$HOST_LOG_PID" >/dev/null 2>&1 || true
    wait "$HOST_LOG_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "$SIM_LOG_PID" ]]; then
    kill -TERM "$SIM_LOG_PID" >/dev/null 2>&1 || true
    wait "$SIM_LOG_PID" >/dev/null 2>&1 || true
  fi
}

forward_signal() {
  local signal="$1"

  echo "Received SIG$signal; forwarding SIG$signal to xctrace pid $XCTRACE_PID" >&2
  if [[ -n "$XCTRACE_PID" ]]; then
    kill -"$signal" "$XCTRACE_PID" >/dev/null 2>&1 || true
    wait "$XCTRACE_PID" || true
  fi

  stop_log_streams
  exit 130
}

trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM
trap 'stop_log_streams' EXIT

echo "Using simulator UDID: $UDID"
echo "Building $BUNDLE_ID"
mkdir -p "$LOG_DIR"
echo "Capturing logs in: $LOG_DIR"

{
  echo "Date: $(date)"
  echo "Bundle ID: $BUNDLE_ID"
  echo "Simulator UDID: $UDID"
  echo
  xcodebuild -version
  echo
  xcrun xctrace version
  echo
  xcrun simctl list runtimes
  echo
  xcrun simctl list devices available
} >"$LOG_DIR/environment.log" 2>&1

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b 2>&1 | tee "$LOG_DIR/bootstatus.log"
open -a Simulator --args -CurrentDeviceUDID "$UDID"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build 2>&1 | tee "$LOG_DIR/xcodebuild.log"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app"

echo "Installing $APP_PATH"
xcrun simctl install "$UDID" "$APP_PATH" 2>&1 | tee "$LOG_DIR/install.log"

rm -rf "$TRACE_PATH"

log stream \
  --style compact \
  --level debug \
  --predicate 'process == "xctrace" OR process == "CoreSimulatorService" OR subsystem CONTAINS "com.apple.dt" OR subsystem CONTAINS "com.apple.CoreSimulator"' \
  >"$LOG_DIR/host.log" \
  2>"$LOG_DIR/host-log-stream.stderr.log" &
HOST_LOG_PID="$!"

xcrun simctl spawn "$UDID" log stream \
  --style compact \
  --level debug \
  --predicate 'eventMessage CONTAINS "DeveloperTools" OR eventMessage CONTAINS "debug" OR eventMessage CONTAINS "attach" OR eventMessage CONTAINS "instrument" OR eventMessage CONTAINS "profil" OR eventMessage CONTAINS "WaitForDebugger" OR eventMessage CONTAINS "StartSuspended"' \
  >"$LOG_DIR/simulator.log" \
  2>"$LOG_DIR/simulator-log-stream.stderr.log" &
SIM_LOG_PID="$!"

echo "Starting xctrace App Launch recording"
echo "Trace output: $TRACE_PATH"
echo "xctrace output: $LOG_DIR/xctrace.log"

xcrun xctrace record \
  --template "App Launch" \
  --device "$UDID" \
  --time-limit 5s \
  --output "$TRACE_PATH" \
  --no-prompt \
  --launch -- "$BUNDLE_ID" \
  >"$LOG_DIR/xctrace.log" \
  2>&1 &
XCTRACE_PID="$!"

echo "xctrace pid: $XCTRACE_PID"
wait "$XCTRACE_PID"
