#!/usr/bin/env bash
# One-shot Mac setup for Blockpulse: tools, signing team, project generation, tests, simulator build.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n==> %s\n' "$*"; }

step "Checking Xcode"
xcode-select -p >/dev/null || { echo "Install Xcode and run: xcode-select --install"; exit 1; }
xcodebuild -version | head -1

step "Checking XcodeGen"
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew install xcodegen
fi
xcodegen --version

step "Signing team"
if [[ ! -f Config/Local.xcconfig ]]; then
  read -r -p "Apple Developer Team ID (10 chars, Xcode → Settings → Accounts): " TEAM
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "Team ID looks wrong: $TEAM"; exit 1; }
  printf 'DEVELOPMENT_TEAM = %s\n' "$TEAM" > Config/Local.xcconfig
  echo "Wrote Config/Local.xcconfig"
else
  echo "Using existing Config/Local.xcconfig"
fi

step "Generating Blockpulse.xcodeproj"
xcodegen generate

step "BitcoinKit unit tests (macOS host)"
swift test --package-path Packages/BitcoinKit

step "Building app + widgets for the iOS Simulator"
xcodebuild -project Blockpulse.xcodeproj -scheme Blockpulse \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO | tail -25

step "BitcoinKit live smoke test against mempool.space (non-fatal)"
BLOCKPULSE_LIVE=1 swift test --package-path Packages/BitcoinKit --filter LiveSmokeTests \
  || echo "WARN: live smoke test failed (network?) — unit tests and build already passed"

step "Done. Opening Xcode — next: docs/MAC-SETUP.md (signing, device run, TestFlight)."
open Blockpulse.xcodeproj
