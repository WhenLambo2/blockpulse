import Foundation

/// How a block page is asked for; heights and times are resolved to a hash when the page loads.
public enum BlockRef: Hashable, Sendable {
    case hash(String)
    case height(Int)
    /// Unix seconds: the block mined at or just before that moment.
    case timestamp(Int)
}

/// A page in the Explore tab. Also the shape of deep links (`blockpulse://tx/…`) and the
/// mempool.space links that can be pasted or scanned.
public enum ExploreRoute: Hashable, Sendable {
    case transaction(String, output: Int?)
    case block(BlockRef)
    case address(String)
    /// 0 is the next block.
    case pendingBlock(Int)

    public static let scheme = "blockpulse"

    /// What a search for this page looks like (used for recent searches and cleaned-up links).
    public var searchText: String {
        switch self {
        case .transaction(let txid, let output): output.map { "\(txid):\($0)" } ?? txid
        case .block(.hash(let hash)): hash
        case .block(.height(let height)): String(height)
        case .block(.timestamp(let seconds)): String(seconds)
        case .address(let address): address
        case .pendingBlock(let index): "pending:\(index)"
        }
    }

    /// `blockpulse://tx/<txid>`, `blockpulse://block/<hash or height>`, `blockpulse://address/<address>`.
    public var deepLink: URL? {
        switch self {
        case .transaction(let txid, _): URL(string: "\(Self.scheme)://tx/\(txid)")
        case .block(.hash(let h)): URL(string: "\(Self.scheme)://block/\(h)")
        case .block(.height(let h)): URL(string: "\(Self.scheme)://block/\(h)")
        case .block(.timestamp(let t)): URL(string: "\(Self.scheme)://block-at/\(t)")
        case .address(let a): URL(string: "\(Self.scheme)://address/\(a)")
        case .pendingBlock(let i): URL(string: "\(Self.scheme)://mempool-block/\(i)")
        }
    }

    /// The same page on the web explorer at `base` (mempool.space or the chosen instance).
    public func webURL(base: URL) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        switch self {
        case .transaction(let txid, let output):
            return URL(string: "\(root)/tx/\(txid)" + (output.map { "#vout=\($0)" } ?? ""))
        case .block(.hash(let h)): return URL(string: "\(root)/block/\(h)")
        case .block(.height(let h)): return URL(string: "\(root)/block/\(h)")
        case .block(.timestamp): return nil
        case .address(let a): return URL(string: "\(root)/address/\(a)")
        case .pendingBlock(let i): return URL(string: "\(root)/mempool-block/\(i)")
        }
    }

    /// Parses a deep link.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kind = components.host?.lowercased() else { return nil }
        let value = components.path.split(separator: "/").first.map(String.init)
        guard let route = Self.route(kind: kind, value: value) else { return nil }
        self = route
    }

    /// Parses an explorer link such as `https://mempool.space/tx/<txid>` or
    /// `https://mempool.space/block/<hash>`. Test networks (`/testnet/tx/…`) are not opened.
    public init?(webURL string: String) {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host != nil else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        let networks: Set<String> = ["testnet", "testnet4", "signet", "regtest", "liquid", "liquidtestnet"]
        guard !parts.contains(where: { networks.contains($0.lowercased()) }) else { return nil }
        for (i, part) in parts.enumerated() where i + 1 < parts.count {
            if let route = Self.route(kind: part.lowercased(), value: parts[i + 1]) {
                if case .transaction(let txid, nil) = route,
                   let fragment = components.fragment, fragment.hasPrefix("vout="), let n = Int(fragment.dropFirst(5)) {
                    self = .transaction(txid, output: n)
                } else {
                    self = route
                }
                return
            }
        }
        return nil
    }

    private static func route(kind: String, value: String?) -> ExploreRoute? {
        guard let value, !value.isEmpty else { return nil }
        let hex = value.count == 64 && value.allSatisfy(\.isHexDigit)
        switch kind {
        case "tx":
            return hex ? .transaction(value.lowercased(), output: nil) : nil
        case "block":
            if hex { return .block(.hash(value.lowercased())) }
            if let height = Int(value), height >= 0 { return .block(.height(height)) }
            return nil
        case "address":
            return value.count >= 14 && value.count <= 100 && value.allSatisfy({ $0.isLetter || $0.isNumber })
                ? .address(value) : nil
        case "block-at":
            return Int(value).map { .block(.timestamp($0)) }
        case "mempool-block":
            return Int(value).map { .pendingBlock(max(0, $0)) }
        default:
            return nil
        }
    }
}
