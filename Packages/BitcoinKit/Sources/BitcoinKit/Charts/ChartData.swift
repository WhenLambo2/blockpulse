import Foundation

/// What a chart's values measure; drives axis labels, the selection readout and table cells.
public enum ChartUnit: Sendable, Equatable {
    case fiat(Currency)
    case sats
    case satPerVB
    case vMB
    case megabytes
    case count
    case vBytesPerSecond
    case hashrate
    case percent
    case difficulty

    /// Full value, e.g. "€73,984", "2.2 sat/vB", "812 EH/s".
    public func format(_ value: Double) -> String {
        switch self {
        case .fiat(let c): Format.price(value, c)
        case .sats: Format.sats(Int(value.rounded()))
        case .satPerVB: Format.feeRate(value)
        case .vMB: String(format: "%.1f vMB", value)
        case .megabytes: String(format: "%.2f MB", value)
        case .count: Format.grouped(value)
        case .vBytesPerSecond: Format.grouped(value) + " vB/s"
        case .hashrate: Format.grouped(value) + " EH/s"
        case .percent: Format.signedPercent(value)
        case .difficulty: String(format: "%.2f T", value)
        }
    }

    /// Short axis label, e.g. "€74k", "2.2", "38".
    public func axis(_ value: Double) -> String {
        switch self {
        case .fiat(let c): Format.compactPrice(value, c)
        case .sats, .count, .vBytesPerSecond: Format.compactCount(Int(value.rounded()))
        case .satPerVB: Format.feeRateNumber(value)
        case .vMB, .hashrate: Format.grouped(value)
        case .megabytes: String(format: "%.1f", value)
        case .percent: String(format: "%+.0f%%", value)
        case .difficulty: String(format: "%.0fT", value)
        }
    }
}

public struct ChartPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let value: Double
    /// Band charts: lower and upper edge around `value`.
    public let low: Double?
    public let high: Double?

    public var id: Date { date }

    public init(date: Date, value: Double, low: Double? = nil, high: Double? = nil) {
        self.date = date; self.value = value; self.low = low; self.high = high
    }
}

public struct ChartSeries: Sendable, Equatable, Identifiable {
    public let name: String
    public let unit: ChartUnit
    public let points: [ChartPoint]

    public var id: String { name }

    public init(name: String, unit: ChartUnit, points: [ChartPoint]) {
        self.name = name; self.unit = unit; self.points = points
    }
}

/// One labelled bar (difficulty adjustments, projected blocks) or donut slice (pools).
public struct ChartBar: Sendable, Equatable, Identifiable {
    public let label: String
    public let value: Double
    public var id: String { label }

    public init(label: String, value: Double) { self.label = label; self.value = value }
}

public struct ChartTable: Sendable, Equatable {
    public let columns: [String]
    public let rows: [[String]]

    public init(columns: [String], rows: [[String]]) { self.columns = columns; self.rows = rows }
    public static let empty = ChartTable(columns: [], rows: [])
}

/// A loaded chart: what to draw, the table behind it, and the headline value.
public struct ChartResult: Sendable, Equatable {
    public let id: ChartID
    public let period: ChartPeriod?
    /// First series is the primary one. The hashrate chart adds an "Average" series on the same
    /// scale and a "Difficulty" series drawn on its own scale.
    public let series: [ChartSeries]
    public let bars: [ChartBar]
    public let barUnit: ChartUnit?
    public let table: ChartTable
    /// Recent blocks chart: the blocks themselves, newest first.
    public let blocks: [Block]
    /// Current value, e.g. "€73,984".
    public let headline: String
    /// Change over the period, e.g. "+4.72%", nil when it doesn't apply.
    public let change: Double?

    public init(id: ChartID, period: ChartPeriod?, series: [ChartSeries] = [], bars: [ChartBar] = [], barUnit: ChartUnit? = nil,
                table: ChartTable, blocks: [Block] = [], headline: String, change: Double? = nil) {
        self.id = id; self.period = period; self.series = series; self.bars = bars; self.barUnit = barUnit
        self.table = table; self.blocks = blocks; self.headline = headline; self.change = change
    }
}

public enum Downsample {
    /// Averages points into at most `maxCount` equal stretches of time (first and last kept exact),
    /// so long ranges stay smooth to draw and drag across. Buckets are by time, not by count:
    /// mempool's price history is hourly for recent years and sparser before, and equal-count buckets
    /// squashed whole older years into a few averaged points (wrong values, drawn as a smooth curve).
    public static func bucketAverage(_ points: [ChartPoint], maxCount: Int = 240) -> [ChartPoint] {
        guard maxCount >= 3, points.count > maxCount else { return points }
        let inner = points.dropFirst().dropLast()
        let buckets = maxCount - 2
        let start = points[0].date.timeIntervalSince1970
        let span = points[points.count - 1].date.timeIntervalSince1970 - start
        guard span > 0 else { return [points[0], points[points.count - 1]] }
        var groups = [[ChartPoint]](repeating: [], count: buckets)
        for point in inner {
            let b = Int((point.date.timeIntervalSince1970 - start) / span * Double(buckets))
            groups[min(max(b, 0), buckets - 1)].append(point)
        }
        var out: [ChartPoint] = [points[0]]
        out.reserveCapacity(maxCount)
        for slice in groups where !slice.isEmpty {
            let n = Double(slice.count)
            let mid = slice[slice.count / 2].date
            let value = slice.reduce(0) { $0 + $1.value } / n
            let lows = slice.compactMap(\.low), highs = slice.compactMap(\.high)
            out.append(ChartPoint(
                date: mid,
                value: value,
                low: lows.isEmpty ? nil : lows.reduce(0, +) / Double(lows.count),
                high: highs.isEmpty ? nil : highs.reduce(0, +) / Double(highs.count)
            ))
        }
        out.append(points[points.count - 1])
        return out
    }

    /// Exactly `count` points at evenly spaced moments from the first to the last date, read off the
    /// line between neighbours. Two charts resampled to the same count can morph into each other point
    /// by point (switching period), instead of points popping in and out.
    public static func resample(_ points: [ChartPoint], count: Int) -> [ChartPoint] {
        guard count >= 2, points.count >= 2 else { return points }
        let start = points[0].date.timeIntervalSince1970
        let span = points[points.count - 1].date.timeIntervalSince1970 - start
        guard span > 0 else { return points }
        var out: [ChartPoint] = []
        out.reserveCapacity(count)
        var j = 0
        for i in 0..<count {
            let t = start + span * Double(i) / Double(count - 1)
            while j < points.count - 2 && points[j + 1].date.timeIntervalSince1970 < t { j += 1 }
            let a = points[j], b = points[j + 1]
            let ta = a.date.timeIntervalSince1970, tb = b.date.timeIntervalSince1970
            let f = tb > ta ? min(max((t - ta) / (tb - ta), 0), 1) : 0
            out.append(ChartPoint(date: Date(timeIntervalSince1970: t), value: a.value + (b.value - a.value) * f))
        }
        return out
    }
}
