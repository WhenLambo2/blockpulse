import SwiftUI
import BitcoinKit

/// One mined block: who mined it, fees and size, then its transactions 25 at a time.
/// The arrows in the top bar walk to the previous and next block.
struct BlockView: View {
    @State private var ref: BlockRef
    /// The searched time, for "mined at or before" (date and timestamp searches). Cleared once the
    /// arrows move to another block.
    @State private var searchedTime: Int? = nil

    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @State private var block: Block?
    @State private var tip: Int?
    @State private var txs: [BitcoinTx] = []
    @State private var loadingTxs = false
    @State private var price: PriceInfo?
    @State private var error: MempoolError?
    /// The ref the page shows, so coming back to it doesn't reload and drop the extra pages.
    @State private var loadedRef: BlockRef?
    @State private var loading = false

    init(ref: BlockRef) {
        _ref = State(initialValue: ref)
        if case .timestamp(let t) = ref { _searchedTime = State(initialValue: t) }
    }

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }

    /// Where the arrows count from: the block being loaded, else the one on screen.
    private var currentHeight: Int? {
        if case .height(let h) = ref { return h }
        return block?.height
    }

    private func step(_ delta: Int) {
        guard let height = currentHeight else { return }
        searchedTime = nil
        ref = .height(height + delta)
    }

    var body: some View {
        ExplorePage(title: block.map { "Block \(Format.grouped(Double($0.height)))" } ?? "Block", refresh: load) {
            if let block {
                Group {
                    header(block)
                    stats(block)
                    transactions(block)
                }
                .opacity(loading ? 0.45 : 1)
                .overlay(alignment: .top) {
                    if loading { ProgressView().tint(Theme.orange).padding(.top, 60) }
                }
                .animation(.easeOut(duration: 0.15), value: loading)
            } else if let error {
                ExploreMessage(title: error.isNotFound ? "Block not found" : "Couldn't load this block",
                               message: error.isNotFound ? "Check the height or hash and try again." : error.exploreMessage,
                               systemImage: "cube.transparent")
            } else {
                ProgressView().tint(Theme.orange).padding(.top, 80)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let block, let height = currentHeight {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(height <= 0)
                        .accessibilityLabel("Previous block")
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(tip.map { height >= $0 } ?? true)
                        .accessibilityLabel("Next block")
                    if let url = ExploreRoute.block(.hash(block.id)).webURL(base: Explore.webBase) {
                        Button { Share.link(url, title: "Block \(Format.grouped(Double(block.height)))") } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share")
                    }
                }
            }
        }
        .task(id: ref) {
            guard loadedRef != ref || block == nil else { return }
            if price == nil { price = Explore.cachedPrice() }
            await load()
        }
    }

    private func load() async {
        let client = Explore.client()
        let target = ref
        loading = true
        defer { if target == ref { loading = false } }
        do {
            let hash: String
            switch ref {
            case .hash(let h): hash = h
            case .height(let h): hash = try await client.blockHash(height: h)
            case .timestamp(let t): hash = try await client.blockAt(timestamp: t).hash
            }
            async let height = try? client.tipHeight()
            async let firstPage = try? client.blockTransactions(hash, start: 0)
            let fresh = try await client.block(hash)
            let (newTip, page) = await (height, firstPage)
            guard target == ref else { return }
            tip = newTip ?? tip
            txs = page ?? []
            block = fresh
            loadedRef = target
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard target == ref else { return }
            block = nil
            self.error = Explore.failure(error)
        }
    }

    private func loadMore(_ block: Block) async {
        guard !loadingTxs, txs.count < block.txCount else { return }
        loadingTxs = true
        defer { loadingTxs = false }
        let start = txs.count
        if let more = try? await Explore.client().blockTransactions(block.id, start: start),
           self.block?.id == block.id, txs.count == start {
            txs += more
        }
    }

    private func header(_ block: Block) -> some View {
        let date = Date(timeIntervalSince1970: TimeInterval(block.timestamp))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.grouped(Double(block.height))).font(.number(.largeTitle, weight: .bold))
                    Text("\(date.formatted(date: .abbreviated, time: .shortened)) · \(date.formatted(.relative(presentation: .named)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BlockCube(intensity: block.extras?.medianFee.map(Theme.feeIntensity) ?? 1, size: 48)
            }
            if let pool = block.extras?.pool?.name {
                (Text("Mined by ").foregroundColor(.secondary) + Text(pool).foregroundColor(Theme.orange).bold())
                    .font(.subheadline)
            }
            if let searchedTime {
                Text("Last block mined at or before \(Date(timeIntervalSince1970: TimeInterval(searchedTime)).formatted(date: .abbreviated, time: .shortened)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MonoID(value: block.id, font: .system(.caption, design: .monospaced))
        }
        .card()
    }

    private func stats(_ block: Block) -> some View {
        VStack(spacing: 10) {
            StatRow(label: "Transactions", value: Format.grouped(Double(block.txCount)))
            if let median = block.extras?.medianFee { StatRow(label: "Median fee", value: Format.feeRate(median)) }
            if let range = block.extras?.feeRange, let low = range.first, let high = range.last {
                StatRow(label: "Fee range", value: "\(Format.feeRateNumber(low))–\(Format.feeRateNumber(high)) sat/vB")
            }
            if let fees = block.extras?.totalFees {
                StatRow(label: "Total fees", value: Format.btc(fees) + (price.map { " · " + Format.fiat(fees, price: $0.price(in: currency), currency) } ?? ""))
            }
            if let reward = block.extras?.reward { StatRow(label: "Reward", value: Format.btc(reward)) }
            StatRow(label: "Size", value: String(format: "%.2f MB", Double(block.size) / 1_000_000))
            StatRow(label: "Weight", value: String(format: "%.2f MWU", Double(block.weight) / 1_000_000))
            if let tip, tip >= block.height {
                StatRow(label: "Confirmations", value: Format.grouped(Double(tip - block.height + 1)))
            }
        }
        .card()
    }

    private func transactions(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Transactions · \(Format.grouped(Double(block.txCount)))").padding(.bottom, 6)
            LazyVStack(spacing: 0) {
                ForEach(txs) { tx in
                    RouteRow(route: .transaction(tx.txid, output: nil)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.short(tx.txid, head: 10, tail: 8))
                                .font(.system(.footnote, design: .monospaced))
                            if tx.isCoinbase {
                                Text("Coinbase").font(.caption2).foregroundStyle(Theme.orange)
                            } else if let rate = tx.feeRate {
                                Text(Format.feeRate(rate)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(Format.btc(tx.totalOutput)).font(.number(.footnote, weight: .medium)).lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    if tx.id != txs.last?.id { Divider().overlay(Theme.border) }
                }
            }
            if txs.count < block.txCount {
                Button {
                    Task { await loadMore(block) }
                } label: {
                    HStack {
                        Spacer()
                        if loadingTxs { ProgressView().controlSize(.small) } else { Text("Show 25 more") }
                        Spacer()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}
