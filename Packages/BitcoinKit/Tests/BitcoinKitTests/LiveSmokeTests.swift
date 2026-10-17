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

    /// Every Explore endpoint against real data: the genesis block, a famous early transaction, a busy address.
    @Test func exploreEndpoints() async throws {
        let c = Self.client()
        let tip = try await c.tipHeight()
        #expect(tip > 900_000)
        let genesis = try await c.blockHash(height: 0)
        #expect(genesis == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
        let block = try await c.block(genesis)
        #expect(block.height == 0)
        let latest = try await c.block(c.blockHash(height: tip))
        #expect(latest.extras?.pool != nil)
        let txs = try await c.blockTransactions(latest.id, start: 0)
        #expect(txs.count == min(25, latest.txCount))
        #expect(txs.first?.isCoinbase == true)
        let older = try await c.blocks(endingAt: tip - 15)
        #expect(older.first?.height == tip - 15)
        #expect(try await c.blockAt(timestamp: 1_231_006_505).height == 0)

        // Block 170: the first payment, from Satoshi to Hal Finney.
        let first = "f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16"
        let tx = try await c.transaction(first)
        #expect(tx.status.blockHeight == 170)
        #expect(try await c.outspends(first).count == tx.vout.count)
        _ = try await c.cpfp(first)
        _ = try await c.rbf(first)

        let address = "bc1qm34lsc65zpw79lxes69zkqmk6ee3ewf0j77s3h"
        let info = try await c.address(address)
        #expect(info.txCount > 0)
        let page = try await c.addressTransactions(address)
        #expect(!page.isEmpty)
        if let last = page.last(where: { $0.status.confirmed }) {
            _ = try await c.addressTransactions(address, after: last.txid)
        }
        #expect(try await c.addressPrefix("bc1qm34lsc65").contains(address))

        let backlog = try await c.mempoolBacklog()
        #expect(backlog.count > 0 && !backlog.feeHistogram.isEmpty)
        #expect(!(try await c.recentMempoolTransactions()).isEmpty)
    }

    @Test func pulseExtras() async {
        let extras = await PulseExtras.load(Self.client())
        #expect(!extras.projectedBlocks.isEmpty)
        #expect(extras.inflow != nil)
    }
}
