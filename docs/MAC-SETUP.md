# Blockpulse — Mac setup & TestFlight checklist

## 1. Clone and bootstrap (~10 min)
1. Clone the repo on the MacBook.
2. Run `./scripts/bootstrap-mac.sh`. It installs XcodeGen if needed, generates the Xcode project, runs the BitcoinKit tests (unit + live), builds for the Simulator, and opens Xcode.
3. If the Simulator build fails, check `docs/MAC-TODO.md` first. That file lists every item that could not be compiled on Linux.

## 2. Signing (Arterion team)
1. Xcode → Settings → Accounts: sign in and select the **Arterion Consultancy B.V.** team.
2. Delete `Config/Local.xcconfig` if you made one for the personal team; it would override the Arterion Team ID (`NNVBJ33M7Q`) in `Config/Base.xcconfig`.
3. Select the **Blockpulse** target → Signing & Capabilities. Leave "Automatically manage signing" on. Xcode registers `nl.arterion.blockpulse`.
4. Under **App Groups**, tick or add `group.nl.arterion.blockpulse`. Xcode registers it in the portal.
5. Repeat for the **BlockpulseWidgets** target (`nl.arterion.blockpulse.widgets`, same App Group).
6. Forks: change the `nl.arterion` prefix in `project.yml` (all targets and entitlements, plus `AppGroup.identifier` in `Packages/BitcoinKit/Sources/BitcoinKit/Snapshot/SnapshotStore.swift`), set your own team in `Config/Local.xcconfig`, then run `xcodegen generate`.

## 3. Run on your iPhone
1. Plug in the iPhone (or use Wi-Fi pairing). Enable Developer Mode on the phone when prompted.
2. Choose the scheme **Blockpulse**, pick your iPhone as the destination, and press ⌘R.
3. In the app, check the overview shows live data, then Settings → Test connection → "OK · NN ms".
4. Add widgets: long-press the Home Screen → Edit → Add Widget → Blockpulse. Do the same on the Lock Screen (long-press → Customize).
5. To debug widgets, use the **BlockpulseWidgets** scheme → run → pick Blockpulse. Edit the scheme's `_XCWidgetKind` / `_XCWidgetFamily` to choose which widget.

## 4. TestFlight (internal, no review)
1. Go to https://appstoreconnect.apple.com → Apps → + New App. Platform iOS, name "Blockpulse" (if taken, try "Blockpulse BTC"; the display name can stay Blockpulse), bundle ID `nl.arterion.blockpulse`, SKU `blockpulse`.
2. In Xcode: destination **Any iOS Device (arm64)** → Product → Archive.
3. In the Organizer: Distribute App → **TestFlight Internal Only** → Upload.
4. In App Store Connect → TestFlight: when processing finishes (5–30 min), add yourself to Internal Testing.
5. Install the **TestFlight** app on the iPhone and accept.
6. For each new build, bump `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate` and archive again.

## 4b. Xcode Cloud
`ci_scripts/ci_post_clone.sh` installs XcodeGen and generates the project after each clone, so Xcode Cloud can build the repo as is. Xcode Cloud sets the build number itself. Create the workflow in Xcode (Integrate → Create Workflow) with a manual start condition, an Archive action and TestFlight internal testing as post-action.

## 5. Verification (from the spec)
- Widgets update about every 15 min over a day.
- Airplane mode: the widget keeps cached data and shows "as of HH:mm" after 30 min.
- Turn airplane mode off: the widget recovers within about 5 min.
- Lock Screen inline/rectangular/circular render in the tinted and clear styles. StandBy: charge the phone in landscape.
