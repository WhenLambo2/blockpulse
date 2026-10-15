import Foundation
import Testing
@testable import BitcoinKit

@Suite struct SnapshotTests {
    let price = PriceInfo(eur: 73_984, usd: 82_565, eur24hAgo: 74_651, usd24hAgo: 83_580, updatedAt: Date(timeIntervalSince1970: 1_791_841_806))

    @Test func priceInfoMath() throws {
        #expect(price.price(in: .eur) == 73_984)
        #expect(price.price(in: .usd) == 82_565)
        let change = try #require(price.change24hPercent(in: .eur))
        #expect(abs(change - (-0.8935))  < 0.001)
        #expect(price.satsPerUnit(in: .eur) == 1_352)
    }

    @Test func priceInfoMissingOrZeroBaselines() {
        let p = PriceInfo(eur: 0, usd: 1, eur24hAgo: nil, usd24hAgo: 0, updatedAt: .now)
        #expect(p.change24hPercent(in: .eur) == nil)
        #expect(p.change24hPercent(in: .usd) == nil)
        #expect(p.satsPerUnit(in: .eur) == nil)
    }

    @Test func blockSummaryFromBlock() throws {
        let block = try Fixture.decode([Block].self, "blocks")[0]
        let s = BlockSummary(block: block)
        #expect(s.height == block.height)
        #expect(s.id == block.id)
        #expect(s.timestamp == Date(timeIntervalSince1970: TimeInterval(block.timestamp)))
        #expect(s.poolName == block.extras?.pool?.name)
        #expect(s.medianFee == block.extras?.medianFee)
    }

    @Test func snapshotDerivedValues() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let s = BitcoinSnapshot.sample(fetchedAt: now)
        #expect(s.tipHeight == s.blocks.first?.height)
        #expect(s.lastBlockDate == s.blocks.first?.timestamp)
        #expect(!s.isEmpty)
        #expect(!s.isStale(now: now.addingTimeInterval(30 * 60)))
        #expect(s.isStale(now: now.addingTimeInterval(30 * 60 + 1)))
        #expect(BitcoinSnapshot(fetchedAt: now, price: nil, blocks: [], fees: nil, mempool: nil, difficulty: nil).isEmpty)
    }

    @Test func sampleIsOrderedNewestFirst() {
        let s = BitcoinSnapshot.sample()
        #expect(s.blocks.count == 5)
        #expect(zip(s.blocks, s.blocks.dropFirst()).allSatisfy { $0.height == $1.height + 1 })
    }

    @Test func storeRoundTrip() throws {
        let store = SnapshotStore(fileURL: tempFile())
        #expect(store.load() == nil)
        let s = BitcoinSnapshot.sample(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func storeCreatesMissingDirectory() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("nested").appendingPathComponent("snapshot.json")
        try SnapshotStore(fileURL: url).save(.sample())
        #expect(SnapshotStore(fileURL: url).load() != nil)
    }

    @Test func storeCorruptFileReturnsNil() throws {
        let url = tempFile()
        try Data("{\"fetchedAt\": tru".utf8).write(to: url)
        #expect(SnapshotStore(fileURL: url).load() == nil)
    }

    @Test func refreshPolicy() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RefreshPolicy.nextReload(for: .live, now: now) == now.addingTimeInterval(15 * 60))
        #expect(RefreshPolicy.nextReload(for: .cache, now: now) == now.addingTimeInterval(5 * 60))
        #expect(RefreshPolicy.nextReload(for: .none, now: now) == now.addingTimeInterval(5 * 60))
        // Fresh snapshot: one entry now plus one at the moment it turns stale.
        #expect(RefreshPolicy.entryDates(now: now, fetchedAt: now) == [now, now.addingTimeInterval(30 * 60 + 1)])
        // Already stale: just now.
        #expect(RefreshPolicy.entryDates(now: now, fetchedAt: now.addingTimeInterval(-3600)) == [now])
        #expect(RefreshPolicy.entryDates(now: now, fetchedAt: nil) == [now])
    }

    @Test func nextReloadForResult() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snap = BitcoinSnapshot.sample(fetchedAt: now)
        let clean = SnapshotResult(snapshot: snap, source: .live, error: nil)
        let partial = SnapshotResult(snapshot: snap, source: .live, error: .http(500))
        let cached = SnapshotResult(snapshot: snap, source: .cache, error: .rateLimited)
        let none = SnapshotResult(snapshot: nil, source: .none, error: .network("offline"))
        #expect(RefreshPolicy.nextReload(for: clean, now: now) == now.addingTimeInterval(15 * 60))
        #expect(RefreshPolicy.nextReload(for: partial, now: now) == now.addingTimeInterval(5 * 60))
        #expect(RefreshPolicy.nextReload(for: cached, now: now) == now.addingTimeInterval(5 * 60))
        #expect(RefreshPolicy.nextReload(for: none, now: now) == now.addingTimeInterval(5 * 60))
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
    }
}
