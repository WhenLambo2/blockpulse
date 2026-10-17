#!/usr/bin/env bash
# Boots an iPhone simulator, installs the built app and screenshots all three tabs (dark and light).
# Usage: scripts/ci-screenshots.sh path/to/Blockpulse.app out-dir
# SIM_NAME="iPhone 17 Pro Max" picks a specific simulator (newest iOS runtime wins); default: an iPhone Pro.
set -euo pipefail
APP="$1"; OUT="$2"; BUNDLE=com.lazet.blockpulse
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | SIM_NAME="${SIM_NAME:-}" python3 -c '
import json, os, sys
want = os.environ.get("SIM_NAME", "")
devices = [d for runtime, ds in sorted(json.load(sys.stdin)["devices"].items()) if "iOS" in runtime for d in ds]
phones = [d for d in devices if d["name"].startswith("iPhone")]
if want:
    named = [d for d in phones if d["name"] == want]
    if not named: sys.exit("No available simulator named " + want)
    print(named[-1]["udid"]); sys.exit()
pro = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
print((pro or phones)[-1]["udid"])')
echo "Simulator: $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

shot() {  # name, launch args...
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@"
  sleep 20
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  echo "Saved $OUT/$name.png"
}

shot 1-home-dark       -selectedTab pulse    -appearance dark -feeTilesShowFiat NO
shot 2-charts-dark     -selectedTab charts   -appearance dark -chartsCategory favourites
shot 3-mining-dark     -selectedTab charts   -appearance dark -chartsCategory mining
shot 4-blocks-dark     -selectedTab charts   -appearance dark -chartsCategory favourites -chartFavourites '(recentBlocks, difficultyHistory)'
shot 5-settings-dark   -selectedTab settings -appearance dark
shot 9-explore-dark    -selectedTab explore  -appearance dark
shot 10-tx-dark        -selectedTab explore  -appearance dark -openLink blockpulse://tx/f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16
shot 11-block-dark     -selectedTab explore  -appearance dark -openLink blockpulse://block/840000
shot 12-address-dark   -selectedTab explore  -appearance dark -openLink blockpulse://address/bc1qm34lsc65zpw79lxes69zkqmk6ee3ewf0j77s3h
shot 6-home-light      -selectedTab pulse    -appearance light -feeTilesShowFiat YES
shot 7-market-light    -selectedTab charts   -appearance light -chartsCategory market
shot 8-celebrate-dark  -selectedTab pulse    -appearance dark -celebrateAfter 18.0

# A crash leaves no process behind; fail loudly instead of shipping blank screenshots.
# (Read the list into a variable first: `grep -q` closing the pipe early makes simctl die of SIGPIPE.)
running=$(xcrun simctl spawn "$UDID" launchctl list)
grep -q "$BUNDLE" <<<"$running" || { echo "App is not running (crashed?)"; exit 1; }
