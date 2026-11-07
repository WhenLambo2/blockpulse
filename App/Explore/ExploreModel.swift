import Foundation
import Observation
import BitcoinKit

/// Everything the Explore tab shows under the search bar: pending and mined blocks, the state of the
/// mempool and the latest transactions entering it. Refreshes only while the tab's overview is on screen.
@MainActor
@Observable
final class ExploreModel {
    /// Blocks, mempool size and inflow.
    static let liveInterval: Duration = .seconds(60)
    /// The latest transactions list.
    static let recentInterval: Duration = .seconds(10)

    private(set) var projected: [ProjectedBlock] = []
    /// Newest first; grows as the block list is scrolled.
    private(set) var blocks: [Block] = []
    private(set) var backlog: MempoolBacklog?
    /// Last two hours, oldest first.
    private(set) var inflow: [MempoolStatistic] = []
    /// The lowest fee rate the mempool still accepts.
    private(set) var minimumFee: Double?
    private(set) var recent: [RecentMempoolTx] = []
    private(set) var error: MempoolError?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false

    /// Bumped by `reset()`, so answers from the previous data source are dropped.
    private var generation = 0
    private var lastFullRefresh: Date?

    var tip: Int? { blocks.first?.height }

    func refresh() async {
        guard !isLoading else { return }
        let started = generation
        isLoading = true
        defer { if started == generation { isLoading = false } }
        let client = Explore.client()
        async let pending = try? client.projectedBlocks()
        async let backlog = try? client.mempoolBacklog()
        async let stats = try? client.mempoolStatistics(.twoHours)
        async let fees = try? client.recommendedFees()
        async let recent = try? client.recentMempoolTransactions()
        do {
            let newest = try await client.recentBlocks()
            guard started == generation else { return }
            let oldestNew = newest.last?.height ?? 0
            blocks = newest + blocks.filter { $0.height < oldestNew }
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard started == generation else { return }
            self.error = Explore.failure(error)
        }
        let results = await (pending, backlog, stats, fees, recent)
        guard started == generation else { return }
        if let value = results.0 { projected = value }
        if let value = results.1 { self.backlog = value }
        if let value = results.2 { inflow = value.sorted { $0.added < $1.added } }
        if let value = results.3 { minimumFee = value.minimumFee }
        if let value = results.4 { self.recent = value }
        lastFullRefresh = Date()
    }

    func refreshRecent() async {
        let started = generation
        guard let value = try? await Explore.client().recentMempoolTransactions(), started == generation else { return }
        recent = value
    }

    /// The next 15 older blocks, when the end of the list comes into view or Retry is tapped.
    func loadMore() async {
        guard !isLoadingMore, let last = blocks.last, last.height > 0 else { return }
        let started = generation
        isLoadingMore = true
        loadMoreFailed = false
        defer { if started == generation { isLoadingMore = false } }
        do {
            let older = try await Explore.client().blocks(endingAt: last.height - 1)
            guard started == generation else { return }
            blocks += older.filter { $0.height < last.height }
        } catch is CancellationError {
            return
        } catch {
            if started == generation { loadMoreFailed = true }
        }
    }

    func reset() {
        generation += 1
        isLoading = false
        isLoadingMore = false
        loadMoreFailed = false
        projected = []
        blocks = []
        backlog = nil
        inflow = []
        minimumFee = nil
        recent = []
        error = nil
        lastFullRefresh = nil
    }

    /// Runs while the overview is on screen: the transaction list every 10 seconds, the rest every
    /// minute. Catches up at once after a detail page was open for a while.
    func runLiveUpdates() async {
        if let last = lastFullRefresh, Date().timeIntervalSince(last) > 60 { await refresh() }
        let fastest = DemoMode.liveInterval ?? Self.recentInterval
        while !Task.isCancelled {
            try? await Task.sleep(for: fastest)
            guard !Task.isCancelled else { return }
            let due = DemoMode.liveInterval != nil || lastFullRefresh.map { Date().timeIntervalSince($0) >= 59 } ?? true
            if due { await refresh() } else { await refreshRecent() }
        }
    }
}
