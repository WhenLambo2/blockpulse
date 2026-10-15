import Foundation

/// Loads charts with a per-chart cache lifetime. The full price history (about 1.1 MB) is fetched
/// at most once a day and shared by the price and sats charts across every period.
public actor ChartLoader {
    public static let priceHistoryLifetime: TimeInterval = 24 * 60 * 60

    private let client: MempoolClient
    private let now: @Sendable () -> Date
    private let priceHistoryFile: URL?
    private var results: [String: (loadedAt: Date, result: ChartResult)] = [:]
    private var priceHistory: (loadedAt: Date, response: HistoricalPriceResponse)?

    /// `priceHistoryFile`: where to keep the price history between launches (nil keeps it in memory only).
    public init(client: MempoolClient, priceHistoryFile: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.priceHistoryFile = priceHistoryFile; self.now = now
    }

    /// Cached result when still fresh, else a network load. `force` skips the cache (pull to refresh).
    public func load(_ id: ChartID, period: ChartPeriod?, currency: Currency, force: Bool = false) async throws -> ChartResult {
        let period = period ?? id.defaultPeriod
        let key = "\(id.rawValue)|\(period?.rawValue ?? "-")|\(currency.code)"
        if !force, let cached = results[key], now().timeIntervalSince(cached.loadedAt) < id.cacheLifetime {
            return cached.result
        }
        let result = try await fetch(id, period: period ?? .day, currency: currency, force: force)
        results[key] = (now(), result)
        return result
    }

    /// Last loaded result regardless of age, for showing something while a refresh runs.
    public func cached(_ id: ChartID, period: ChartPeriod?, currency: Currency) -> ChartResult? {
        let period = period ?? id.defaultPeriod
        return results["\(id.rawValue)|\(period?.rawValue ?? "-")|\(currency.code)"]?.result
    }

    private func fetch(_ id: ChartID, period: ChartPeriod, currency: Currency, force: Bool) async throws -> ChartResult {
        switch id {
        case .price:
            return ChartBuilder.price(try await history(force: force), period: period, currency: currency, now: now())
        case .priceOther:
            return ChartBuilder.price(try await history(force: force), period: period, currency: currency.other, now: now(), id: .priceOther)
        case .satsPerFiat:
            return ChartBuilder.satsPerFiat(try await history(force: force), period: period, currency: currency, now: now())
        case .feeRates: return ChartBuilder.feeRates(try await client.blockFeeRates(period), period: period)
        case .blockFees: return ChartBuilder.blockFees(try await client.blockFees(period), period: period)
        case .mempoolSize: return ChartBuilder.mempoolSize(try await client.mempoolStatistics(period), period: period)
        case .mempoolCount: return ChartBuilder.mempoolCount(try await client.mempoolStatistics(period), period: period)
        case .mempoolInflow: return ChartBuilder.mempoolInflow(try await client.mempoolStatistics(period), period: period)
        case .projectedBlocks: return ChartBuilder.projectedBlocks(try await client.projectedBlocks())
        case .hashrate: return ChartBuilder.hashrate(try await client.hashrate(period), period: period)
        case .difficultyHistory: return ChartBuilder.difficultyHistory(try await client.difficultyAdjustments(period), period: period)
        case .pools: return ChartBuilder.pools(try await client.pools(period), period: period)
        case .blockSize: return ChartBuilder.blockSize(try await client.blockSizes(period), period: period)
        case .recentBlocks: return ChartBuilder.recentBlocks(try await client.recentBlocks())
        }
    }

    private func history(force: Bool) async throws -> HistoricalPriceResponse {
        let current = now()
        if priceHistory == nil, let file = priceHistoryFile, let stored = Self.readHistory(file) {
            priceHistory = stored
        }
        if let cached = priceHistory, current.timeIntervalSince(cached.loadedAt) < Self.priceHistoryLifetime {
            return cached.response
        }
        do {
            let response = try await client.priceHistory()
            priceHistory = (current, response)
            if let file = priceHistoryFile { Self.writeHistory(response, loadedAt: current, to: file) }
            return response
        } catch {
            // An old history beats no chart.
            if let cached = priceHistory { return cached.response }
            throw error
        }
    }

    private struct StoredHistory: Codable {
        let loadedAt: Date
        let response: HistoricalPriceResponse
    }

    private static func readHistory(_ file: URL) -> (loadedAt: Date, response: HistoricalPriceResponse)? {
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(StoredHistory.self, from: data) else { return nil }
        return (stored.loadedAt, stored.response)
    }

    private static func writeHistory(_ response: HistoricalPriceResponse, loadedAt: Date, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(StoredHistory(loadedAt: loadedAt, response: response)).write(to: file, options: .atomic)
    }
}
