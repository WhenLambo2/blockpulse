import SwiftUI
import Observation
import BitcoinKit

/// State shared by the tabs, so a change in Settings shows up in Charts and on the home screen at once.
@MainActor
@Observable
final class AppState {
    var favourites: [ChartID] {
        didSet { AppPreferences().favourites = favourites }
    }

    var cardOrder: [HomeCard] {
        didSet { AppPreferences().homeCardOrder = cardOrder }
    }

    /// Bumps to play the block-found animation without a new block (the 7-tap easter egg).
    private(set) var celebration = 0

    /// Bumps when the data source changes, so screens reload from the new instance.
    private(set) var dataSourceVersion = 0

    /// The Explore tab's navigation stack, so other tabs and links can open a block or transaction there.
    var explorePath: [ExploreRoute] = []

    /// Set to switch tabs from code (a tapped block on another tab, a deep link); the app clears it.
    var requestedTab: String?

    private var tabTaps: [Date] = []

    init(preferences: AppPreferences = AppPreferences()) {
        favourites = preferences.favourites
        cardOrder = preferences.homeCardOrder
    }

    func toggleFavourite(_ id: ChartID) {
        if let i = favourites.firstIndex(of: id) { favourites.remove(at: i) } else { favourites.append(id) }
    }

    func dataSourceChanged() { dataSourceVersion += 1 }

    /// Counts taps on the Blockpulse tab; seven within three seconds plays the block-found animation.
    func registerHomeTabTap(now: Date = Date()) {
        tabTaps = tabTaps.filter { now.timeIntervalSince($0) < 3 } + [now]
        if tabTaps.count >= 7 {
            tabTaps = []
            celebrate()
        }
    }

    func celebrate() { celebration += 1 }

    /// Shows `route` on the Explore tab, on top of the tab's root.
    func open(_ route: ExploreRoute) {
        explorePath = [route]
        requestedTab = "explore"
    }
}
