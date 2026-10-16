import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BitcoinKit

@Suite struct FixtureTransportTests {
    let upstream = FakeTransport()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fixtures-\(UUID().uuidString)")

    private func client(_ transport: FixtureTransport) -> MempoolClient { MempoolClient(transport: transport) }

    @Test func fileNamesIncludePathAndQuery() {
        #expect(FixtureTransport.fileName(for: URL(string: "https://mempool.space/api/v1/mining/hashrate/1y")!) == "api_v1_mining_hashrate_1y.json")
        #expect(FixtureTransport.fileName(for: URL(string: "https://mempool.space/api/v1/historical-price?currency=EUR")!) == "api_v1_historical_price_currency_EUR.json")
    }

    @Test func recordsOnceThenReplays() async throws {
        try upstream.stub("/api/v1/prices", fixture: "prices")
        let transport = FixtureTransport(directory: directory, upstream: upstream)
        let first = try await client(transport).prices()
        upstream.stub("/api/v1/prices", status: 500, data: Data())
        let second = try await client(transport).prices()
        #expect(first == second)
        #expect(upstream.requests.count == 1)
    }

    @Test func failedResponsesAreNotSaved() async throws {
        upstream.stub("/api/v1/prices", status: 503, data: Data())
        let transport = FixtureTransport(directory: directory, upstream: upstream)
        await #expect(throws: MempoolError.self) { try await client(transport).prices() }
        try upstream.stub("/api/v1/prices", fixture: "prices")
        _ = try await client(transport).prices()
        #expect(upstream.requests.count == 2)
    }

    @Test func newestBlockIsShiftedToTipAge() async throws {
        try upstream.stub("/api/v1/blocks", fixture: "blocks")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let transport = FixtureTransport(directory: directory, upstream: upstream, tipAge: 150, now: { now })
        let original = try Fixture.decode([Block].self, "blocks")
        let blocks = try await client(transport).recentBlocks()
        #expect(blocks.count == original.count)
        #expect(blocks[0].height == original[0].height)
        #expect(blocks[0].timestamp == 1_800_000_000 - 150)
        // Spacing between blocks is kept.
        #expect(blocks[0].timestamp - blocks[1].timestamp == original[0].timestamp - original[1].timestamp)
    }

    @Test func newestBlockIsHeldBackUntilNewBlockAt() async throws {
        try upstream.stub("/api/v1/blocks", fixture: "blocks")
        let release = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000 - 10))
        let transport = FixtureTransport(directory: directory, upstream: upstream, newBlockAt: release, now: { clock.now })
        let original = try Fixture.decode([Block].self, "blocks")

        let before = try await client(transport).recentBlocks()
        #expect(before.first?.height == original[1].height)

        clock.now = release.addingTimeInterval(1)
        let after = try await client(transport).recentBlocks()
        #expect(after.first?.height == original[0].height)
        #expect(after.first?.timestamp == 1_800_000_000 - 2)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
