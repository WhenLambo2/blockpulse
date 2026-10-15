import Foundation

/// Turns API responses into `ChartResult`s. Pure functions, so every chart is tested on Linux.
public enum ChartBuilder {
    static let maxPoints = 240
    static let maxTableRows = 200

    // MARK: - Market

    /// `id` is `.price` (the chosen currency) or `.priceOther` (pass the other currency).
    public static func price(_ history: HistoricalPriceResponse, period: ChartPeriod, currency: Currency, now: Date,
                             id: ChartID = .price) -> ChartResult {
        let points = window(history.prices.compactMap { p -> ChartPoint? in
            guard let v = currency == .eur ? p.eur : p.usd, v > 0 else { return nil }
            return ChartPoint(date: date(p.time), value: v)
        }, period: period, now: now)
        return line(id, period: period, name: "Price", unit: .fiat(currency), points: points, valueColumn: currency.code)
    }

    public static func satsPerFiat(_ history: HistoricalPriceResponse, period: ChartPeriod, currency: Currency, now: Date) -> ChartResult {
        let points = window(history.prices.compactMap { p -> ChartPoint? in
            guard let v = currency == .eur ? p.eur : p.usd, v > 0 else { return nil }
            return ChartPoint(date: date(p.time), value: 100_000_000 / v)
        }, period: period, now: now)
        return line(.satsPerFiat, period: period, name: "Sats", unit: .sats, points: points, valueColumn: "Sats")
    }

    // MARK: - Fees

    public static func feeRates(_ rates: [BlockFeeRates], period: ChartPeriod) -> ChartResult {
        let sorted = rates.sorted { $0.timestamp < $1.timestamp }
        let points = Downsample.bucketAverage(
            smoothed(sorted.map { ChartPoint(date: date($0.timestamp), value: $0.p50, low: $0.p25, high: $0.p75) }),
            maxCount: maxPoints
        )
        let rows = sorted.reversed().prefix(maxTableRows).map { r in
            [tableDate(date(r.timestamp), period), Format.blockHeight(Int(r.avgHeight)),
             Format.feeRateNumber(r.p10), Format.feeRateNumber(r.p50), Format.feeRateNumber(r.p90)]
        }
        return ChartResult(
            id: .feeRates, period: period,
            series: [ChartSeries(name: "Median", unit: .satPerVB, points: points)],
            table: ChartTable(columns: ["Date", "Block", "10%", "Median", "90%"], rows: Array(rows)),
            headline: sorted.last.map { Format.feeRate($0.p50) } ?? "—",
            change: nil
        )
    }

    public static func blockFees(_ fees: [BlockFees], period: ChartPeriod) -> ChartResult {
        let sorted = fees.sorted { $0.timestamp < $1.timestamp }
        var result = line(.blockFees, period: period, name: "Fees", unit: .sats,
                          points: sorted.map { ChartPoint(date: date($0.timestamp), value: $0.avgFees) }, valueColumn: "Sats")
        let rows = sorted.reversed().prefix(maxTableRows).map { f in
            [tableDate(date(f.timestamp), period), Format.blockHeight(Int(f.avgHeight)), Format.grouped(f.avgFees)]
        }
        result = ChartResult(id: result.id, period: period, series: result.series,
                             table: ChartTable(columns: ["Date", "Block", "Sats"], rows: Array(rows)),
                             headline: result.headline, change: result.change)
        return result
    }

    // MARK: - Mempool

    public static func mempoolSize(_ stats: [MempoolStatistic], period: ChartPeriod) -> ChartResult {
        let points = stats.sorted { $0.added < $1.added }.map { ChartPoint(date: $0.date, value: $0.totalVSize / 1_000_000) }
        return line(.mempoolSize, period: period, name: "vMB", unit: .vMB, points: points, valueColumn: "vMB")
    }

    public static func mempoolCount(_ stats: [MempoolStatistic], period: ChartPeriod) -> ChartResult {
        let points = stats.sorted { $0.added < $1.added }.map { ChartPoint(date: $0.date, value: Double($0.count)) }
        return line(.mempoolCount, period: period, name: "Transactions", unit: .count, points: points, valueColumn: "Transactions")
    }

    public static func mempoolInflow(_ stats: [MempoolStatistic], period: ChartPeriod) -> ChartResult {
        let points = stats.sorted { $0.added < $1.added }.map { ChartPoint(date: $0.date, value: $0.vbytesPerSecond) }
        return line(.mempoolInflow, period: period, name: "vB/s", unit: .vBytesPerSecond, points: points, valueColumn: "vB/s")
    }

