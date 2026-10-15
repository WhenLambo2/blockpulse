import SwiftUI
import WidgetKit
import BitcoinKit

enum Theme {
    static let accent = Color(red: 0.969, green: 0.576, blue: 0.102) // #F7931A
    static let up = Color.green
    static let down = Color.red
}

/// Standard background for Home Screen / StandBy widgets (removed automatically in tinted/clear modes).
struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(.fill.tertiary, for: .widget)
    }
}

extension View {
    func blockpulseBackground() -> some View { modifier(WidgetBackground()) }
}

struct WidgetHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.bold())
            .foregroundStyle(Theme.accent)
            .widgetAccentable()
            .lineLimit(1)
    }
}

struct StaleFooter: View {
    let entry: SnapshotEntry

    var body: some View {
        if entry.isStale, let snapshot = entry.snapshot {
            Label {
                Text("as of \(snapshot.fetchedAt, format: .dateTime.hour().minute())")
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

struct NoDataView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "bitcoinsign.circle")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .widgetAccentable()
            Text("No data yet").font(.caption.bold())
            Text("Open Blockpulse").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChangeText: View {
    let percent: Double?

    var body: some View {
        if let percent {
            Text(Format.signedPercent(percent))
                .foregroundStyle(percent >= 0 ? Theme.up : Theme.down)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

struct BlockRow: View {
    let block: BlockSummary

    var body: some View {
        HStack(spacing: 6) {
            Text(Format.blockHeight(block.height)).monospacedDigit().bold()
            Spacer(minLength: 4)
            Text("\(Format.compactCount(block.txCount)) tx").foregroundStyle(.secondary)
            if let fee = block.medianFee {
                Text("~\(Format.feeRateNumber(fee))").foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }
}

struct FeeGrid: View {
    let fees: RecommendedFees

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            row("Fast", fees.fastestFee)
            row("30 min", fees.halfHourFee)
            row("1 hour", fees.hourFee)
            row("Economy", fees.economyFee)
        }
        .font(.caption)
    }

    private func row(_ label: String, _ value: Double) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(Format.feeRateNumber(value)).bold().monospacedDigit()
        }
    }
}
