import SwiftUI
import WidgetKit
import BitcoinKit

struct BlocksWidget: Widget {
    let kind = "BlocksWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CurrencyIntent.self, provider: SnapshotProvider<CurrencyIntent>()) { entry in
            BlocksWidgetView(entry: entry)
        }
        .configurationDisplayName("Blocks")
        .description("Latest block, recent blocks and the next difficulty adjustment.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BlocksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let tip = snapshot.blocks.first {
                if family == .systemMedium {
                    HStack(alignment: .top, spacing: 12) {
                        tipColumn(tip)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Recent").font(.caption2.bold()).foregroundStyle(.secondary)
                            ForEach(Array(snapshot.blocks.dropFirst().prefix(3))) { BlockRow(block: $0) }
                            Spacer(minLength: 0)
                            if let difficulty = snapshot.difficulty {
                                DifficultyLine(difficulty: difficulty)
                            }
                        }
                    }
                } else {
                    tipColumn(tip)
                }
            } else {
                NoDataView()
            }
        }
        .blockpulseBackground()
    }

    private func tipColumn(_ tip: BlockSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(title: "Latest block", systemImage: "cube.fill")
            Spacer(minLength: 0)
            Text(Format.blockHeight(tip.height))
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("\(tip.timestamp, style: .relative) ago")
                .font(.caption)
                .lineLimit(1)
            if let pool = tip.poolName {
                Text(pool).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            StaleFooter(entry: entry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct DifficultyLine: View {
    let difficulty: DifficultyAdjustment

    var body: some View {
        Text("Difficulty \(Format.signedPercent(difficulty.difficultyChange)) in \(difficulty.retargetDate, style: .relative)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

#Preview("Blocks small", as: .systemSmall) {
    BlocksWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.stalePreview
    SnapshotEntry.emptyPreview
}

#Preview("Blocks medium", as: .systemMedium) {
    BlocksWidget()
} timeline: {
    SnapshotEntry.preview()
}
