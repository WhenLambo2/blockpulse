# Blockpulse

Free and open source iOS app with Bitcoin widgets: price (EUR/USD), blocks, fees and mempool. Site: https://blockpul.se
Data: public `https://mempool.space` by default (no API key). Settings can switch to the Blockrise instance `https://blockrise.mempool.space` or any mempool.space-compatible URL; widgets follow.

## Layout
- `Packages/BitcoinKit`: API client, models, snapshot cache, formatting, settings. Pure Foundation, tested on Linux and macOS.
- `App/`: SwiftUI app. Three tabs: **Blockpulse** (block header with heartbeat, then foldable cards you can reorder: fees, mempool, difficulty, halving, recent blocks), **Charts** (categories, favourites, vertical paging, Swift Charts; tables only where they help) and **Settings** (appearance, currency, fee tiles, card order, favourites, data source). Logo palette in `App/Theme.swift`; dark by default, light/system in Settings.
- `Widgets/`: WidgetKit extension (Home Screen S/M/L, Lock Screen, StandBy).
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated and never committed.

## Commands
- Mac first run: `./scripts/bootstrap-mac.sh`, then follow `docs/MAC-SETUP.md`
- Tests: `swift test --package-path Packages/BitcoinKit`
- Live API check: `BLOCKPULSE_LIVE=1 swift test --package-path Packages/BitcoinKit --filter LiveSmokeTests`
- Simulator build + screenshots: CI workflow `iOS app` (`.github/workflows/ios.yml`, `scripts/ci-screenshots.sh`); screenshots are a run artifact
- Regenerate project after editing `project.yml`: `xcodegen generate`

## License and trademarks
The code is MIT licensed (see `LICENSE`).
The license covers the code only. The Blockpulse and Blockrise names, the Blockpulse logo and app icon are not licensed for reuse: a fork published to the App Store or elsewhere needs its own name and icon.
