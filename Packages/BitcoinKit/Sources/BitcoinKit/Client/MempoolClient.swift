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
    /// Blockrise Enterprise instance, offered as a preset in Settings.
    public static let blockriseBaseURL = URL(string: "https://blockrise.mempool.space")!
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
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MempoolError.decoding(String(describing: error))
        }
    }
}
