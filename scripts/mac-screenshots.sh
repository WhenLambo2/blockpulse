#!/usr/bin/env bash
# On a Mac with Xcode: builds the app for the Simulator and saves full-resolution screenshots of every
# tab in dark and light, for the App Store and blockpul.se.
# Usage: scripts/mac-screenshots.sh [out-dir]        (default: screenshots)
#        SIM_NAME="iPhone 17 Pro Max" scripts/mac-screenshots.sh
# App Store needs 6.9" shots (Pro Max, 1320 x 2868); the default here is the newest Pro Max available.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-screenshots}"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
mkdir -p build
xcodebuild -project Blockpulse.xcodeproj -scheme Blockpulse -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build > build/xcodebuild.log 2>&1 || { grep -E "error:" build/xcodebuild.log | sort -u; exit 1; }
if [ -z "${SIM_NAME:-}" ]; then
  SIM_NAME=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
phones = [d["name"] for r, ds in sorted(json.load(sys.stdin)["devices"].items()) if "iOS" in r for d in ds if d["name"].startswith("iPhone")]
maxes = [n for n in phones if n.endswith("Pro Max")]
print((maxes or phones)[-1])')
fi
echo "Simulator: $SIM_NAME"
SIM_NAME="$SIM_NAME" scripts/ci-screenshots.sh build/dd/Build/Products/Release-iphonesimulator/Blockpulse.app "$OUT"
echo "Screenshots in $OUT"
