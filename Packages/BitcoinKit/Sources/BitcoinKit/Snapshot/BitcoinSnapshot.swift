import Foundation

public struct PriceInfo: Codable, Sendable, Equatable {
    public var eur: Double
    public var usd: Double
    public var eur24hAgo: Double?
    public var usd24hAgo: Double?
    public var updatedAt: Date

    public init(eur: Double, usd: Double, eur24hAgo: Double?, usd24hAgo: Double?, updatedAt: Date) {
        self.eur = eur; self.usd = usd; self.eur24hAgo = eur24hAgo; self.usd24hAgo = usd24hAgo; self.updatedAt = updatedAt
    }

    public func price(in currency: Currency) -> Double { currency == .eur ? eur : usd }

    /// 24h change in percent units (e.g. -0.89 means -0.89%), nil when no usable baseline.
    public func change24hPercent(in currency: Currency) -> Double? {
        guard let ago = currency == .eur ? eur24hAgo : usd24hAgo, ago > 0 else { return nil }
        return (price(in: currency) - ago) / ago * 100
    }

    /// Satoshis per one unit of fiat ("moscow time"), nil when price is not positive.
    public func satsPerUnit(in currency: Currency) -> Int? {
        let p = price(in: currency)
        guard p > 0 else { return nil }
        return Int((100_000_000 / p).rounded())
    }
}

public struct BlockSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var height: Int
    public var timestamp: Date
    public var txCount: Int
    public var size: Int
    public var medianFee: Double?
    public var poolName: String?
    public var totalFees: Int?

    public init(id: String, height: Int, timestamp: Date, txCount: Int, size: Int, medianFee: Double?, poolName: String?, totalFees: Int?) {
        self.id = id; self.height = height; self.timestamp = timestamp; self.txCount = txCount
        self.size = size; self.medianFee = medianFee; self.poolName = poolName; self.totalFees = totalFees
    }

    public init(block: Block) {
        self.init(
            id: block.id,
            height: block.height,
            timestamp: Date(timeIntervalSince1970: TimeInterval(block.timestamp)),
            txCount: block.txCount,
            size: block.size,
            medianFee: block.extras?.medianFee,
            poolName: block.extras?.pool?.name,
            totalFees: block.extras?.totalFees
        )
    }
}

/// Everything a widget renders, fetched in one refresh.
public struct BitcoinSnapshot: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var price: PriceInfo?
    /// Newest first.
    public var blocks: [BlockSummary]
    public var fees: RecommendedFees?
    public var mempool: MempoolStats?
    public var difficulty: DifficultyAdjustment?

    public init(fetchedAt: Date, price: PriceInfo?, blocks: [BlockSummary], fees: RecommendedFees?, mempool: MempoolStats?, difficulty: DifficultyAdjustment?) {
        self.fetchedAt = fetchedAt; self.price = price; self.blocks = blocks
        self.fees = fees; self.mempool = mempool; self.difficulty = difficulty
    }

    public var tipHeight: Int? { blocks.first?.height }
    public var lastBlockDate: Date? { blocks.first?.timestamp }
    public var isEmpty: Bool { price == nil && blocks.isEmpty && fees == nil && mempool == nil && difficulty == nil }

    public func isStale(now: Date, threshold: TimeInterval = RefreshPolicy.staleThreshold) -> Bool {
        now.timeIntervalSince(fetchedAt) > threshold
    }
}

extension BitcoinSnapshot {
    /// Realistic data (2026-10-13) for previews, widget gallery and placeholders.
    public static func sample(fetchedAt: Date = Date()) -> BitcoinSnapshot {
        let pools = ["Foundry USA", "AntPool", "ViaBTC", "Luxor", "F2Pool"]
        let blocks = (0..<5).map { i in
            BlockSummary(
                id: String(repeating: "0", count: 20) + String(971_150 - i),
                height: 971_150 - i,
                timestamp: fetchedAt.addingTimeInterval(TimeInterval(-240 - i * 600)),
                txCount: [5_689, 3_341, 4_102, 2_877, 3_960][i],
                size: 1_585_913,
                medianFee: [0.35, 2.2, 1.1, 0.8, 1.6][i],
                poolName: pools[i],
                totalFees: 967_148
            )
        }
        return BitcoinSnapshot(
            fetchedAt: fetchedAt,
            price: PriceInfo(eur: 73_984, usd: 82_565, eur24hAgo: 74_651, usd24hAgo: 83_580, updatedAt: fetchedAt),
            blocks: blocks,
            fees: RecommendedFees(fastestFee: 2, halfHourFee: 1, hourFee: 1, economyFee: 1, minimumFee: 1),
            mempool: MempoolStats(count: 77_148, vsize: 38_536_434, totalFee: 5_509_019),
            difficulty: DifficultyAdjustment(
                progressPercent: 72.17,
                difficultyChange: 4.72,
                estimatedRetargetDate: (fetchedAt.timeIntervalSince1970 + 321_635) * 1000,
                remainingBlocks: 561,
                nextRetargetHeight: 971_712
            )
        )
    }
}
