import Foundation

/// GET /api/v1/mining/hashrate/{period}
public struct HashrateResponse: Codable, Sendable, Equatable {
    public let hashrates: [Hashrate]
    public let difficulty: [Difficulty]
    public let currentHashrate: Double?
    public let currentDifficulty: Double?

    public init(hashrates: [Hashrate], difficulty: [Difficulty], currentHashrate: Double?, currentDifficulty: Double?) {
        self.hashrates = hashrates; self.difficulty = difficulty
        self.currentHashrate = currentHashrate; self.currentDifficulty = currentDifficulty
    }

    public struct Hashrate: Codable, Sendable, Equatable {
        public let timestamp: Int
        /// Hashes per second.
        public let avgHashrate: Double
        public init(timestamp: Int, avgHashrate: Double) { self.timestamp = timestamp; self.avgHashrate = avgHashrate }
    }

    public struct Difficulty: Codable, Sendable, Equatable {
        public let time: Int
        public let height: Int
        public let difficulty: Double
        /// Ratio to the previous difficulty (1.04 means +4%).
        public let adjustment: Double
        public init(time: Int, height: Int, difficulty: Double, adjustment: Double) {
            self.time = time; self.height = height; self.difficulty = difficulty; self.adjustment = adjustment
        }
    }
}

/// Element of GET /api/v1/mining/difficulty-adjustments/{period}, sent as `[time, height, difficulty, ratio]`.
public struct DifficultyAdjustmentEntry: Codable, Sendable, Equatable {
    public let time: Int
    public let height: Int
    public let difficulty: Double
    /// Ratio to the previous difficulty (1.04 means +4%).
    public let ratio: Double

    public init(time: Int, height: Int, difficulty: Double, ratio: Double) {
        self.time = time; self.height = height; self.difficulty = difficulty; self.ratio = ratio
    }

    public var changePercent: Double { (ratio - 1) * 100 }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(time)) }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        time = Int(try c.decode(Double.self))
        height = Int(try c.decode(Double.self))
        difficulty = try c.decode(Double.self)
        ratio = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(time); try c.encode(height); try c.encode(difficulty); try c.encode(ratio)
    }
}

/// Element of GET /api/v1/mining/blocks/fee-rates/{period}: fee-rate percentiles (sat/vB) averaged per bucket of blocks.
public struct BlockFeeRates: Codable, Sendable, Equatable {
    public let avgHeight: Double
    public let timestamp: Int
    public let p0: Double
    public let p10: Double
    public let p25: Double
    public let p50: Double
    public let p75: Double
    public let p90: Double
    public let p100: Double

    public init(avgHeight: Double, timestamp: Int, p0: Double, p10: Double, p25: Double, p50: Double, p75: Double, p90: Double, p100: Double) {
        self.avgHeight = avgHeight; self.timestamp = timestamp
        self.p0 = p0; self.p10 = p10; self.p25 = p25; self.p50 = p50; self.p75 = p75; self.p90 = p90; self.p100 = p100
    }

    enum CodingKeys: String, CodingKey {
        case avgHeight, timestamp
        case p0 = "avgFee_0", p10 = "avgFee_10", p25 = "avgFee_25", p50 = "avgFee_50"
        case p75 = "avgFee_75", p90 = "avgFee_90", p100 = "avgFee_100"
    }
}

/// Element of GET /api/v1/mining/blocks/fees/{period}: average total fees per block (sats).
public struct BlockFees: Codable, Sendable, Equatable {
    public let avgHeight: Double
    public let timestamp: Int
    public let avgFees: Double
    public let usd: Double?

    public init(avgHeight: Double, timestamp: Int, avgFees: Double, usd: Double?) {
        self.avgHeight = avgHeight; self.timestamp = timestamp; self.avgFees = avgFees; self.usd = usd
    }

    enum CodingKeys: String, CodingKey { case avgHeight, timestamp, avgFees, usd = "USD" }
}

/// GET /api/v1/mining/blocks/sizes-weights/{period} (weights ignored)
public struct BlockSizes: Codable, Sendable, Equatable {
    public let sizes: [Size]

    public init(sizes: [Size]) { self.sizes = sizes }

    public struct Size: Codable, Sendable, Equatable {
        public let avgHeight: Double
        public let timestamp: Int
        /// Bytes.
        public let avgSize: Double
        public init(avgHeight: Double, timestamp: Int, avgSize: Double) {
            self.avgHeight = avgHeight; self.timestamp = timestamp; self.avgSize = avgSize
        }
    }
}

/// GET /api/v1/mining/pools/{period}
public struct PoolsResponse: Codable, Sendable, Equatable {
    public let pools: [Pool]
    public let blockCount: Int

    public init(pools: [Pool], blockCount: Int) { self.pools = pools; self.blockCount = blockCount }

    public struct Pool: Codable, Sendable, Equatable {
        public let poolId: Int
        public let name: String
        public let blockCount: Int
        public let rank: Int
        public let emptyBlocks: Int?
        public let slug: String?

        public init(poolId: Int, name: String, blockCount: Int, rank: Int, emptyBlocks: Int?, slug: String?) {
            self.poolId = poolId; self.name = name; self.blockCount = blockCount
            self.rank = rank; self.emptyBlocks = emptyBlocks; self.slug = slug
        }
    }
}

/// Element of GET /api/v1/statistics/{period}: one mempool sample.
public struct MempoolStatistic: Codable, Sendable, Equatable {
    public let added: Int
    public let count: Int
    /// Incoming transaction rate.
    public let vbytesPerSecond: Double
    public let totalFee: Double?
    public let minFee: Double?
    /// vbytes per fee-rate bucket; their sum is the mempool size.
    public let vsizes: [Double]

    public init(added: Int, count: Int, vbytesPerSecond: Double, totalFee: Double?, minFee: Double?, vsizes: [Double]) {
        self.added = added; self.count = count; self.vbytesPerSecond = vbytesPerSecond
        self.totalFee = totalFee; self.minFee = minFee; self.vsizes = vsizes
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(added)) }
    public var totalVSize: Double { vsizes.reduce(0, +) }

    enum CodingKeys: String, CodingKey {
        case added, count, vsizes
        case vbytesPerSecond = "vbytes_per_second", totalFee = "total_fee", minFee = "min_fee"
    }
}

/// Element of GET /api/v1/fees/mempool-blocks: the next blocks a miner would build from the mempool.
public struct ProjectedBlock: Codable, Sendable, Equatable {
    public let blockSize: Double
    public let blockVSize: Double
    public let nTx: Int
    public let totalFees: Double
    public let medianFee: Double
    /// Fee rates from lowest to highest included (sat/vB).
    public let feeRange: [Double]

    public init(blockSize: Double, blockVSize: Double, nTx: Int, totalFees: Double, medianFee: Double, feeRange: [Double]) {
        self.blockSize = blockSize; self.blockVSize = blockVSize; self.nTx = nTx
        self.totalFees = totalFees; self.medianFee = medianFee; self.feeRange = feeRange
    }

    public var minFee: Double { feeRange.first ?? medianFee }
    public var maxFee: Double { feeRange.last ?? medianFee }
}