    public static func projectedBlocks(_ blocks: [ProjectedBlock]) -> ChartResult {
        let bars = blocks.enumerated().map { i, b in ChartBar(label: i == 0 ? "Next" : "+\(i)", value: b.medianFee) }
        let rows = blocks.enumerated().map { i, b in
            [i == 0 ? "Next" : "+\(i)", Format.feeRateNumber(b.medianFee),
             "\(Format.feeRateNumber(b.minFee))–\(Format.feeRateNumber(b.maxFee))",
             Format.grouped(Double(b.nTx)), String(format: "%.2f", b.blockVSize / 1_000_000)]
        }
        return ChartResult(
            id: .projectedBlocks, period: nil, bars: bars, barUnit: .satPerVB,
            table: ChartTable(columns: ["Block", "Median", "Range", "Tx", "vMB"], rows: rows),
            headline: blocks.first.map { Format.feeRate($0.medianFee) } ?? "—"
        )
    }

    // MARK: - Mining

    /// Three series: raw daily hashrate, its moving average (both EH/s) and difficulty (T).
    public static func hashrate(_ response: HashrateResponse, period: ChartPeriod) -> ChartResult {
        let raw = response.hashrates.sorted { $0.timestamp < $1.timestamp }
            .map { ChartPoint(date: date($0.timestamp), value: $0.avgHashrate / 1e18) }
        // Daily values: a 14-day moving average (shorter for the 1M view) reads as the trend.
        let average = Downsample.bucketAverage(smoothed(raw, window: min(14, raw.count / 6)), maxCount: maxPoints)
        let diff = response.difficulty.sorted { $0.time < $1.time }
            .map { ChartPoint(date: date($0.time), value: $0.difficulty / 1e12) }
        let rows = average.reversed().prefix(maxTableRows).map { [tableDate($0.date, period), Format.grouped($0.value)] }
        let current = response.currentHashrate.map { $0 / 1e18 } ?? raw.last?.value
        return ChartResult(
            id: .hashrate, period: period,
            series: [ChartSeries(name: "Hashrate", unit: .hashrate, points: Downsample.bucketAverage(raw, maxCount: maxPoints)),
                     ChartSeries(name: "Average", unit: .hashrate, points: average),
                     ChartSeries(name: "Difficulty", unit: .difficulty, points: diff)],
            table: ChartTable(columns: ["Date", "EH/s"], rows: Array(rows)),
            headline: current.map(ChartUnit.hashrate.format) ?? "—",
            change: change(average)
        )
    }

    /// Every adjustment in the period as a bar, oldest first; the table lists newest first.
    public static func difficultyHistory(_ entries: [DifficultyAdjustmentEntry], period: ChartPeriod) -> ChartResult {
        let newestFirst = entries.sorted { $0.height > $1.height }
        let bars = newestFirst.reversed().map { ChartBar(label: Format.blockHeight($0.height), value: $0.changePercent) }
        let rows = newestFirst.prefix(maxTableRows).map { e in
            [tableDate(e.date, .year), Format.blockHeight(e.height),
             ChartUnit.difficulty.format(e.difficulty / 1e12), Format.signedPercent(e.changePercent)]
        }
        return ChartResult(
            id: .difficultyHistory, period: period, bars: Array(bars), barUnit: .percent,
            table: ChartTable(columns: ["Date", "Block", "Difficulty", "Change"], rows: Array(rows)),
            headline: newestFirst.first.map { Format.signedPercent($0.changePercent) } ?? "—"
        )
    }

    /// Top 8 pools plus "Other"; bar values are percent of blocks.
    public static func pools(_ response: PoolsResponse, period: ChartPeriod) -> ChartResult {
        let total = Double(max(response.blockCount, response.pools.reduce(0) { $0 + $1.blockCount }, 1))
        let ranked = response.pools.sorted { $0.blockCount > $1.blockCount }
        var bars = ranked.prefix(8).map { ChartBar(label: $0.name, value: Double($0.blockCount) / total * 100) }
        let rest = ranked.dropFirst(8).reduce(0) { $0 + $1.blockCount }
        if rest > 0 { bars.append(ChartBar(label: "Other", value: Double(rest) / total * 100)) }
        let rows = ranked.prefix(maxTableRows).enumerated().map { i, p in
            ["\(i + 1)", p.name, Format.grouped(Double(p.blockCount)), String(format: "%.1f%%", Double(p.blockCount) / total * 100)]
        }
        let top = ranked.first.map { "\($0.name) · " + String(format: "%.1f%%", Double($0.blockCount) / total * 100) }
        return ChartResult(
            id: .pools, period: period, bars: bars, barUnit: .percent,
            table: ChartTable(columns: ["#", "Pool", "Blocks", "Share"], rows: Array(rows)),
            headline: top ?? "—"
        )
    }

