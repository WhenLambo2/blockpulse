import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BitcoinKit

@Suite struct ChartModelTests {
    @Test func decodesHashrate() throws {
        let h = try Fixture.decode(HashrateResponse.self, "hashrate")
        #expect(h.hashrates.count == 5)
        #expect(h.difficulty.first?.height == 967_680)
        #expect(h.currentHashrate == 8.5e20)
    }

    @Test func decodesDifficultyAdjustmentArrays() throws {
        let d = try Fixture.decode([DifficultyAdjustmentEntry].self, "difficulty-adjustments")
        #expect(d.count == 3)
        #expect(d[1].height == 967_680)
        #expect(abs(d[1].changePercent - 4.163) < 0.001)
        let roundTrip = try JSONDecoder().decode([DifficultyAdjustmentEntry].self, from: JSONEncoder().encode(d))
        #expect(roundTrip == d)
    }

    @Test func decodesFeeRatesFeesSizesPools() throws {
        let rates = try Fixture.decode([BlockFeeRates].self, "fee-rates")
        #expect(rates.count == 4)
        #expect(rates[0].p50 == 1 && rates[0].p100 == 250)
        let fees = try Fixture.decode([BlockFees].self, "block-fees")
        #expect(fees[0].avgFees == 1_395_775)
        #expect(fees[0].usd == 76_360)
        let sizes = try Fixture.decode(BlockSizes.self, "sizes-weights")
        #expect(sizes.sizes.count == 3)
        let pools = try Fixture.decode(PoolsResponse.self, "pools")
        #expect(pools.pools.count == 10)
        #expect(pools.blockCount == 770)
    }

    @Test func decodesStatisticsAndProjectedBlocks() throws {
        let stats = try Fixture.decode([MempoolStatistic].self, "statistics")
        #expect(stats.count == 3)
        #expect(stats[0].vbytesPerSecond == 1_218)
        #expect(stats[0].totalVSize == 6_919_000)
        let blocks = try Fixture.decode([ProjectedBlock].self, "mempool-blocks")
        #expect(blocks.count == 2)
        #expect(blocks[0].minFee < blocks[0].maxFee)
    }

    @Test func clientPaths() async throws {
        let transport = FakeTransport()
        let client = MempoolClient(transport: transport)
        try transport.stub("/api/v1/statistics/24h", fixture: "statistics")
        try transport.stub("/api/v1/mining/hashrate/1y", fixture: "hashrate")
        try transport.stub("/api/v1/mining/blocks/fee-rates/1w", fixture: "fee-rates")
        try transport.stub("/api/v1/fees/mempool-blocks", fixture: "mempool-blocks")
        _ = try await client.mempoolStatistics(.day)
        _ = try await client.hashrate(.year)
        _ = try await client.blockFeeRates(.week)
        _ = try await client.projectedBlocks()
        #expect(transport.requests.map { $0.url?.path } == [
            "/api/v1/statistics/24h", "/api/v1/mining/hashrate/1y", "/api/v1/mining/blocks/fee-rates/1w", "/api/v1/fees/mempool-blocks",
        ])
    }
}

@Suite struct ChartCatalogTests {
    @Test func everyChartBelongsToARealCategory() {
        for id in ChartID.allCases {
            #expect(id.category != .favourites)
            #expect(id.category.charts.contains(id))
        }
        #expect(ChartCategory.favourites.charts.isEmpty)
    }

    @Test func defaultPeriodIsOffered() {
        for id in ChartID.allCases {
            if let p = id.defaultPeriod { #expect(id.periods.contains(p), "\(id)") } else { #expect(id.periods.isEmpty) }
            #expect(!id.periods.contains(.twoHours))
        }
    }

    @Test func periodAPIValues() {
        #expect(ChartPeriod.allCases.map(\.apiValue) == ["2h", "24h", "1w", "1m", "1y", "3y", "5y", "all"])
        #expect(ChartPeriod.all.duration == nil)
    }

    @Test func periodPolicy() {
        // 5Y is a client-side window, so only the price-history charts may offer it.
        for id in ChartID.allCases where id.periods.contains(.fiveYears) {
            #expect([.price, .priceOther, .satsPerFiat].contains(id), "\(id)")
        }
        #expect(ChartID.mempoolSize.periods == [.day])
        #expect(ChartID.difficultyHistory.periods == [.year])
        #expect(!ChartID.pools.periods.contains(.all))
        #expect(ChartID.allCases.filter(\.hasTable) == [.projectedBlocks, .difficultyHistory, .pools])
        #expect(ChartCategory.market.charts == [.price, .priceOther, .satsPerFiat])
        #expect(ChartID.priceOther.title(.eur) == "BTC price (USD)")
        #expect(ChartID.priceOther.title(.usd) == "BTC price (EUR)")
    }
}

@Suite struct ChartBuilderTests {
    let now = Date(timeIntervalSince1970: 1_792_083_660)

