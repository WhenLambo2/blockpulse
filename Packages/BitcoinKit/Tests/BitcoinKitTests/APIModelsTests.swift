import Foundation
import Testing
@testable import BitcoinKit

@Suite struct APIModelsTests {
    @Test func currency() {
        #expect(Currency.eur.code == "EUR")
        #expect(Currency.eur.symbol == "€")
        #expect(Currency.usd.symbol == "$")
        #expect(Currency.eur.other == .usd)
        #expect(Currency.usd.other == .eur)
        #expect(Currency.allCases == [.eur, .usd])
    }

    @Test func decodesPrices() throws {
        let p = try Fixture.decode(Prices.self, "prices")
        #expect(p.eur > 1_000)
        #expect(p.usd > 1_000)
        #expect(p.date.timeIntervalSince1970 == TimeInterval(p.time))
    }

    @Test func decodesHistoricalPrice() throws {
        let h = try Fixture.decode(HistoricalPriceResponse.self, "historical-price")
        #expect(h.prices.count == 1)
        #expect((h.prices[0].eur ?? 0) > 1_000)
    }

    @Test func decodesEmptyHistoricalPrice() throws {
        let h = try JSONDecoder().decode(HistoricalPriceResponse.self, from: Data(#"{"prices":[],"exchangeRates":{}}"#.utf8))
        #expect(h.prices.isEmpty)
    }

    @Test func decodesBlocks() throws {
        let blocks = try Fixture.decode([Block].self, "blocks")
        #expect(blocks.count == 15)
        let tip = blocks[0]
        #expect(tip.height > 971_000)
        #expect(tip.txCount > 0)
        #expect(tip.extras?.pool?.name.isEmpty == false)
        #expect(tip.extras?.medianFee != nil)
        #expect(blocks[0].height == blocks[1].height + 1)
    }

    @Test func decodesBlockWithoutExtras() throws {
        let json = #"[{"id":"abc","height":1,"timestamp":1231006505,"tx_count":1,"size":285,"weight":1140}]"#
        let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        #expect(blocks[0].extras == nil)
    }

    @Test func decodesFees() throws {
        let f = try Fixture.decode(RecommendedFees.self, "fees-precise")
        #expect(f.fastestFee >= f.economyFee)
        let fractional = try JSONDecoder().decode(RecommendedFees.self, from: Data(#"{"fastestFee":0.5,"halfHourFee":0.4,"hourFee":0.3,"economyFee":0.2,"minimumFee":0.1}"#.utf8))
        #expect(fractional.fastestFee == 0.5)
    }

    @Test func decodesMempool() throws {
        let m = try Fixture.decode(MempoolStats.self, "mempool")
        #expect(m.count > 0)
        #expect(m.vsize > 0)
        #expect(m.blocksToClear == Int((Double(m.vsize) / 1_000_000).rounded(.up)))
        #expect(MempoolStats(count: 0, vsize: 0, totalFee: 0).blocksToClear == 0)
        #expect(MempoolStats(count: 1, vsize: 1, totalFee: 1).blocksToClear == 1)
    }

    @Test func decodesDifficulty() throws {
        let d = try Fixture.decode(DifficultyAdjustment.self, "difficulty-adjustment")
        #expect(d.remainingBlocks > 0)
        #expect(d.retargetDate.timeIntervalSince1970 == d.estimatedRetargetDate / 1000)
    }
}
