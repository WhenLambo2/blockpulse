import SwiftUI
import WidgetKit
import BitcoinKit

struct DashboardWidget: Widget {
    let kind = "DashboardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CurrencyIntent.self, provider: SnapshotProvider<CurrencyIntent>()) { entry in
            DashboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Bitcoin Dashboard")
        .description("Price, fees, mempool, difficulty and the latest blocks.")
        .supportedFamilies([.systemLarge])
    }
}

struct DashboardWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.isEmpty {
                content(snapshot)
            } else {
                NoDataView()
            }
        }
        .blockpulseBackground()
    }

    private func content(_ snapshot: BitcoinSnapshot) -> some View {
        let currency = entry.currency
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(title: "Blockpulse", systemImage: "bitcoinsign.circle.fill")
                Spacer()
                StaleFooter(entry: entry)
            }
            if let price = snapshot.price {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.price(price.price(in: currency), currency))
                        .font(.system(.title, design: .rounded).bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    ChangeText(percent: price.change24hPercent(in: currency)).font(.subheadline.bold())
                    Spacer()
                    if let sats = price.satsPerUnit(in: currency) {
                        Text("\(Format.sats(sats))/\(currency.symbol)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                if let fees = snapshot.fees {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fees (sat/vB)").font(.caption2.bold()).foregroundStyle(.secondary)
                        FeeGrid(fees: fees)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let mempool = snapshot.mempool {
                        Text("Mempool").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text("\(Format.compactCount(mempool.count)) tx · \(Format.vMB(mempool.vsize))").font(.caption)
                        Text("~\(mempool.blocksToClear) blocks to clear").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let difficulty = snapshot.difficulty {
                        Text("Difficulty").font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 4)
                        Text("\(Format.signedPercent(difficulty.difficultyChange)) · \(difficulty.remainingBlocks) blocks").font(.caption)
                        Text(difficulty.retargetDate, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            if let tip = snapshot.blocks.first {
                HStack {
                    Text("Latest blocks").font(.caption2.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(tip.timestamp, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(snapshot.blocks.prefix(5))) { block in
                HStack(spacing: 6) {
                    BlockRow(block: block)
                    Text(block.poolName ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 70, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Dashboard", as: .systemLarge) {
    DashboardWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.stalePreview
    SnapshotEntry.emptyPreview
}
