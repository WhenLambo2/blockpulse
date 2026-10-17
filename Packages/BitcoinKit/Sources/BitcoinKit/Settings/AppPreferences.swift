import Foundation

/// Light/dark choice. Dark is the default look; "system" follows the phone.
public enum Appearance: String, CaseIterable, Sendable {
    case dark, light, system

    public var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }
}

/// Movable cards on the home screen (the block-number header is fixed above them).
public enum HomeCard: String, CaseIterable, Sendable, Identifiable {
    case fees, mempool, difficulty, halving, blocks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fees: "What fee to pay"
        case .mempool: "Mempool traffic"
        case .difficulty: "Next difficulty adjustment"
        case .halving: "Next halving"
        case .blocks: "Recent blocks"
        }
    }

    /// Stored order with unknown ids dropped, duplicates removed and new cards appended.
    public static func ordered(_ raw: [String]) -> [HomeCard] {
        var seen = Set<HomeCard>()
        let stored = raw.compactMap(HomeCard.init(rawValue:)).filter { seen.insert($0).inserted }
        return stored + allCases.filter { !seen.contains($0) }
    }
}

/// App-only preferences (the widgets never read these), kept in the app's own UserDefaults.
public struct AppPreferences {
    public enum Keys {
        public static let appearance = "appearance"
        public static let favourites = "chartFavourites"
        public static let homeCardOrder = "homeCardOrder"
        public static let feeTilesShowFiat = "feeTilesShowFiat"
        public static let recentSearches = "recentSearches"
        public static let remembersSearches = "remembersSearches"
    }

    public static let recentSearchLimit = 10

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var appearance: Appearance {
        get { defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .dark }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Keys.appearance) }
    }

    /// Ordered favourites; unknown stored ids are dropped, duplicates removed.
    /// Never set before: the default trio. Set to empty: stays empty.
    public var favourites: [ChartID] {
        get {
            guard let raw = defaults.array(forKey: Keys.favourites) as? [String] else { return ChartID.defaultFavourites }
            var seen = Set<ChartID>()
            return raw.compactMap(ChartID.init(rawValue:)).filter { seen.insert($0).inserted }
        }
        nonmutating set {
            var seen = Set<ChartID>()
            defaults.set(newValue.filter { seen.insert($0).inserted }.map(\.rawValue), forKey: Keys.favourites)
        }
    }

    public var homeCardOrder: [HomeCard] {
        get { HomeCard.ordered(defaults.stringArray(forKey: Keys.homeCardOrder) ?? []) }
        nonmutating set { defaults.set(HomeCard.ordered(newValue.map(\.rawValue)).map(\.rawValue), forKey: Keys.homeCardOrder) }
    }

    /// On unless switched off in Settings.
    public var remembersSearches: Bool {
        get { defaults.object(forKey: Keys.remembersSearches) as? Bool ?? true }
        nonmutating set {
            defaults.set(newValue, forKey: Keys.remembersSearches)
            if !newValue { recentSearches = [] }
        }
    }

    /// Newest first, at most ten, stored on this device only. Unreadable entries are dropped.
    public var recentSearches: [ExploreRoute] {
        get {
            (defaults.stringArray(forKey: Keys.recentSearches) ?? []).compactMap { URL(string: $0).flatMap(ExploreRoute.init(url:)) }
        }
        nonmutating set {
            var seen = Set<String>()
            let links = newValue.compactMap { $0.deepLink?.absoluteString }.filter { seen.insert($0).inserted }
            defaults.set(Array(links.prefix(Self.recentSearchLimit)), forKey: Keys.recentSearches)
        }
    }

    /// Puts `route` on top; does nothing while remembering is off.
    public func remember(_ route: ExploreRoute) {
        guard remembersSearches, route.deepLink != nil else { return }
        recentSearches = [route] + recentSearches
    }

    public func isFavourite(_ id: ChartID) -> Bool { favourites.contains(id) }

    /// Adds at the end, or removes; returns whether it is now a favourite.
    @discardableResult
    public func toggleFavourite(_ id: ChartID) -> Bool {
        var list = favourites
        if let i = list.firstIndex(of: id) {
            list.remove(at: i)
            favourites = list
            return false
        }
        list.append(id)
        favourites = list
        return true
    }
}