    @Test func priceWindowAndChange() throws {
        let h = try Fixture.decode(HistoricalPriceResponse.self, "price-history")
        let week = ChartBuilder.price(h, period: .week, currency: .eur, now: now)
        let points = try #require(week.series.first?.points)
        #expect(points.count == 7)  // daily points inside the last 7 days
        #expect(points.first!.date < points.last!.date)
        #expect(week.headline == "€73,541")
        #expect((week.change ?? 0) > 0)
        #expect(week.table.rows.first?.last == "€73,541")  // newest row first
        let all = ChartBuilder.price(h, period: .all, currency: .usd, now: now)
        #expect(all.series[0].points.count == 60)
        #expect(all.headline == "$82,052")
        let other = ChartBuilder.price(h, period: .fiveYears, currency: .usd, now: now, id: .priceOther)
        #expect(other.id == .priceOther)
        #expect(other.headline == "$82,052")
    }

    @Test func satsPerFiat() throws {
        let h = try Fixture.decode(HistoricalPriceResponse.self, "price-history")
        let r = ChartBuilder.satsPerFiat(h, period: .day, currency: .eur, now: now)
        #expect(r.headline == Format.sats(Int((100_000_000 / 73_541.0).rounded())))
    }

    @Test func feeRatesBand() throws {
        let r = ChartBuilder.feeRates(try Fixture.decode([BlockFeeRates].self, "fee-rates"), period: .week)
        let p = try #require(r.series.first?.points.first)
        #expect(p.value == 1 && p.low == 0.5 && p.high == 2)
        #expect(r.headline == "4 sat/vB")
        #expect(r.table.columns.count == r.table.rows[0].count)
    }

    @Test func projectedBlocks() throws {
        let r = ChartBuilder.projectedBlocks(try Fixture.decode([ProjectedBlock].self, "mempool-blocks"))
        #expect(r.bars.map(\.label) == ["Next", "+1"])
        #expect(r.headline == "3 sat/vB")
        #expect(r.table.rows[0][2] == "2–41")
    }

    @Test func hashrateHasThreeSeries() throws {
        let r = ChartBuilder.hashrate(try Fixture.decode(HashrateResponse.self, "hashrate"), period: .year)
        #expect(r.series.map(\.name) == ["Hashrate", "Average", "Difficulty"])
        #expect(r.series[0].unit == .hashrate && r.series[1].unit == .hashrate)
        #expect(r.headline == "850 EH/s")
        #expect(abs((r.series[2].points.last?.value ?? 0) - 132.716) < 0.001)
    }

    @Test func difficultyHistoryNewestFirst() throws {
        let r = ChartBuilder.difficultyHistory(try Fixture.decode([DifficultyAdjustmentEntry].self, "difficulty-adjustments"), period: .year)
        #expect(r.headline == "-0.03%")
        #expect(r.table.rows.first?[1] == "#969,696")
        #expect(r.bars.last?.label == "#969,696")  // chart reads left to right, oldest first
        #expect(r.bars.count == r.table.rows.count)  // every adjustment, no cap
    }

    @Test func poolsTopEightPlusOther() throws {
        let r = ChartBuilder.pools(try Fixture.decode(PoolsResponse.self, "pools"), period: .week)
        #expect(r.bars.count == 9)
        #expect(r.bars.last?.label == "Other")
        #expect(abs(r.bars.reduce(0) { $0 + $1.value } - 100) < 0.001)
        #expect(r.headline == "Foundry USA · 36.0%")
    }

    @Test func mempoolSeries() throws {
        let stats = try Fixture.decode([MempoolStatistic].self, "statistics")
        let size = ChartBuilder.mempoolSize(stats, period: .day)
        #expect(size.series[0].points.first!.date < size.series[0].points.last!.date)
        #expect(size.headline == "6.9 vMB")
        #expect(ChartBuilder.mempoolInflow(stats, period: .day).headline == "1,218 vB/s")
        #expect(ChartBuilder.mempoolCount(stats, period: .day).headline == "84,119")
    }

