import SwiftUI
import WidgetKit
import BitcoinKit

struct LockScreenWidget: Widget {
    let kind = "LockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LockScreenIntent.self, provider: SnapshotProvider<LockScreenIntent>()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Blockpulse")
        .description("Price, block height or fastest fee on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        content.containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: EmptyView()
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: circularIcon).font(.caption2)
                Text(circularValue)
                    .font(.system(.body, design: .rounded).bold())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                if entry.metric == .fee {
                    Text("sat/vB").font(.system(size: 8))
                }
            }
            .padding(2)
        }
    }

    private var circularIcon: String {
        switch entry.metric {
        case .price: "bitcoinsign"
        case .fee: "gauge.with.dots.needle.33percent"
        case .height: "cube"
        }
    }

    private var circularValue: String {
        guard let snapshot = entry.snapshot else { return "—" }
        switch entry.metric {
        case .price: return snapshot.price.map { Format.compactPrice($0.price(in: entry.currency), entry.currency) } ?? "—"
        case .fee: return snapshot.fees.map { Format.feeRateNumber($0.fastestFee) } ?? "—"
        case .height: return snapshot.tipHeight.map { String($0) } ?? "—"
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let snapshot = entry.snapshot {
                Text(priceLine(snapshot))
                    .font(.headline)
                    .widgetAccentable()
                    .lineLimit(1)
                Text(detailLine(snapshot))
                    .font(.caption)
                    .lineLimit(1)
                if entry.isStale {
                    Text("as of \(snapshot.fetchedAt, format: .dateTime.hour().minute())").font(.caption2)
                } else if let change = snapshot.price?.change24hPercent(in: entry.currency) {
                    Text("24h \(Format.signedPercent(change))").font(.caption2)
                }
            } else {
                Text("Blockpulse").font(.headline)
                Text("Open the app to load data").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "₿ €73,984" (or "₿ —"). Kept out of the view builder so `Text` gets a plain String.
    private func priceLine(_ snapshot: BitcoinSnapshot) -> String {
        guard let price = snapshot.price else { return "₿ —" }
        return "₿ " + Format.price(price.price(in: entry.currency), entry.currency)
    }

    /// "#971,150 · 2 sat/vB", omitting missing parts.
    private func detailLine(_ snapshot: BitcoinSnapshot) -> String {
        var parts: [String] = []
        if let height = snapshot.tipHeight { parts.append(Format.blockHeight(height)) }
        if let fees = snapshot.fees { parts.append(Format.feeRate(fees.fastestFee)) }
        return parts.joined(separator: " · ")
    }

    private var inline: some View {
        Text(entry.snapshot.map { Format.inline($0, entry.currency) } ?? "₿ —")
    }
}

#Preview("Circular", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    SnapshotEntry.preview(metric: .price)
    SnapshotEntry.preview(metric: .fee)
    SnapshotEntry.preview(metric: .height)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.stalePreview
    SnapshotEntry.emptyPreview
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenWidget()
} timeline: {
    SnapshotEntry.preview()
}
