import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ConnectionCheck: Sendable, Equatable {
    public let latencyMilliseconds: Int
    public let error: MempoolError?

    public init(latencyMilliseconds: Int, error: MempoolError?) {
        self.latencyMilliseconds = latencyMilliseconds; self.error = error
    }

    public var succeeded: Bool { error == nil }
    public var summary: String {
        if let error { return "Failed: \(error.userMessage)" }
        return "OK · \(latencyMilliseconds) ms"
    }
}

/// Client for the mempool.space-compatible REST API (public mempool.space by default).
public struct MempoolClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://mempool.space")!
    /// Chart endpoints over long periods return up to about 1 MB and can take seconds server-side.
    public static let chartTimeout: TimeInterval = 30
    static let userAgent = "Blockpulse/1.0"

    public let baseURL: URL
    private let authorization: String?
    private let transport: any HTTPTransport
    private let timeout: TimeInterval

    public init(
        baseURL: URL = MempoolClient.defaultBaseURL,
        authorization: String? = nil,
        transport: any HTTPTransport = URLSessionTransport(),
        timeout: TimeInterval = 10
    ) {
        self.baseURL = baseURL
        let trimmed = authorization?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authorization = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.transport = transport
        self.timeout = timeout
    }

    public func prices() async throws -> Prices { try await get("/api/v1/prices") }

    public func historicalPrice(at date: Date, currency: Currency = .eur) async throws -> HistoricalPriceResponse {
        try await get("/api/v1/historical-price", query: [
            URLQueryItem(name: "currency", value: currency.code),
            URLQueryItem(name: "timestamp", value: String(Int(date.timeIntervalSince1970))),
        ])
    }

    public func recentBlocks() async throws -> [Block] { try await get("/api/v1/blocks") }
    public func recommendedFees() async throws -> RecommendedFees { try await get("/api/v1/fees/precise") }
    public func mempool() async throws -> MempoolStats { try await get("/api/mempool") }
    public func difficultyAdjustment() async throws -> DifficultyAdjustment { try await get("/api/v1/difficulty-adjustment") }

    // MARK: - Charts

    /// Full hourly-to-daily price history (about 1.5 MB); the response carries EUR and USD.
    public func priceHistory() async throws -> HistoricalPriceResponse {
        try await get("/api/v1/historical-price", query: [URLQueryItem(name: "currency", value: Currency.eur.code)],
                      timeout: Self.chartTimeout)
    }

    public func projectedBlocks() async throws -> [ProjectedBlock] { try await get("/api/v1/fees/mempool-blocks") }
    public func mempoolStatistics(_ period: ChartPeriod) async throws -> [MempoolStatistic] {
        try await get("/api/v1/statistics/\(period.apiValue)", timeout: Self.chartTimeout)
    }
    public func hashrate(_ period: ChartPeriod) async throws -> HashrateResponse {
        try await get("/api/v1/mining/hashrate/\(period.apiValue)", timeout: Self.chartTimeout)
    }
    public func difficultyAdjustments(_ period: ChartPeriod) async throws -> [DifficultyAdjustmentEntry] {
        try await get("/api/v1/mining/difficulty-adjustments/\(period.apiValue)", timeout: Self.chartTimeout)
    }
    public func blockFeeRates(_ period: ChartPeriod) async throws -> [BlockFeeRates] {
        try await get("/api/v1/mining/blocks/fee-rates/\(period.apiValue)", timeout: Self.chartTimeout)
    }
    public func blockFees(_ period: ChartPeriod) async throws -> [BlockFees] {
        try await get("/api/v1/mining/blocks/fees/\(period.apiValue)", timeout: Self.chartTimeout)
    }
    public func blockSizes(_ period: ChartPeriod) async throws -> BlockSizes {
        try await get("/api/v1/mining/blocks/sizes-weights/\(period.apiValue)", timeout: Self.chartTimeout)
    }
    public func pools(_ period: ChartPeriod) async throws -> PoolsResponse {
        try await get("/api/v1/mining/pools/\(period.apiValue)", timeout: Self.chartTimeout)
    }

    // MARK: - Explore

    public func tipHeight() async throws -> Int {
        let text = try await getText("/api/blocks/tip/height")
        guard let height = Int(text) else { throw MempoolError.decoding("tip height: \(text.prefix(40))") }
        return height
    }
    public func transaction(_ txid: String) async throws -> BitcoinTx { try await get("/api/tx/\(txid)") }
    public func outspends(_ txid: String) async throws -> [Outspend] { try await get("/api/tx/\(txid)/outspends") }
    public func cpfp(_ txid: String) async throws -> CPFPInfo { try await get("/api/v1/cpfp/\(txid)") }
    public func rbf(_ txid: String) async throws -> RBFInfo { try await get("/api/v1/tx/\(txid)/rbf") }

    /// Block with pool and fee details (same shape as an element of /api/v1/blocks).
    public func block(_ hash: String) async throws -> Block { try await get("/api/v1/block/\(hash)") }
    public func blockHash(height: Int) async throws -> String {
        let hash = try await getText("/api/block-height/\(height)")
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { throw MempoolError.decoding("block hash: \(hash.prefix(40))") }
        return hash
    }
    public func blockAt(timestamp: Int) async throws -> BlockAtTime {
        try await get("/api/v1/mining/blocks/timestamp/\(timestamp)")
    }
    /// 25 transactions from `start` (a multiple of 25).
    public func blockTransactions(_ hash: String, start: Int = 0) async throws -> [BitcoinTx] {
        try await get("/api/block/\(hash)/txs/\(start)")
    }
    /// 15 blocks ending at `height` (newest first).
    public func blocks(endingAt height: Int) async throws -> [Block] { try await get("/api/v1/blocks/\(height)") }

    public func address(_ address: String) async throws -> AddressInfo { try await get("/api/address/\(address)") }
    /// First page: pending transactions plus the newest 25 confirmed. Next pages: 25 confirmed after `lastSeen`.
    public func addressTransactions(_ address: String, after lastSeen: String? = nil) async throws -> [BitcoinTx] {
        if let lastSeen { return try await get("/api/address/\(address)/txs/chain/\(lastSeen)") }
        return try await get("/api/address/\(address)/txs")
    }
    /// Up to 10 addresses starting with `prefix` (bech32 prefixes are sent in lower case).
    public func addressPrefix(_ prefix: String) async throws -> [String] {
        let p = prefix.lowercased().hasPrefix("bc1") ? prefix.lowercased() : prefix
        return try await get("/api/address-prefix/\(p)")
    }

    /// Times a prices request; used by the app's "Test connection" button.
    public func checkConnection() async -> ConnectionCheck {
        let clock = ContinuousClock()
        let start = clock.now
        var failure: MempoolError?
        do { _ = try await prices() } catch { failure = error as? MempoolError ?? .network(error.localizedDescription) }
        let elapsed = (clock.now - start).components
        let ms = Int(elapsed.seconds) * 1000 + Int(elapsed.attoseconds / 1_000_000_000_000_000)
        return ConnectionCheck(latencyMilliseconds: ms, error: failure)
    }

    func makeRequest(path: String, query: [URLQueryItem] = [], timeout: TimeInterval? = nil) -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var components = URLComponents(string: base + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: max(timeout ?? self.timeout, self.timeout))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], timeout: TimeInterval? = nil) async throws -> T {
        let data = try await send(path, query: query, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MempoolError.decoding(String(describing: error))
        }
    }

    /// Plain-text endpoints (a hash or a number).
    private func getText(_ path: String) async throws -> String {
        let data = try await send(path, query: [], timeout: nil)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(_ path: String, query: [URLQueryItem], timeout: TimeInterval?) async throws -> Data {
        let request = makeRequest(path: path, query: query, timeout: timeout)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as MempoolError {
            throw error
        } catch {
            throw MempoolError.network(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw MempoolError.unauthorized
        case 429: throw MempoolError.rateLimited
        default: throw MempoolError.http(response.statusCode)
        }
        return data
    }
}
