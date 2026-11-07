import SwiftUI
import Charts
import BitcoinKit

/// Under the block strip: how big the mempool is, how it splits by fee rate, what is coming in, and
/// the latest transactions entering it, like the mempool.space dashboard.
struct MempoolOverview: View {
    let model: ExploreModel

    /// What blocks clear on average: 4 M weight units (1 M vbytes) every 10 minutes.
    static let blockCapacity: Double = 1_000_000 / 600

    var body: some View {
        if let backlog = model.backlog { summary(backlog) }
        if model.inflow.count > 1 { incoming(model.inflow) }
        if !model.recent.isEmpty { latest(model.recent) }
    }

    private func summary(_ backlog: MempoolBacklog) -> some View {
        let bands = backlog.bands()
        let total = max(bands.reduce(0) { $0 + $1.vsize }, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Mempool")
            HStack(alignment: .top, spacing: 8) {
                stat(Format.grouped(Double(backlog.count)), "unconfirmed tx")
                stat(Format.vMB(backlog.vsize), "≈ \(Format.grouped(Double(backlog.blocksToClear))) blocks")
                if let minimumFee = model.minimumFee {
                    stat(Format.feeRateNumber(minimumFee), "sat/vB to get in")
                }
            }
            if !backlog.feeHistogram.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { proxy in
                        let gaps = CGFloat(bands.count - 1) * 2
                        HStack(spacing: 2) {
                            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Theme.orange.opacity(0.3 + 0.7 * Double(index) / Double(max(bands.count - 1, 1))))
                                    .frame(width: max(0, (proxy.size.width - gaps) * band.vsize / total))
                            }
                        }
                    }
                    .frame(height: 12)
                    HStack {
                        ForEach(bands) { band in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(band.label).font(.number(.caption2, weight: .semibold))
                                Text(Format.vMB(Int(band.vsize))).font(.number(.caption2, weight: .regular)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text("Mempool size by fee rate in sat/vB, cheapest first.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mempool size by fee rate")
                .accessibilityValue(bands.map { "\($0.label) sat per vbyte: \(Format.vMB(Int($0.vsize)))" }.joined(separator: ", "))
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.number(.headline, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func incoming(_ stats: [MempoolStatistic]) -> some View {
        let now = stats.last?.vbytesPerSecond ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Incoming")
            HStack(alignment: .firstTextBaseline) {
                Text("\(Format.grouped(now)) vB/s").font(.number(.headline, weight: .bold))
                Spacer()
                Text("Blocks clear ~\(Format.grouped(Self.blockCapacity)) vB/s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(stats, id: \.added) { stat in
                    AreaMark(x: .value("Time", stat.date), y: .value("vB/s", stat.vbytesPerSecond))
                        .foregroundStyle(Theme.orange.opacity(0.18))
                    LineMark(x: .value("Time", stat.date), y: .value("vB/s", stat.vbytesPerSecond))
                        .foregroundStyle(Theme.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                RuleMark(y: .value("Block capacity", Self.blockCapacity))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 64)
            HStack {
                Text("2 h ago")
                Spacer()
                Text("now")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Incoming transactions")
        .accessibilityValue("\(Format.grouped(now)) vbytes per second; blocks clear about \(Format.grouped(Self.blockCapacity))")
    }

    private func latest(_ txs: [RecentMempoolTx]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Latest transactions")
                Spacer()
                Circle().fill(Theme.up).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("Live").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)
            ForEach(txs) { tx in
                RouteRow(route: .transaction(tx.txid, output: nil)) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.short(tx.txid, head: 10, tail: 6))
                                .font(.system(.footnote, design: .monospaced))
                            Text(Format.feeRate(tx.feeRate)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Text(Format.btc(tx.value)).font(.number(.subheadline, weight: .medium)).lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
                if tx.id != txs.last?.id { Divider().overlay(Theme.border) }
            }
        }
        .card()
        .animation(.snappy, value: txs.map(\.txid))
    }
}

/// Every mined block, newest first, loading older ones as the list scrolls.
struct LatestBlocksView: View {
    let model: ExploreModel

    var body: some View {
        ExplorePage(title: "Blocks", refresh: { await model.refresh() }) {
            if model.blocks.isEmpty {
                if let error = model.error {
                    ExploreMessage(title: "Blocks didn't load", message: error.exploreMessage,
                                   systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView().tint(Theme.orange).padding(.top, 80)
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.blocks) { block in
                        RouteRow(route: .block(.hash(block.id))) { LatestBlockRow(block: block) }
                            .onAppear {
                                if block.id == model.blocks.last?.id { Task { await model.loadMore() } }
                            }
                        if block.id != model.blocks.last?.id { Divider().overlay(Theme.border) }
                    }
                    if model.isLoadingMore {
                        ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(.top, 10)
                    } else if model.loadMoreFailed {
                        Button { Task { await model.loadMore() } } label: {
                            Label("Couldn't load more · Retry", systemImage: "arrow.clockwise")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10)
                        }
                    }
                }
                .card()
            }
        }
    }
}
