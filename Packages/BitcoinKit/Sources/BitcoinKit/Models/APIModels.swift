import Foundation

/// GET /api/v1/prices
public struct Prices: Codable, Sendable, Equatable {
    public let time: Int
    public let usd: Double
    public let eur: Double

    public init(time: Int, usd: Double, eur: Double) {
        self.time = time; self.usd = usd; self.eur = eur
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }

    enum CodingKeys: String, CodingKey { case time, usd = "USD", eur = "EUR" }
}

/// GET /api/v1/historical-price?currency=EUR&timestamp=…
public struct HistoricalPriceResponse: Codable, Sendable, Equatable {
    public let prices: [HistoricalPricePoint]
    public init(prices: [HistoricalPricePoint]) { self.prices = prices }
}

public struct HistoricalPricePoint: Codable, Sendable, Equatable {
    public let time: Int
    public let eur: Double?
    public let usd: Double?

    public init(time: Int, eur: Double?, usd: Double?) {
        self.time = time; self.eur = eur; self.usd = usd
    }

    enum CodingKeys: String, CodingKey { case time, eur = "EUR", usd = "USD" }
}

/// Element of GET /api/v1/blocks (newest first)
public struct Block: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let height: Int
    public let timestamp: Int
    public let txCount: Int
    public let size: Int
    public let weight: Int
    public let extras: Extras?

    public init(id: String, height: Int, timestamp: Int, txCount: Int, size: Int, weight: Int, extras: Extras?) {
        self.id = id; self.height = height; self.timestamp = timestamp
        self.txCount = txCount; self.size = size; self.weight = weight; self.extras = extras
    }

    public struct Extras: Codable, Sendable, Equatable {
        public let medianFee: Double?
        /// Lowest to highest fee rate paid in the block, sat/vB (seven percentiles).
        public let feeRange: [Double]?
        public let totalFees: Int?
        public let reward: Int?
        public let pool: Pool?

        public init(medianFee: Double?, feeRange: [Double]? = nil, totalFees: Int?, reward: Int?, pool: Pool?) {
            self.medianFee = medianFee; self.feeRange = feeRange; self.totalFees = totalFees; self.reward = reward; self.pool = pool
        }
    }

    public struct Pool: Codable, Sendable, Equatable {
        public let id: Int
        public let name: String
        public let slug: String

        public init(id: Int, name: String, slug: String) {
            self.id = id; self.name = name; self.slug = slug
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, height, timestamp, size, weight, extras
        case txCount = "tx_count"
    }
}

/// GET /api/v1/fees/precise (sat/vB, fractional; /recommended floors at 1)
public struct RecommendedFees: Codable, Sendable, Equatable {
    public let fastestFee: Double
    public let halfHourFee: Double
    public let hourFee: Double
    public let economyFee: Double
    public let minimumFee: Double

    public init(fastestFee: Double, halfHourFee: Double, hourFee: Double, economyFee: Double, minimumFee: Double) {
        self.fastestFee = fastestFee; self.halfHourFee = halfHourFee; self.hourFee = hourFee
        self.economyFee = economyFee; self.minimumFee = minimumFee
    }
}

/// GET /api/mempool (fee_histogram ignored)
public struct MempoolStats: Codable, Sendable, Equatable {
    public let count: Int
    public let vsize: Int
    public let totalFee: Int

    public init(count: Int, vsize: Int, totalFee: Int) {
        self.count = count; self.vsize = vsize; self.totalFee = totalFee
    }

    /// Approximate number of 1 MvB blocks needed to clear the mempool.
    public var blocksToClear: Int { Int((Double(vsize) / 1_000_000).rounded(.up)) }

    enum CodingKeys: String, CodingKey { case count, vsize, totalFee = "total_fee" }
}

/// GET /api/v1/difficulty-adjustment
public struct DifficultyAdjustment: Codable, Sendable, Equatable {
    public let progressPercent: Double
    public let difficultyChange: Double
    /// Milliseconds since 1970.
    public let estimatedRetargetDate: Double
    public let remainingBlocks: Int
    public let nextRetargetHeight: Int

    public init(progressPercent: Double, difficultyChange: Double, estimatedRetargetDate: Double, remainingBlocks: Int, nextRetargetHeight: Int) {
        self.progressPercent = progressPercent; self.difficultyChange = difficultyChange
        self.estimatedRetargetDate = estimatedRetargetDate; self.remainingBlocks = remainingBlocks
        self.nextRetargetHeight = nextRetargetHeight
    }

    public var retargetDate: Date { Date(timeIntervalSince1970: estimatedRetargetDate / 1000) }
}
