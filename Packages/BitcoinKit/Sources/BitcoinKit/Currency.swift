public enum Currency: String, Codable, CaseIterable, Sendable {
    case eur = "EUR"
    case usd = "USD"

    public var code: String { rawValue }
    public var symbol: String { self == .eur ? "€" : "$" }
    public var other: Currency { self == .eur ? .usd : .eur }
}
