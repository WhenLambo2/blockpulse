import Foundation

public struct SnapshotResult: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case live, cache, none }

    public let snapshot: BitcoinSnapshot?
    public let source: Source
    public let error: MempoolError?

    public init(snapshot: BitcoinSnapshot?, source: Source, error: MempoolError?) {
        self.snapshot = snapshot; self.source = source; self.error = error
    }
}

public struct SnapshotService: Sendable {
    private let client: MempoolClient
    private let store: SnapshotStore?
    private let now: @Sendable () -> Date

    public init(client: MempoolClient, store: SnapshotStore?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.store = store; self.now = now
    }

    /// Fetches all sections concurrently and saves the result. A section that fails is
    /// filled from the cached snapshot when that cache is not stale, otherwise left nil.
    /// Throws only when every section failed (nothing is saved then).
    public func refresh() async throws -> BitcoinSnapshot {
        try await fetch().snapshot
    }

    /// Widget/app entry point: live data, else cached data, else nothing — never throws.
    /// A live result carries the first section failure as `error` when the refresh was partial.
    public func load(reuseIfYoungerThan reuseWindow: TimeInterval = RefreshPolicy.reuseWindow) async -> SnapshotResult {
        if reuseWindow > 0, let cached = store?.load() {
            let age = now().timeIntervalSince(cached.fetchedAt)
            if age >= 0, age < reuseWindow {
                return SnapshotResult(snapshot: cached, source: .live, error: nil)
            }
        }
        do {
            let (snapshot, partialFailure) = try await fetch()
            return SnapshotResult(snapshot: snapshot, source: .live, error: partialFailure)
        } catch {
            let failure = error as? MempoolError ?? .network(error.localizedDescription)
            if let cached = store?.load() {
                return SnapshotResult(snapshot: cached, source: .cache, error: failure)
            }
            return SnapshotResult(snapshot: nil, source: .none, error: failure)
        }
    }

    private func fetch() async throws -> (snapshot: BitcoinSnapshot, partialFailure: MempoolError?) {
        let started = now()
        let client = self.client
        async let prices = attempt { try await client.prices() }
        async let history = attempt { try await client.historicalPrice(at: started.addingTimeInterval(-86_400)) }
        async let blocks = attempt { try await client.recentBlocks() }
        async let fees = attempt { try await client.recommendedFees() }
        async let mempool = attempt { try await client.mempool() }
        async let difficulty = attempt { try await client.difficultyAdjustment() }
        let (p, h, b, f, m, d) = await (prices, history, blocks, fees, mempool, difficulty)

        let baseline = (try? h.get())?.prices.first
        let price = (try? p.get()).map {
            PriceInfo(eur: $0.eur, usd: $0.usd, eur24hAgo: baseline?.eur, usd24hAgo: baseline?.usd, updatedAt: $0.date)
        }
        let summaries = ((try? b.get()) ?? [])
            .sorted { $0.height > $1.height }
            .prefix(10)
            .map(BlockSummary.init(block:))
        var snapshot = BitcoinSnapshot(
            fetchedAt: started,
            price: price,
            blocks: Array(summaries),
            fees: try? f.get(),
            mempool: try? m.get(),
            difficulty: try? d.get()
        )
        let failures = [p.failure, b.failure, f.failure, m.failure, d.failure, h.failure].compactMap { $0 }
        if snapshot.isEmpty {
            throw failures.first ?? MempoolError.network("No data")
        }
        if !failures.isEmpty, let previous = store?.load() {
            let age = started.timeIntervalSince(previous.fetchedAt)
            if age >= 0, age <= RefreshPolicy.staleThreshold {
                if p.failure != nil { snapshot.price = previous.price }  // keeps its own updatedAt
                if b.failure != nil { snapshot.blocks = previous.blocks }
                if f.failure != nil { snapshot.fees = previous.fees }
                if m.failure != nil { snapshot.mempool = previous.mempool }
                if d.failure != nil { snapshot.difficulty = previous.difficulty }
            }
        }
        try? store?.save(snapshot)
        return (snapshot, failures.first)
    }

    private func attempt<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, MempoolError> {
        do { return .success(try await operation()) }
        catch let error as MempoolError { return .failure(error) }
        catch { return .failure(.network(error.localizedDescription)) }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
