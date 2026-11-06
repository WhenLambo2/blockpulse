#!/bin/sh
# Xcode Cloud: the Xcode project, Info.plists and entitlements are generated from project.yml and not committed.
set -eu
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
