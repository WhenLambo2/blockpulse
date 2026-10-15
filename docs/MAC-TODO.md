# Items to verify in Xcode (not compilable on Linux)

BitcoinKit is fully tested on Linux (Swift 6.4). `App/` and `Widgets/` were only syntax-checked (`swiftc -parse`).
Check these on the first Xcode build:

- [ ] `xcodegen generate` succeeds and both targets build for the Simulator.
- [ ] `PrivacyInfo.xcprivacy` lands in Copy Bundle Resources for both targets (XcodeGen resource detection).

## Widgets (Task 6)

- [ ] Widget previews render for every family (Price S/M, Blocks S/M, Fees S/M, Dashboard L, Lock circular/rectangular/inline) in fresh, stale and empty states.
- [ ] Tinted / clear Home Screen modes: accent text uses `.widgetAccentable()`; check contrast.
- [ ] Widget gallery shows the configuration (Currency / Metric) options.
- [ ] `Intents.swift`: `static let description = IntentDescription(...)` is non-optional while `AppIntent.description` is declared `IntentDescription?`. If the gallery/edit sheet shows no description (silent fallback to the default `nil`), change both intents to `static let description: IntentDescription? = IntentDescription("…")`.
- [ ] `Intents.swift`: under Xcode 16+ the AppIntents metadata extractor must accept the generic `SnapshotProvider<Intent>` + custom `SnapshotWidgetIntent` protocol; confirm the build log shows no "appintentsmetadataprocessor" warnings and both intents appear in the edit sheet.
- [ ] `Components.swift` `FeeGrid.row(_:_:)` returns `some View` wrapping a `GridRow`; confirm the four rows align as two columns (if not, change the return type to `GridRow<some View>` or inline the rows).
- [ ] systemSmall Fees widget: header + 4 fee rows + "sat/vB" + stale footer may clip; if so, drop the "sat/vB" line on small (fold into header "Fees (sat/vB)").
- [ ] SF Symbols exist on iOS 18: `gauge.with.dots.needle.33percent`, `clock.badge.exclamationmark`, `tray.full.fill`, `bitcoinsign`, `bitcoinsign.circle(.fill)`, `cube(.fill)`.
- [ ] Swift 6 strict-concurrency warnings in Widgets (target is Swift 5 mode): AppEnum static `let` dictionaries and `SnapshotEntry` Sendability — warnings acceptable, errors not.

## App (Task 7)

- [ ] App: overview loads live data on launch; pull to refresh works; Settings → Test connection shows "OK · NN ms".
- [ ] Changing currency in Settings updates widgets set to "App setting" within a reload.
- [ ] Airplane mode: overview shows the error banner + "Showing cached data."
- [ ] `OverviewView`: `Text("\(b.timestamp, style: .relative) ago")` renders e.g. "4 min ago" (not "4 min ago ago" or a doubled unit); if odd, switch to `Text(b.timestamp, format: .relative(presentation: .named))`.
- [ ] Settings: base URL is saved only via **Done**; swipe-to-dismiss discards edits (currency still saves instantly via `@AppStorage`). Confirm that is acceptable, else add `.interactiveDismissDisabled(baseURLText != AppSettings.shared().baseURL.absoluteString)` or save in `onDisappear`.
- [ ] `OverviewModel.refresh()` now drops calls while one is in flight (`guard !isLoading`). Confirm launch fetches once (`.task` + first `.active`), returning from background refreshes the overview, and that a Settings change made while a refresh is in flight is picked up (onDismiss refresh is dropped if one is running; pull to refresh to recover).
- [ ] Swift 6 strict-concurrency warnings in App (Swift 5 mode): `@State private var model = OverviewModel()` (MainActor init in a View property initializer) — warnings acceptable, errors not.

## Final-review fixes (2026-10-13)

- [ ] Widget gallery (`context.isPreview`) shows sample data; a freshly added widget with no cache shows real data after its first fetch, or "No data yet" offline — never the sample prices.
- [ ] `snapshot(for:in:)` without cache awaits a network load; confirm WidgetKit does not time out the snapshot on a slow network (10 s request timeout x 6 concurrent requests).
- [ ] Lock Screen circular `.height` shows the full number (e.g. "971150"); check it scales legibly with `minimumScaleFactor(0.5)` and is not truncated.
- [ ] Partial refresh (one endpoint failing) shows the error banner in the app with live data; widgets keep the previous section and retry after 5 min.

## v2 redesign (2026-10-15)

CI builds the app for the Simulator and screenshots both tabs; these still need a hands-on check:
- [ ] Charts tab: swipe up/down pages one chart at a time; swipe sideways changes category without fighting the vertical pager.
- [ ] Press and drag on line, band and bar charts shows the readout; it stays inside the card at both edges.
- [ ] Favourites: star toggles, Edit sheet reorders/removes/adds, order survives a relaunch.
- [ ] Pulse cards fold/unfold with animation and remember their state after relaunch.
- [ ] Appearance: Dark (default), Light and System switch live from Settings; System follows Control Centre.
- [ ] Changing the base URL in Settings: Pulse picks it up at once, Charts after a relaunch (shared loader is created once).

## v2.1 fine-tuning (2026-10-15)

CI screenshots cover the three tabs; check these by hand on a device:
- [ ] Heartbeat: a glow sweeps along the line while waiting; it stops in the background and with Reduce Motion on.
- [ ] New block: the line spikes, a ring ripples from the peak, "Block found" shows, the block number rolls and a success haptic plays.
- [ ] Easter egg: tapping the Blockpulse tab 7 times within 3 seconds plays the same animation (from another tab, the first tap counts too).
- [ ] Home: hold and drag a card onto another to reorder; the block header can't move; order survives a relaunch and matches Settings → Card order.
- [ ] Fee tiles: tapping any tile swaps all four between sat/vB and the cost in €/$; Settings → Fee tiles show stays in sync.
- [ ] Charts: hashrate legend chips hide/show Hashrate, Average and Difficulty; with only Difficulty shown, the axis labels hide.
- [ ] Recent blocks chart: block cards scroll sideways inside the vertical pager without fighting it.
- [ ] Settings tab: Appearance changes apply live everywhere, including System after Dark (window style override).
- [ ] Data source: switching mempool.space / Blockrise / Custom reloads home and charts without a relaunch; Test connection uses the chosen URL; widgets follow.
- [ ] Existing v2 install with Blockrise saved moves to mempool.space once after updating (migration), and can pick Blockrise again.

## v2.2 feedback (2026-10-15)

- [ ] Switching chart periods (Market especially) swaps cleanly: no filled area under the line, no lines morphing; the old period dims while the new one loads.
- [ ] Charts: the next chart's top shows behind the tab bar; swiping up snaps card by card; the last card can still be fully shown.
- [ ] Block found: glow races and shakes along the line, then lights up the whole card (wave, border, shake), number rolls, heavy tap plus success haptic.
- [ ] Brand (D9 board): header shows the symbol without tile, white pulse in dark and ink pulse in light; Settings → About shows the app icon; Home Screen Dark and Tinted icon styles use the supplied variants (long-press Home Screen → Edit → Customize).
