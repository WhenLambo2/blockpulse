import Foundation
import Observation
import BitcoinKit

/// Pending and mined blocks for the Explore tab, refreshed every minute while it is on screen.
@MainActor
@Observable
final class ExploreModel {
    static let liveInterval: Duration = .seconds(60)

    private(set) var projected: [ProjectedBlock] = []
    /// Newest first; grows as the list is scrolled.
    private(set) var blocks: [Block] = []
    private(set) var error: MempoolError?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false

    var tip: Int? { blocks.first?.height }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let client = Explore.client()
        async let pending = try? client.projectedBlocks()
        do {
            let newest = try await client.recentBlocks()
            let oldestNew = newest.last?.height ?? 0
            blocks = newest + blocks.filter { $0.height < oldestNew }
            error = nil
        } catch {
            self.error = Explore.failure(error)
        }
        if let pending = await pending { projected = pending }
    }

    /// The next 15 older blocks, when the end of the list comes into view.
    func loadMore() async {
        guard !isLoadingMore, let last = blocks.last, last.height > 0 else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let older = try? await Explore.client().blocks(endingAt: last.height - 1) else { return }
        blocks += older.filter { $0.height < last.height }
    }

    func reset() {
        projected = []
        blocks = []
        error = nil
    }

    func runLiveUpdates() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: DemoMode.liveInterval ?? Self.liveInterval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}
