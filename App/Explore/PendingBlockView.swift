import SwiftUI
import BitcoinKit

/// One projected block from the mempool: fee range, fees, size and how fee rates spread through it.
struct PendingBlockView: View {
    @State private var index: Int

    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @State private var projected: [ProjectedBlock] = []
    @State private var price: PriceInfo?
    @State private var error: MempoolError?
    @State private var loaded = false

    private static let pollInterval: Duration = .seconds(30)

    init(index: Int) { _index = State(initialValue: index) }

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }
    private var title: String { index == 0 ? "Next block" : "Pending block \(index + 1)" }

    var body: some View {
        ExplorePage(title: title, refresh: load) {
            if index < projected.count {
                let block = projected[index]
                header(block)
                stats(block)
                spread(block)
                Text("Projection from the mempool. The real block may differ.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                ExploreMessage(title: "Couldn't load the mempool", message: error.exploreMessage,
                               systemImage: "exclamationmark.triangle")
            } else if loaded {
                ExploreMessage(title: "This block has cleared",
                               message: "The mempool is smaller now. Go back to see the current pending blocks.",
                               systemImage: "checkmark.circle")
            } else {
                ProgressView().tint(Theme.orange).padding(.top, 80)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { index -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                    .accessibilityLabel("Earlier block")
                Button { index += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(index + 1 >= projected.count)
                    .accessibilityLabel("Later block")
            }
        }
        .task {
            if price == nil { price = Explore.cachedPrice() }
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private func load() async {
        do {
            projected = try await Explore.client().projectedBlocks()
            error = nil
        } catch is CancellationError {
            return
        } catch {
            if projected.isEmpty { self.error = Explore.failure(error) }
        }
        loaded = true
    }

    private func header(_ block: ProjectedBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            Text("~\(Format.feeRate(block.medianFee))").font(.number(.largeTitle, weight: .bold))
            Text("Expected in ~\(PendingPosition.minutes(index: index)) min · \(Format.grouped(Double(block.nTx))) transactions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func stats(_ block: ProjectedBlock) -> some View {
        let fees = Int(block.totalFees.rounded())
        return VStack(spacing: 10) {
            StatRow(label: "Fee range", value: "\(Format.feeRateNumber(block.minFee))–\(Format.feeRateNumber(block.maxFee)) sat/vB")
            StatRow(label: "Median fee", value: Format.feeRate(block.medianFee))
            StatRow(label: "Total fees", value: Format.btc(fees) + (price.map { " · " + Format.fiat(fees, price: $0.price(in: currency), currency) } ?? ""))
            StatRow(label: "Size", value: String(format: "%.2f MvB", block.blockVSize / 1_000_000))
        }
        .card()
    }

    /// The fee rates mempool.space reports through the block (lowest to highest), on a log scale.
    private func spread(_ block: ProjectedBlock) -> some View {
        let rates = block.feeRange
        let top = log((rates.max() ?? 1) + 1)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Fee rates in this block")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(rates.enumerated()), id: \.offset) { _, rate in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.orange.opacity(Theme.feeIntensity(rate)))
                            .frame(height: max(6, 80 * log(rate + 1) / max(top, 0.0001)))
                        Text(Format.feeRateNumber(rate)).font(.number(.caption2, weight: .regular)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
            Text("sat/vB, from the cheapest to the most expensive transactions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
