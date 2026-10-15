import Foundation

/// Fee level for the next block: Low, Medium, High, Very high.
public enum Congestion: String, Sendable, Equatable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very high"

    public init(nextBlockFee: Double) {
        switch nextBlockFee {
        case ..<3: self = .low
        case ..<10: self = .medium
        case ..<30: self = .high
        default: self = .veryHigh
        }
    }

    /// 0...3, for meters.
    public var level: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// What paying a fee rate costs for a typical transaction.
public struct FeeCost: Sendable, Equatable {
    /// One SegWit input, two outputs (P2WPKH): the most common payment shape.
    public static let typicalVSize = 141

    public let rate: Double
    public let sats: Int
    public let fiat: Double?

    public init(rate: Double, price: Double?, vsize: Int = FeeCost.typicalVSize) {
        self.rate = rate
        let sats = Int((rate * Double(vsize)).rounded())
        self.sats = sats
        fiat = price.map { Double(sats) / 100_000_000 * $0 }
    }

    /// "141 sats · €0.10"
    public func summary(_ currency: Currency) -> String {
        var s = Format.sats(sats)
        if let fiat { s += " · " + currency.symbol + String(format: "%.2f", fiat) }
        return s
    }
}

public struct HalvingCountdown: Sendable, Equatable {
    public static let interval = 210_000
    public static let targetBlockTime: TimeInterval = 600

    public let nextHeight: Int
    public let remainingBlocks: Int
    public let estimatedDate: Date
    /// 0...1 through the current halving era.
    public let progress: Double

    public init(tipHeight: Int, tipDate: Date) {
        nextHeight = (tipHeight / Self.interval + 1) * Self.interval
        remainingBlocks = nextHeight - tipHeight
        estimatedDate = tipDate.addingTimeInterval(TimeInterval(remainingBlocks) * Self.targetBlockTime)
        progress = Double(Self.interval - remainingBlocks) / Double(Self.interval)
    }
}

/// Live extras for the Pulse tab beyond the shared widget snapshot.
public struct PulseExtras: Sendable, Equatable {
    public var projectedBlocks: [ProjectedBlock]
    /// Latest incoming rate, vB/s.
    public var inflow: Double?

    public init(projectedBlocks: [ProjectedBlock], inflow: Double?) {
        self.projectedBlocks = projectedBlocks; self.inflow = inflow
    }

    public static let empty = PulseExtras(projectedBlocks: [], inflow: nil)

    /// Fetches both parts concurrently; a part that fails is left empty.
    public static func load(_ client: MempoolClient) async -> PulseExtras {
        async let blocks = client.projectedBlocks()
        async let stats = client.mempoolStatistics(.twoHours)
        let b = try? await blocks
        let s = try? await stats
        let latest = s?.max { $0.added < $1.added }
        return PulseExtras(projectedBlocks: b ?? [], inflow: latest?.vbytesPerSecond)
    }

    public static func sample() -> PulseExtras {
        let medians = [3.0, 2.1, 1.6, 1.2, 1.0, 0.8, 0.5, 0.3]
        return PulseExtras(
            projectedBlocks: medians.map {
                ProjectedBlock(blockSize: 1_600_000, blockVSize: 997_950, nTx: 3_884, totalFees: 3_642_458,
                               medianFee: $0, feeRange: [$0 * 0.6, $0, $0 * 4])
            },
            inflow: 1_218
        )
    }
}
