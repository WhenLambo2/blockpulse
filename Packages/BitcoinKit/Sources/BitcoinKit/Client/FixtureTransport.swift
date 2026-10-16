import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Demo data for screen captures: replays saved responses so every take shows the same numbers.
/// A request with nothing saved yet is fetched once from `upstream` and saved for the next take.
///
/// Block times are shifted so the newest block is always `tipAge` seconds old. With `newBlockAt`,
/// the newest block is held back until that moment and is timestamped at it, so the first
/// refresh after it plays the app's real block-found flow, block number included.
public actor FixtureTransport: HTTPTransport {
    public static let blocksPath = "/api/v1/blocks"

    private let directory: URL
    private let upstream: any HTTPTransport
    private let tipAge: TimeInterval
    private let newBlockAt: Date?
    private let now: @Sendable () -> Date

    public init(
        directory: URL,
        upstream: any HTTPTransport = URLSessionTransport(),
        tipAge: TimeInterval = 150,
        newBlockAt: Date? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.upstream = upstream
        self.tipAge = tipAge
        self.newBlockAt = newBlockAt
        self.now = now
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw MempoolError.network("Request without URL") }
        let file = directory.appendingPathComponent(Self.fileName(for: url))
        var data: Data
        if let saved = try? Data(contentsOf: file) {
            data = saved
        } else {
            let (fresh, response) = try await upstream.send(request)
            guard (200..<300).contains(response.statusCode) else { return (fresh, response) }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fresh.write(to: file, options: .atomic)
            data = fresh
        }
        if url.path == Self.blocksPath { data = adjustBlocks(data) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }

    /// `/api/v1/mining/hashrate/1y` → `api_v1_mining_hashrate_1y.json` (query included).
    static func fileName(for url: URL) -> String {
        var key = url.path
        if let query = url.query, !query.isEmpty { key += "?" + query }
        let safe = String(key.map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return safe.trimmingCharacters(in: CharacterSet(charactersIn: "_")) + ".json"
    }

    func adjustBlocks(_ data: Data) -> Data {
        guard var blocks = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let newest = blocks.first?["timestamp"] as? Int else { return data }
        let current = now()
        let tipDate = newBlockAt ?? current.addingTimeInterval(-tipAge)
        let shift = Int(tipDate.timeIntervalSince1970) - newest
        blocks = blocks.map { block in
            var block = block
            if let timestamp = block["timestamp"] as? Int { block["timestamp"] = timestamp + shift }
            return block
        }
        if let newBlockAt, current < newBlockAt, blocks.count > 1 { blocks.removeFirst() }
        return (try? JSONSerialization.data(withJSONObject: blocks)) ?? data
    }
}
