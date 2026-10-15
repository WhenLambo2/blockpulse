import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BitcoinKit

@Suite struct SnapshotServiceTests {
    let transport = FakeTransport()
    let now = Date(timeIntervalSince1970: 1_791_842_000)
    let store = SnapshotStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).json"))

    func service(store: SnapshotStore? = nil) -> SnapshotService {
        let fixed = now
        return SnapshotService(client: MempoolClient(transport: transport), store: store ?? self.store, now: { fixed })
    }

    @Test func refreshAllSucceed() async throws {
        try transport.stubAllFixtures()
        let s = try await service().refresh()
        #expect(s.fetchedAt == now)
        #expect(s.price?.eur24hAgo != nil)
        #expect(s.price?.change24hPercent(in: .eur) != nil)
        #expect(s.blocks.count == 10)
        #expect(s.blocks[0].height > s.blocks[1].height)
        #expect(s.fees != nil && s.mempool != nil && s.difficulty != nil)
        #expect(store.load() == s)
        #expect(transport.requests.count == 6)
    }

    @Test func historicalTimestampIs24hBeforeNow() async throws {
        try transport.stubAllFixtures()
        _ = try await service().refresh()
        let hist = try #require(transport.requests.first { $0.url?.path == "/api/v1/historical-price" }?.url)
        let ts = URLComponents(url: hist, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "timestamp" }?.value
        #expect(ts == String(Int(now.timeIntervalSince1970) - 86_400))
    }

    @Test func partialFailureKeepsOtherSections() async throws {
        try transport.stubAllFixtures()
        transport.stub("/api/v1/prices", status: 500, data: Data())
        let s = try await service().refresh()
        #expect(s.price == nil)
        #expect(!s.blocks.isEmpty)
        #expect(s.fees != nil)
    }

    @Test func emptyHistoricalPriceGivesNilChange() async throws {
        try transport.stubAllFixtures()
        transport.stub("/api/v1/historical-price", data: Data(#"{"prices":[],"exchangeRates":{}}"#.utf8))
        let s = try await service().refresh()
        #expect(s.price != nil)
        #expect(s.price?.change24hPercent(in: .eur) == nil)
    }

    @Test func totalFailureThrowsFirstError() async {
        transport.failure = URLError(.timedOut)
        await #expect(throws: MempoolError.self) { try await service().refresh() }
        #expect(store.load() == nil)
    }

    @Test func loadLive() async throws {
        try transport.stubAllFixtures()
        let r = await service().load()
        #expect(r.source == .live)
        #expect(r.error == nil)
        #expect(r.snapshot?.fetchedAt == now)
    }

    @Test func loadFallsBackToCache() async throws {
        let cached = BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-3600))
        try store.save(cached)
        transport.stub("/api/v1/prices", status: 429, data: Data())  // everything else 404
        let r = await service().load()
        #expect(r.source == .cache)
        #expect(r.snapshot == cached)
        #expect(r.error == .rateLimited)
    }

    @Test func loadNoCacheNoNetwork() async {
        transport.failure = URLError(.notConnectedToInternet)
        let r = await service().load()
        #expect(r.source == .none)
        #expect(r.snapshot == nil)
        #expect(r.error != nil)
    }

    @Test func loadReusesVeryRecentCacheWithoutNetwork() async throws {
        let cached = BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-30))
        try store.save(cached)
        let r = await service().load(reuseIfYoungerThan: 60)
        #expect(r.source == .live)
        #expect(r.snapshot == cached)
        #expect(transport.requests.isEmpty)
    }

    @Test func loadIgnoresReuseWhenZero() async throws {
        try store.save(BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-30)))
        try transport.stubAllFixtures()
        let r = await service().load(reuseIfYoungerThan: 0)
        #expect(r.snapshot?.fetchedAt == now)
        #expect(transport.requests.count == 6)
    }

    @Test func partialFailureFillsFromFreshCache() async throws {
        let cached = BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-10 * 60))
        try store.save(cached)
        try transport.stubAllFixtures()
        transport.stub("/api/v1/prices", status: 500, data: Data())
        let r = await service().load()
        #expect(r.source == .live)
        #expect(r.error == .http(500))
        let s = try #require(r.snapshot)
        #expect(s.fetchedAt == now)
        #expect(s.price == cached.price)  // filled from cache, own updatedAt kept
        #expect(s.price?.updatedAt == cached.price?.updatedAt)
        #expect(s.blocks.count == 10 && s.blocks != cached.blocks)  // fresh
        #expect(s.fees != nil && s.fees != cached.fees)  // fresh fixture
        #expect(store.load() == s)
    }

    @Test func partialFailureFillsEverySectionThatFailed() async throws {
        let cached = BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-10 * 60))
        try store.save(cached)
        try transport.stub("/api/v1/prices", fixture: "prices")  // everything else 404
        let r = await service().load()
        #expect(r.source == .live)
        #expect(r.error == .http(404))
        let s = try #require(r.snapshot)
        #expect(s.price != nil && s.price != cached.price)
        #expect(s.blocks == cached.blocks)
        #expect(s.fees == cached.fees)
        #expect(s.mempool == cached.mempool)
        #expect(s.difficulty == cached.difficulty)
    }

    @Test func partialFailureIgnoresStaleCache() async throws {
        try store.save(BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-31 * 60)))
        try transport.stubAllFixtures()
        transport.stub("/api/v1/prices", status: 500, data: Data())
        let r = await service().load()
        #expect(r.source == .live)
        #expect(r.error == .http(500))
        #expect(r.snapshot?.price == nil)
        #expect(store.load()?.price == nil)
    }

    @Test func allSucceedReportsNoError() async throws {
        try store.save(BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(-10 * 60)))
        try transport.stubAllFixtures()
        let r = await service().load()
        #expect(r.source == .live)
        #expect(r.error == nil)
    }

    @Test func loadIgnoresCacheFromTheFuture() async throws {
        try store.save(BitcoinSnapshot.sample(fetchedAt: now.addingTimeInterval(3600)))
        try transport.stubAllFixtures()
        let r = await service().load(reuseIfYoungerThan: 60)
        #expect(r.snapshot?.fetchedAt == now)
        #expect(transport.requests.count == 6)
    }
}
