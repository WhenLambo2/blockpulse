import Foundation

/// User settings shared between app and widgets via App Group UserDefaults.
public struct AppSettings {
    public enum Keys {
        public static let currency = "currency"
        public static let baseURL = "baseURL"
        public static let migratedToPublicDefault = "migratedToPublicDefault"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    public static func shared() -> AppSettings { AppSettings(defaults: sharedDefaults) }

    public var currency: Currency {
        get { defaults.string(forKey: Keys.currency).flatMap(Currency.init(rawValue:)) ?? .eur }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Keys.currency) }
    }

    /// Raw override; setting an invalid value clears it (falls back to mempool.space).
    public var baseURLString: String? {
        get { defaults.string(forKey: Keys.baseURL) }
        nonmutating set {
            if let url = Self.validatedBaseURL(newValue) {
                defaults.set(url.absoluteString, forKey: Keys.baseURL)
            } else {
                defaults.removeObject(forKey: Keys.baseURL)
            }
        }
    }

    public var baseURL: URL { Self.validatedBaseURL(baseURLString) ?? MempoolClient.defaultBaseURL }

    /// Whether a custom instance is set (anything other than public mempool.space).
    public var usesCustomInstance: Bool { baseURL != MempoolClient.defaultBaseURL }

    /// v2.1 made public mempool.space the default. Up to v2 Settings saved the then-default
    /// Blockrise URL explicitly, so a stored Blockrise value is cleared once to move those users over.
    public func migrateToPublicDefault() {
        guard !defaults.bool(forKey: Keys.migratedToPublicDefault) else { return }
        defaults.set(true, forKey: Keys.migratedToPublicDefault)
        if Self.validatedBaseURL(baseURLString) == MempoolClient.blockriseBaseURL {
            defaults.removeObject(forKey: Keys.baseURL)
        }
    }

    /// Trims whitespace and trailing slashes; requires http(s) and a host.
    public static func validatedBaseURL(_ input: String?) -> URL? {
        guard var s = input?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        while s.hasSuffix("/") { s.removeLast() }
        guard let components = URLComponents(string: s),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              components.query == nil, components.fragment == nil,
              !s.contains(" ")
        else { return nil }
        return components.url
    }

    public func makeClient(transport: any HTTPTransport = URLSessionTransport()) -> MempoolClient {
        MempoolClient(baseURL: baseURL, transport: transport)
    }
}