    // MARK: - Blocks

    public static func blockSize(_ sizes: BlockSizes, period: ChartPeriod) -> ChartResult {
        let points = sizes.sizes.sorted { $0.timestamp < $1.timestamp }
            .map { ChartPoint(date: date($0.timestamp), value: $0.avgSize / 1_000_000) }
        return line(.blockSize, period: period, name: "MB", unit: .megabytes, points: points, valueColumn: "MB")
    }

    public static func recentBlocks(_ blocks: [Block]) -> ChartResult {
        let sorted = blocks.sorted { $0.height > $1.height }
        let rows = sorted.map { b in
            [Format.blockHeight(b.height), tableDate(date(b.timestamp), .day), Format.grouped(Double(b.txCount)),
             b.extras?.medianFee.map(Format.feeRateNumber) ?? "—", b.extras?.pool?.name ?? "Unknown"]
        }
        return ChartResult(
            id: .recentBlocks, period: nil,
            table: ChartTable(columns: ["Block", "Time", "Tx", "Median", "Pool"], rows: rows),
            blocks: sorted,
            headline: sorted.first.map { Format.blockHeight($0.height) } ?? "—"
        )
    }

    // MARK: - Helpers

    /// Keeps points inside the period (ending at `now`), sorted oldest first.
    static func window(_ points: [ChartPoint], period: ChartPeriod, now: Date) -> [ChartPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard let duration = period.duration else { return sorted }
        let cutoff = now.addingTimeInterval(-duration)
        return sorted.filter { $0.date >= cutoff }
    }

    static func line(_ id: ChartID, period: ChartPeriod, name: String, unit: ChartUnit, points: [ChartPoint], valueColumn: String) -> ChartResult {
        let drawn = Downsample.bucketAverage(points, maxCount: maxPoints)
        let rows = drawn.reversed().prefix(maxTableRows).map { [tableDate($0.date, period), unit.format($0.value)] }
        return ChartResult(
            id: id, period: period,
            series: [ChartSeries(name: name, unit: unit, points: drawn)],
            table: ChartTable(columns: ["Date", valueColumn], rows: Array(rows)),
            headline: points.last.map { unit.format($0.value) } ?? "—",
            change: change(points)
        )
    }

    /// Trailing moving average over about 1/60th of the series, so noisy per-block and daily
    /// data reads as a trend (like mempool.space's averaged lines). Short series are left as is.
    static func smoothed(_ points: [ChartPoint], parts: Int = 60) -> [ChartPoint] {
        smoothed(points, window: points.count / parts)
    }

    /// Trailing moving average over `window` points; a window of 1 or less leaves the series as is.
    static func smoothed(_ points: [ChartPoint], window: Int) -> [ChartPoint] {
        guard window > 1 else { return points }
        func avg(_ slice: ArraySlice<ChartPoint>, _ value: (ChartPoint) -> Double?) -> Double? {
            let values = slice.compactMap(value)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return points.indices.map { i in
            let slice = points[max(0, i - window + 1)...i]
            return ChartPoint(date: points[i].date, value: avg(slice, { $0.value }) ?? points[i].value,
                              low: avg(slice, \.low), high: avg(slice, \.high))
        }
    }

    /// Percent change from first to last point, nil when it can't be computed.
    static func change(_ points: [ChartPoint]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value, points.count > 1, first != 0 else { return nil }
        return (last - first) / first * 100
    }

    static func date(_ unix: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(unix)) }

    /// "15 Oct 14:05" for short periods, "15 Oct 2026" for long ones.
    static func tableDate(_ date: Date, _ period: ChartPeriod) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = .current
        switch period {
        case .twoHours, .day, .week: f.dateFormat = "d MMM HH:mm"
        case .month, .year, .threeYears, .fiveYears, .all: f.dateFormat = "d MMM yyyy"
        }
        return f.string(from: date)
    }
}
