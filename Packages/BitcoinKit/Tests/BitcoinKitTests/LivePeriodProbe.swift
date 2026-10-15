import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BitcoinKit

/// Diagnostic: prints status, size, time and decode result for every chart endpoint × period.
/// Run with: BLOCKPULSE_PROBE=1 swift test --filter LivePeriodProbe
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BLOCKPULSE_PROBE"] == "1"))
struct LivePeriodProbe {
    @Test func probe() async throws {
        let base = ProcessInfo.processInfo.environment["BLOCKPULSE_BASE"] ?? "https://mempool.space"
        let periods = ["24h", "1w", "1m", "1y", "2y", "3y", "all"]
        var paths: [(String, (Data) throws -> Int)] = []
        for p in periods {
            paths.append(("/api/v1/statistics/\(p)", { try JSONDecoder().decode([MempoolStatistic].self, from: $0).count }))
            paths.append(("/api/v1/mining/blocks/sizes-weights/\(p)", { try JSONDecoder().decode(BlockSizes.self, from: $0).sizes.count }))
            paths.append(("/api/v1/mining/blocks/fee-rates/\(p)", { try JSONDecoder().decode([BlockFeeRates].self, from: $0).count }))
            paths.append(("/api/v1/mining/blocks/fees/\(p)", { try JSONDecoder().decode([BlockFees].self, from: $0).count }))
            paths.append(("/api/v1/mining/pools/\(p)", { try JSONDecoder().decode(PoolsResponse.self, from: $0).pools.count }))
            paths.append(("/api/v1/mining/hashrate/\(p)", { try JSONDecoder().decode(HashrateResponse.self, from: $0).hashrates.count }))
            paths.append(("/api/v1/mining/difficulty-adjustments/\(p)", { try JSONDecoder().decode([DifficultyAdjustmentEntry].self, from: $0).count }))
        }
        paths.append(("/api/v1/historical-price?currency=EUR", { try JSONDecoder().decode(HistoricalPriceResponse.self, from: $0).prices.count }))
        for (path, decode) in paths {
            var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: 60)
            req.setValue("Blockpulse/1.0", forHTTPHeaderField: "User-Agent")
            let start = Date()
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                var decoded = "-"
                do { decoded = "ok n=\(try decode(data))" } catch { decoded = "DECODE FAIL \(String(describing: error).prefix(300))" }
                print("PROBE \(path) status=\(status) bytes=\(data.count) ms=\(ms) \(decoded)")
            } catch {
                print("PROBE \(path) ERROR \(error.localizedDescription) ms=\(Int(Date().timeIntervalSince(start) * 1000))")
            }
        }
    }
}
