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
if [[ -f Config/Local.xcconfig ]]; then
  echo "Config/Local.xcconfig overrides the Arterion team: $(grep DEVELOPMENT_TEAM Config/Local.xcconfig || true)"
  echo "Delete it to sign with Arterion (NNVBJ33M7Q)."
else
  echo "Signing with the Arterion team from Config/Base.xcconfig"
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