    @Test func blocksAndSizes() throws {
        let blocks = ChartBuilder.recentBlocks(try Fixture.decode([Block].self, "blocks"))
        #expect(blocks.table.rows.count == 15)
        #expect(blocks.table.columns.count == 5)
        #expect(blocks.blocks.count == 15)
        #expect(zip(blocks.blocks, blocks.blocks.dropFirst()).allSatisfy { $0.height > $1.height })
        #expect(blocks.blocks.contains { $0.extras?.feeRange?.count == 7 })
        let sizes = ChartBuilder.blockSize(try Fixture.decode(BlockSizes.self, "sizes-weights"), period: .month)
        #expect(sizes.headline == "1.59 MB")
        let fees = ChartBuilder.blockFees(try Fixture.decode([BlockFees].self, "block-fees"), period: .week)
        #expect(fees.table.columns == ["Date", "Block", "Sats"])
    }

    @Test func smoothingAveragesLongSeriesOnly() {
        let short = (0..<50).map { ChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0)), value: Double($0 % 2)) }
        #expect(ChartBuilder.smoothed(short) == short)
        let long = (0..<600).map { ChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0)), value: Double($0 % 2), low: 0, high: 2) }
        let out = ChartBuilder.smoothed(long)  // window 10
        #expect(out.count == 600)
        #expect(out.map(\.date) == long.map(\.date))
        #expect(out[599].value == 0.5)
        #expect(out[599].low == 0 && out[599].high == 2)
    }

    @Test func downsampleKeepsEndsAndCount() {
        let points = (0..<1_000).map { ChartPoint(date: Date(timeIntervalSince1970: TimeInterval($0)), value: Double($0)) }
        let out = Downsample.bucketAverage(points, maxCount: 100)
        #expect(out.count <= 100)
        #expect(out.first == points.first)
        #expect(out.last == points.last)
        #expect(zip(out, out.dropFirst()).allSatisfy { $0.date < $1.date })
        #expect(Downsample.bucketAverage(Array(points.prefix(50)), maxCount: 100).count == 50)
    }

    @Test func downsampleBucketsByTimeNotCount() {
        // Like mempool's price history: daily for the first 1,000 days, hourly for the last 1,000.
        let day: TimeInterval = 86_400
        let daily = (0..<1_000).map { ChartPoint(date: Date(timeIntervalSince1970: Double($0) * day), value: Double($0)) }
        let hourly = (0..<24_000).map { ChartPoint(date: Date(timeIntervalSince1970: 1_000 * day + Double($0) * 3_600), value: 5_000) }
        let out = Downsample.bucketAverage(daily + hourly, maxCount: 240)
        let older = out.filter { $0.date.timeIntervalSince1970 < 1_000 * day }
        #expect(older.count >= 100)  // about half the points, not a handful
        #expect(older.allSatisfy { abs($0.value - $0.date.timeIntervalSince1970 / day) < 10 })
        #expect(zip(out, out.dropFirst()).allSatisfy { $0.date < $1.date })
    }
}

