import Foundation
import Testing
@testable import BitcoinKit

/// Hits the real API (mempool.space, or BLOCKPULSE_BASE). Run with: BLOCKPULSE_LIVE=1 swift test --filter LiveSmokeTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BLOCKPULSE_LIVE"] == "1"), .serialized)
struct LiveSmokeTests {
    static func client() -> MempoolClient {
        let base = ProcessInfo.processInfo.environment["BLOCKPULSE_BASE"].flatMap(AppSettings.validatedBaseURL)
        return MempoolClient(baseURL: base ?? MempoolClient.defaultBaseURL)
    }

    /// Every chart in every period it offers (live-only charts once).
    static let chartPeriods: [(ChartID, ChartPeriod?)] = ChartID.allCases.flatMap { id in
        id.periods.isEmpty ? [(id, nil)] : id.periods.map { (id, Optional($0)) }
    }

    @Test func fullSnapshot() async throws {
        let snapshot = try await SnapshotService(client: Self.client(), store: nil).refresh()
        #expect(snapshot.price != nil)
        #expect(snapshot.price?.change24hPercent(in: .eur) != nil)
        #expect((snapshot.tipHeight ?? 0) > 900_000)
        #expect(snapshot.fees != nil)
        #expect(snapshot.mempool != nil)
        #expect(snapshot.difficulty != nil)
    }

    @Test func connectionCheck() async {
        let check = await Self.client().checkConnection()
        #expect(check.succeeded, "\(check.summary)")
    }

    /// Shared so the 1.5 MB price history downloads once.
    static let loader = ChartLoader(client: client())

    @Test(arguments: chartPeriods)
    func chartLoads(_ id: ChartID, _ period: ChartPeriod?) async throws {
        let result = try await Self.loader.load(id, period: period, currency: .eur)
        let label = "\(id) \(period?.label ?? "live")"
        #expect(result.headline != "—", "\(label)")
        #expect(!result.series.isEmpty || !result.bars.isEmpty || !result.blocks.isEmpty, "\(label)")
        #expect(result.series.first.map { !$0.points.isEmpty } ?? true, "\(label)")
    }

    @Test func pulseExtras() async {
        let extras = await PulseExtras.load(Self.client())
        #expect(!extras.projectedBlocks.isEmpty)
        #expect(extras.inflow != nil)
    }
}
