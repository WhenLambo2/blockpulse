import Foundation

/// Time window of a chart. `apiValue` is the mempool.space period segment.
public enum ChartPeriod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Only used for the Pulse tab's arrival rate; never offered in a picker.
    case twoHours = "2h"
    case day = "24h"
    case week = "1w"
    case month = "1m"
    case year = "1y"
    case threeYears = "3y"
    /// Client-side window over the price history only; the mining API has no 5y period.
    case fiveYears = "5y"
    case all = "all"

    public var id: String { rawValue }
    public var apiValue: String { rawValue }

    public var label: String {
        switch self {
        case .twoHours: "2H"
        case .day: "24H"
        case .week: "1W"
        case .month: "1M"
        case .year: "1Y"
        case .threeYears: "3Y"
        case .fiveYears: "5Y"
        case .all: "All"
        }
    }

    /// Window length, nil for all-time.
    public var duration: TimeInterval? {
        switch self {
        case .twoHours: 2 * 3_600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .year: 365 * 86_400
        case .threeYears: 3 * 365 * 86_400
        case .fiveYears: 5 * 365 * 86_400
        case .all: nil
        }
    }
}

public enum ChartCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case favourites, market, fees, mempool, mining, blocks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .favourites: "Favourites"
        case .market: "Market"
        case .fees: "Fees"
        case .mempool: "Mempool"
        case .mining: "Mining"
        case .blocks: "Blocks"
        }
    }

    public var systemImage: String {
        switch self {
        case .favourites: "star.fill"
        case .market: "eurosign.circle"
        case .fees: "gauge.with.dots.needle.33percent"
        case .mempool: "tray.full"
        case .mining: "hammer"
        case .blocks: "cube"
        }
    }

    /// Charts in this category, in display order. Favourites are the user's list instead.
    public var charts: [ChartID] { ChartID.allCases.filter { $0.category == self } }
}

/// How a chart is drawn.
public enum ChartStyle: Sendable, Equatable {
    case line, area, band, bars, donut
    /// Recent blocks drawn as a horizontal row of block cards.
    case blocks
}

/// Every chart in the Charts tab. The raw value is what favourites persist.
public enum ChartID: String, Codable, CaseIterable, Sendable, Identifiable {
    case price, priceOther, satsPerFiat
    case feeRates, blockFees
    case mempoolSize, mempoolCount, mempoolInflow, projectedBlocks
    case hashrate, difficultyHistory, pools
    case blockSize, recentBlocks

    public var id: String { rawValue }

    public static let defaultFavourites: [ChartID] = [.price, .feeRates, .mempoolSize]

    public var category: ChartCategory {
        switch self {
        case .price, .priceOther, .satsPerFiat: .market
        case .feeRates, .blockFees: .fees
        case .mempoolSize, .mempoolCount, .mempoolInflow, .projectedBlocks: .mempool
        case .hashrate, .difficultyHistory, .pools: .mining
        case .blockSize, .recentBlocks: .blocks
        }
    }

    public func title(_ currency: Currency) -> String {
        switch self {
        case .price: "BTC price (\(currency.code))"
        case .priceOther: "BTC price (\(currency.other.code))"
        case .satsPerFiat: "Sats per \(currency.symbol)1"
        case .feeRates: "Fee rates per block"
        case .blockFees: "Total fees per block"
        case .mempoolSize: "Mempool size"
        case .mempoolCount: "Mempool transactions"
        case .mempoolInflow: "Incoming transactions"
        case .projectedBlocks: "Next projected blocks"
        case .hashrate: "Hashrate & difficulty"
        case .difficultyHistory: "Difficulty adjustments"
        case .pools: "Mining pools"
        case .blockSize: "Block size"
        case .recentBlocks: "Recent blocks"
        }
    }

    public var subtitle: String {
        switch self {
        case .price, .priceOther: "Price history from mempool.space"
        case .satsPerFiat: "How many sats one unit of money buys"
        case .feeRates: "Middle half of payers (band) and median (line)"
        case .blockFees: "Average fees collected by miners per block"
        case .mempoolSize: "Unconfirmed transactions waiting over the last 24 hours, in vMB"
        case .mempoolCount: "Unconfirmed transactions over the last 24 hours"
        case .mempoolInflow: "New transactions arriving over the last 24 hours, in vB per second"
        case .projectedBlocks: "Median fee of the blocks a miner would build now"
        case .hashrate: "Tap the legend to show or hide a line"
        case .difficultyHistory: "Change at each retarget over the past year"
        case .pools: "Share of blocks found"
        case .blockSize: "Average block size in MB"
        case .recentBlocks: "The latest blocks, newest first. Swipe for more"
        }
    }

    public var style: ChartStyle {
        switch self {
        case .price, .priceOther, .satsPerFiat, .blockFees, .mempoolCount, .mempoolInflow, .hashrate, .blockSize: .line
        case .mempoolSize: .area
        case .feeRates: .band
        case .projectedBlocks, .difficultyHistory: .bars
        case .pools: .donut
        case .recentBlocks: .blocks
        }
    }

    /// Periods offered in the picker. One or none means no picker is shown.
    public var periods: [ChartPeriod] {
        switch self {
        case .price, .priceOther, .satsPerFiat: [.day, .week, .month, .year, .fiveYears, .all]
        case .feeRates, .blockFees, .blockSize: [.day, .week, .month, .year, .threeYears]
        // Longer mempool statistics periods come back as invalid JSON from mempool.space.
        case .mempoolSize, .mempoolCount, .mempoolInflow: [.day]
        case .hashrate: [.month, .year, .threeYears, .all]
        case .difficultyHistory: [.year]
        case .pools: [.day, .week, .month, .year]
        case .projectedBlocks, .recentBlocks: []
        }
    }

    public var defaultPeriod: ChartPeriod? {
        switch self {
        case .price, .priceOther, .satsPerFiat: .month
        case .feeRates, .blockFees, .blockSize, .pools: .week
        case .mempoolSize, .mempoolCount, .mempoolInflow: .day
        case .hashrate, .difficultyHistory: .year
        case .projectedBlocks, .recentBlocks: nil
        }
    }

    /// Whether the card offers a table view (only where the numbers read better as a list).
    public var hasTable: Bool {
        switch self {
        case .projectedBlocks, .difficultyHistory, .pools: true
        default: false
        }
    }

    /// How long a loaded chart stays fresh before it is fetched again.
    public var cacheLifetime: TimeInterval {
        switch self {
        case .price, .priceOther, .satsPerFiat: 60 * 60  // the 1.1 MB history itself is kept for a day, see ChartLoader
        case .projectedBlocks, .recentBlocks: 60
        case .mempoolSize, .mempoolCount, .mempoolInflow: 5 * 60
        case .feeRates, .blockFees, .blockSize, .pools: 10 * 60
        case .hashrate, .difficultyHistory: 60 * 60
        }
    }
}
