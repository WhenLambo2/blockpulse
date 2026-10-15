import SwiftUI
import WidgetKit
import BitcoinKit

struct FeesWidget: Widget {
    let kind = "FeesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CurrencyIntent.self, provider: SnapshotProvider<CurrencyIntent>()) { entry in
            FeesWidgetView(entry: entry)
        }
        .configurationDisplayName("Fees & Mempool")
        .description("Recommended fees in sat/vB and mempool size.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FeesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let fees = snapshot.fees {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetHeader(title: "Fees", systemImage: "gauge.with.dots.needle.33percent")
                        Spacer(minLength: 0)
                        FeeGrid(fees: fees)
                        Text("sat/vB").font(.caption2).foregroundStyle(.secondary)
                        StaleFooter(entry: entry)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    if family == .systemMedium, let mempool = snapshot.mempool {
                        MempoolColumn(mempool: mempool)
                    }
                }
            } else {
                NoDataView()
            }
        }
        .blockpulseBackground()
    }
}

struct MempoolColumn: View {
    let mempool: MempoolStats

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(title: "Mempool", systemImage: "tray.full.fill")
            Spacer(minLength: 0)
            Text("\(Format.compactCount(mempool.count)) tx")
                .font(.system(.title3, design: .rounded).bold())
                .monospacedDigit()
            Text(Format.vMB(mempool.vsize)).font(.caption)
            Text("~\(mempool.blocksToClear) blocks to clear")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("Fees small", as: .systemSmall) {
    FeesWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.emptyPreview
}

#Preview("Fees medium", as: .systemMedium) {
    FeesWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.stalePreview
}
