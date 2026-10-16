#!/usr/bin/env bash
# On a Mac with Xcode: records the scripted takes for the launch film in the newest iPhone Pro Max
# Simulator (Capture/CaptureTests.swift). Real app, real scrolling, demo data so every take matches.
# Usage: scripts/mac-capture.sh [out-dir]          (default: captures)
#        SIM_NAME="iPhone 17 Pro Max" scripts/mac-capture.sh
#        ONLY="test2HomeScroll test3ChartsSwipe" scripts/mac-capture.sh   (re-record some takes)
# Takes about 10 minutes. Close other heavy apps first: dropped frames show up in the recordings.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-captures}"
BUNDLE=com.lazet.blockpulse
TAKES=(test1HomeBlockFound test2HomeScroll test3ChartsSwipe test4PriceScrub)
[ -n "${ONLY:-}" ] && read -ra TAKES <<< "$ONLY"   # one or more take names, space separated

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

UDID=$(xcrun simctl list devices available -j | SIM_NAME="${SIM_NAME:-}" python3 -c '
import json, os, sys
want = os.environ.get("SIM_NAME", "")
phones = [d for r, ds in sorted(json.load(sys.stdin)["devices"].items()) if "iOS" in r for d in ds if d["name"].startswith("iPhone")]
pick = [d for d in phones if d["name"] == want] if want else [d for d in phones if d["name"].endswith("Pro Max")]
if not pick: sys.exit("No matching iPhone simulator" + (" named " + want if want else ""))
print(pick[-1]["udid"])')
echo "Simulator: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --operatorName ""
xcrun simctl uninstall "$UDID" "$BUNDLE" 2>/dev/null || true

DEST="platform=iOS Simulator,id=$UDID"
mkdir -p build "$OUT"
echo "Building..."
xcodebuild -project Blockpulse.xcodeproj -scheme BlockpulseCapture -destination "$DEST" \
  -derivedDataPath build/capture build-for-testing > build/capture-build.log 2>&1 \
  || { grep -E "error:" build/capture-build.log | sort -u; exit 1; }

run() {  # test name
  xcodebuild -project Blockpulse.xcodeproj -scheme BlockpulseCapture -destination "$DEST" \
    -derivedDataPath build/capture test-without-building \
    -only-testing:"BlockpulseCapture/CaptureTests/$1" > "build/capture-$1.log" 2>&1 \
    || { echo "  $1 failed, see build/capture-$1.log"; failed=1; return 1; }
}
failed=0

echo "Warming up (records the demo data, about 4 minutes)..."
run test0WarmUp || true

for take in "${TAKES[@]}"; do
  echo "Recording $take..."
  xcrun simctl io "$UDID" recordVideo --codec=h264 --mask=ignored --force "$OUT/$take.mp4" > /dev/null 2>&1 &
  rec=$!
  sleep 2
  run "$take" || true
  sleep 1
  kill -INT "$rec"; wait "$rec" 2>/dev/null || true
  echo "  saved $OUT/$take.mp4"
done

xcrun simctl status_bar "$UDID" clear || true
echo "Done. Takes are in $OUT/. Attach that folder in the Blockpulse launch video thread."
exit "$failed"
