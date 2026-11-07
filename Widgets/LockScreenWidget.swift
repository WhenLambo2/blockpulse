import SwiftUI
import WidgetKit
import BitcoinKit

/// Price on the Lock Screen: circular, rectangular (price and change, height and fee, last block) and inline.
struct LockScreenWidget: Widget {
    let kind = "LockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CurrencyIntent.self, provider: SnapshotProvider<CurrencyIntent>()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Bitcoin price")
        .description("Price, block height and fastest fee on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Fastest fee in a circle.
struct LockFeeWidget: Widget {
    let kind = "LockFeeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LockFeeIntent.self, provider: SnapshotProvider<LockFeeIntent>()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Fastest fee")
        .description("The fee for the next block, in sat/vB.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Block height in a circle.
struct LockHeightWidget: Widget {
    let kind = "LockHeightWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LockHeightIntent.self, provider: SnapshotProvider<LockHeightIntent>()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Block height")
        .description("The latest block on the chain.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Icon and title with a tight gap, for the small third line of the rectangular widget.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
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
                    Text("s/vB").font(.system(size: 8))
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

    /// Line 1: price with the 24h change next to it. Line 2: height and fastest fee.
    /// Line 3: time since the last block, or "as of" once the data is stale.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let snapshot = entry.snapshot {
                priceRow(snapshot)
                Text(detailLine(snapshot))
                    .font(.caption)
                    .lineLimit(1)
                if entry.isStale {
                    Text("as of \(snapshot.fetchedAt, format: .dateTime.hour().minute())").font(.caption2)
                } else if let lastBlock = snapshot.lastBlockDate {
                    Label(Format.minutesAgo(lastBlock, now: entry.date), systemImage: "cube")
                        .labelStyle(CompactLabelStyle())
                        .font(.caption2)
                        .lineLimit(1)
                }
            } else {
                Text("Blockpulse").font(.headline)
                Text("Open the app to load data").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "₿ €73,541 ▲ 0.39%". Long values first drop a decimal from the change, then shrink;
    /// the price itself is never truncated.
    @ViewBuilder private func priceRow(_ snapshot: BitcoinSnapshot) -> some View {
        let price = priceLine(snapshot)
        if let change = snapshot.price?.change24hPercent(in: entry.currency) {
            ViewThatFits(in: .horizontal) {
                priceAndChange(price, Format.arrowPercent(change, decimals: 2))
                priceAndChange(price, Format.arrowPercent(change, decimals: 1))
                priceAndChange(price, Format.arrowPercent(change, decimals: 1))
                    .minimumScaleFactor(0.75)
            }
        } else {
            Text(price)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
        }
    }

    private func priceAndChange(_ price: String, _ change: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(price)
                .font(.headline)
                .widgetAccentable()
                .layoutPriority(1)
            Text(change)
                .font(.subheadline)
        }
        .lineLimit(1)
    }

    /// "₿ €73,984" (or "₿ —"). Kept out of the view builder so `Text` gets a plain String.
    private func priceLine(_ snapshot: BitcoinSnapshot) -> String {
        guard let price = snapshot.price else { return "₿ —" }
        return "₿ " + Format.price(price.price(in: entry.currency), entry.currency)
    }

    /// "#971,150 · 2 s/vB", omitting missing parts.
    private func detailLine(_ snapshot: BitcoinSnapshot) -> String {
        var parts: [String] = []
        if let height = snapshot.tipHeight { parts.append(Format.blockHeight(height)) }
        if let fees = snapshot.fees { parts.append(Format.feeRateShort(fees.fastestFee)) }
        return parts.joined(separator: " · ")
    }

    private var inline: some View {
        Text(entry.snapshot.map { Format.inline($0, entry.currency) } ?? "₿ —")
    }
}

#Preview("Circular price", as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    SnapshotEntry.preview(metric: .price)
}

#Preview("Circular fee", as: .accessoryCircular) {
    LockFeeWidget()
} timeline: {
    SnapshotEntry.preview(metric: .fee)
}

#Preview("Circular height", as: .accessoryCircular) {
    LockHeightWidget()
} timeline: {
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