@Suite struct ChartLoaderTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_792_083_660)
    }

    @Test func cachesWithinLifetimeAndSharesPriceHistory() async throws {
        let transport = FakeTransport()
        try transport.stub("/api/v1/historical-price", fixture: "price-history")
        try transport.stub("/api/v1/fees/mempool-blocks", fixture: "mempool-blocks")
        let clock = Clock()
        let loader = ChartLoader(client: MempoolClient(transport: transport), now: { clock.now })

        _ = try await loader.load(.price, period: .week, currency: .eur)
        _ = try await loader.load(.price, period: .year, currency: .eur)
        _ = try await loader.load(.satsPerFiat, period: .month, currency: .usd)
        #expect(transport.requests.count == 1)  // one history download serves all three

        _ = try await loader.load(.projectedBlocks, period: nil, currency: .eur)
        _ = try await loader.load(.projectedBlocks, period: nil, currency: .eur)
        #expect(transport.requests.count == 2)
        clock.now = clock.now.addingTimeInterval(61)
        _ = try await loader.load(.projectedBlocks, period: nil, currency: .eur)
        #expect(transport.requests.count == 3)
        _ = try await loader.load(.projectedBlocks, period: nil, currency: .eur, force: true)
        #expect(transport.requests.count == 4)
        #expect(await loader.cached(.projectedBlocks, period: nil, currency: .eur) != nil)
    }

    @Test func priceHistoryPersistsToDisk() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bp-\(UUID().uuidString)/history.json")
        let transport = FakeTransport()
        try transport.stub("/api/v1/historical-price", fixture: "price-history")
        let clock = Clock()
        _ = try await ChartLoader(client: MempoolClient(transport: transport), priceHistoryFile: file, now: { clock.now })
            .load(.price, period: .week, currency: .eur)
        #expect(transport.requests.count == 1)

        transport.failure = MempoolError.network("offline")
        let second = try await ChartLoader(client: MempoolClient(transport: transport), priceHistoryFile: file, now: { clock.now })
            .load(.price, period: .week, currency: .eur)
        #expect(second.headline == "€73,541")
        #expect(transport.requests.count == 1)  // served from disk, no request
    }
}

@Suite struct PulseInsightTests {
    @Test func congestionLevels() {
        #expect(Congestion(nextBlockFee: 0.5) == .low)
        #expect(Congestion(nextBlockFee: 5) == .medium)
        #expect(Congestion(nextBlockFee: 12) == .high)
        #expect(Congestion(nextBlockFee: 80) == .veryHigh)
        #expect(Congestion.veryHigh.level == 3)
        #expect(Congestion.veryHigh.rawValue == "Very high")
    }

    @Test func typicalTransactionCost() {
        let c = FeeCost(rate: 1, price: 73_984)
        #expect(c.sats == 141)
        #expect(c.summary(.eur) == "141 sats · €0.10")
        #expect(FeeCost(rate: 2.5, price: nil).summary(.eur) == "353 sats")
    }

    @Test func halving() {
        let tip = Date(timeIntervalSince1970: 1_792_083_660)
        let h = HalvingCountdown(tipHeight: 971_150, tipDate: tip)
        #expect(h.nextHeight == 1_050_000)
        #expect(h.remainingBlocks == 78_850)
        #expect(h.estimatedDate == tip.addingTimeInterval(78_850 * 600))
        #expect(abs(h.progress - (210_000 - 78_850) / 210_000.0) < 1e-9)
        #expect(HalvingCountdown(tipHeight: 840_000, tipDate: tip).nextHeight == 1_050_000)
    }

    @Test func extrasLoadToleratesFailure() async throws {
        let transport = FakeTransport()
        try transport.stub("/api/v1/fees/mempool-blocks", fixture: "mempool-blocks")
        let extras = await PulseExtras.load(MempoolClient(transport: transport))
        #expect(extras.projectedBlocks.count == 2)
        #expect(extras.inflow == nil)  // statistics/2h not stubbed -> 404
    }
}

@Suite struct AppPreferencesTests {
    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "bp-prefs-\(UUID().uuidString)")!)

    @Test func defaults() {
        #expect(prefs.appearance == .dark)
        #expect(prefs.favourites == ChartID.defaultFavourites)
    }

    @Test func favouritesToggleAndOrder() {
        #expect(prefs.toggleFavourite(.hashrate))
        #expect(prefs.favourites == [.price, .feeRates, .mempoolSize, .hashrate])
        #expect(!prefs.toggleFavourite(.price))
        #expect(prefs.favourites == [.feeRates, .mempoolSize, .hashrate])
        prefs.favourites = []
        #expect(prefs.favourites.isEmpty)  // explicit empty is kept, not reset to defaults
        prefs.favourites = [.pools, .pools, .blockSize]
        #expect(prefs.favourites == [.pools, .blockSize])
    }

    @Test func homeCardOrder() {
        #expect(prefs.homeCardOrder == HomeCard.allCases)
        prefs.homeCardOrder = [.blocks, .fees]
        #expect(prefs.homeCardOrder == [.blocks, .fees, .mempool, .difficulty, .halving])
        #expect(HomeCard.ordered(["halving", "bogus", "halving"]) == [.halving, .fees, .mempool, .difficulty, .blocks])
    }

    @Test func appearancePersists() {
        prefs.appearance = .system
        #expect(prefs.appearance == .system)
    }
}
