# Blockpulse — Mac setup & TestFlight checklist

## 1. Clone and bootstrap (~10 min)
1. Clone the repo on the MacBook.
2. Run `./scripts/bootstrap-mac.sh`. It installs XcodeGen if needed, asks for your Team ID once, generates the Xcode project, runs the BitcoinKit tests (unit + live), builds for the Simulator, and opens Xcode.
3. If the Simulator build fails, check `docs/MAC-TODO.md` first. That file lists every item that could not be compiled on Linux.

## 2. Signing (personal account)
1. Xcode → Settings → Accounts: make sure your personal Apple ID / team is signed in.
2. Select the **Blockpulse** target → Signing & Capabilities. Leave "Automatically manage signing" on and pick your team. Xcode registers `com.lazet.blockpulse`.
3. Under **App Groups**, tick or add `group.com.lazet.blockpulse`. Xcode registers it in the portal.
4. Repeat for the **BlockpulseWidgets** target (`com.lazet.blockpulse.widgets`, same App Group).
5. If the bundle ID is taken, change the `com.lazet` prefix in `project.yml` (both targets, plus `AppGroup.identifier` in `Packages/BitcoinKit/Sources/BitcoinKit/Snapshot/SnapshotStore.swift` and the entitlements), then run `xcodegen generate`.

## 3. Run on your iPhone
1. Plug in the iPhone (or use Wi-Fi pairing). Enable Developer Mode on the phone when prompted.
2. Choose the scheme **Blockpulse**, pick your iPhone as the destination, and press ⌘R.
3. In the app, check the overview shows live data, then Settings → Test connection → "OK · NN ms".
4. Add widgets: long-press the Home Screen → Edit → Add Widget → Blockpulse. Do the same on the Lock Screen (long-press → Customize).
5. To debug widgets, use the **BlockpulseWidgets** scheme → run → pick Blockpulse. Edit the scheme's `_XCWidgetKind` / `_XCWidgetFamily` to choose which widget.

## 4. TestFlight (internal, no review)
1. Go to https://appstoreconnect.apple.com → Apps → + New App. Platform iOS, name "Blockpulse" (if taken, try "Blockpulse BTC"; the display name can stay Blockpulse), bundle ID `com.lazet.blockpulse`, SKU `blockpulse`.
2. In Xcode: destination **Any iOS Device (arm64)** → Product → Archive.
3. In the Organizer: Distribute App → **TestFlight Internal Only** → Upload.
4. In App Store Connect → TestFlight: when processing finishes (5–30 min), add yourself to Internal Testing.
5. Install the **TestFlight** app on the iPhone and accept.
6. For each new build, bump `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate` and archive again.

## 5. Verification (from the spec)
- Widgets update about every 15 min over a day.
- Airplane mode: the widget keeps cached data and shows "as of HH:mm" after 30 min.
- Turn airplane mode off: the widget recovers within about 5 min.
- Lock Screen inline/rectangular/circular render in the tinted and clear styles. StandBy: charge the phone in landscape.
