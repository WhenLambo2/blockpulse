import SwiftUI
import WidgetKit
import BitcoinKit

struct PriceWidget: Widget {
    let kind = "PriceWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CurrencyIntent.self, provider: SnapshotProvider<CurrencyIntent>()) { entry in
            PriceWidgetView(entry: entry)
        }
        .configurationDisplayName("Bitcoin Price")
        .description("BTC price, 24h change and sats per euro or dollar.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PriceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let price = entry.snapshot?.price {
                content(price)
            } else {
                NoDataView()
            }
        }
        .blockpulseBackground()
    }

    private func content(_ price: PriceInfo) -> some View {
        let currency = entry.currency
        return VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(title: "Bitcoin", systemImage: "bitcoinsign.circle.fill")
            Spacer(minLength: 0)
            Text(Format.price(price.price(in: currency), currency))
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            ChangeText(percent: price.change24hPercent(in: currency))
                .font(.caption.bold())
            if let sats = price.satsPerUnit(in: currency) {
                Text("\(Format.sats(sats)) per \(currency.symbol)1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if family == .systemMedium {
                Divider()
                HStack {
                    Text(Format.price(price.price(in: currency.other), currency.other))
                    Spacer()
                    Text("updated \(price.updatedAt, format: .dateTime.hour().minute())")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            StaleFooter(entry: entry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("Price small", as: .systemSmall) {
    PriceWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.stalePreview
    SnapshotEntry.emptyPreview
}

#Preview("Price medium", as: .systemMedium) {
    PriceWidget()
} timeline: {
    SnapshotEntry.preview()
    SnapshotEntry.preview(currency: .usd)
}
