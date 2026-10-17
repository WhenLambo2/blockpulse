import SwiftUI
import BitcoinKit

/// One transaction: status first (pending with an estimate, or confirmations), then amounts, fee,
/// and its inputs and outputs. Checks again every 30 seconds until it confirms.
struct TransactionView: View {
    let txid: String
    /// From a `txid:n` search: that output is highlighted.
    let output: Int?

    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @State private var tx: BitcoinTx?
    @State private var outspends: [Outspend] = []
    @State private var effectiveRate: Double?
    @State private var projected: [ProjectedBlock] = []
    @State private var tip: Int?
    @State private var price: PriceInfo?
    @State private var notFound = false
    @State private var replacedBy: String?
    @State private var error: MempoolError?
    @State private var showQR = false
    @State private var showAllInputs = false
    @State private var showAllOutputs = false

    private static let pollInterval: Duration = .seconds(30)
    private static let listLimit = 25

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }
    private var route: ExploreRoute { .transaction(txid, output: output) }

    var body: some View {
        ExplorePage(title: "Transaction", refresh: load) {
            if let tx {
                header(tx)
                details(tx)
                inputs(tx)
                outputs(tx)
            } else if notFound {
                if let replacedBy {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusPill(text: "Replaced", color: Theme.orange, systemImage: "arrow.triangle.2.circlepath")
                        Text("This transaction was replaced by a newer version with a higher fee.")
                            .font(.subheadline)
                        RouteRow(route: .transaction(replacedBy, output: nil)) {
                            Text(Format.short(replacedBy, head: 12, tail: 8))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Theme.orange)
                            Spacer()
                        }
                    }
                    .card()
                } else {
                    ExploreMessage(title: "Transaction not found yet",
                                   message: "Waiting for it to reach the mempool. This page checks again every 30 seconds.",
                                   systemImage: "hourglass")
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Transaction id")
                    MonoID(value: txid)
                }
                .card()
            } else if let error {
                ExploreMessage(title: "Couldn't load this transaction", message: error.exploreMessage,
                               systemImage: "exclamationmark.triangle")
            } else {
                ProgressView().tint(Theme.orange).padding(.top, 80)
            }
        }
        .toolbar { ShareTools(route: route, qrPayload: qrPayload, qrTitle: "Transaction", showQR: $showQR) }
        .sheet(isPresented: $showQR) {
            QRCodeSheet(kind: "Transaction", value: txid, payload: qrPayload,
                        shareURL: route.webURL(base: Explore.webBase))
        }
        .task {
            price = Explore.cachedPrice()
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled, tx?.status.confirmed != true else { return }
                await load()
            }
        }
    }

    /// The web link, so any phone camera can open it.
    private var qrPayload: String { route.webURL(base: Explore.webBase)?.absoluteString ?? txid }

    private func load() async {
        let client = Explore.client()
        do {
            let fresh = try await client.transaction(txid)
            async let spends = try? client.outspends(txid)
            async let height = try? client.tipHeight()
            if !fresh.status.confirmed {
                async let cpfp = try? client.cpfp(txid)
                async let blocks = try? client.projectedBlocks()
                effectiveRate = await cpfp?.effectiveFeePerVsize
                projected = await blocks ?? projected
            }
            outspends = await spends ?? outspends
            tip = await height ?? tip
            tx = fresh
            notFound = false
            error = nil
        } catch let failure as MempoolError where failure.isNotFound {
            notFound = true
            replacedBy = (try? await client.rbf(txid))?.replacement(of: txid)
        } catch {
            self.error = Explore.failure(error)
        }
    }

    // MARK: - Sections

    private func header(_ tx: BitcoinTx) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoID(value: tx.txid)
            status(tx)
            if tx.isCoinbase {
                Text("Coinbase: the block reward and fees paid to the miner.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            AmountView(sats: tx.totalOutput, price: price, currency: currency)
            FlowRow(spacing: 6) {
                if let rate = shownRate(tx) { Chip(text: Format.feeRate(rate) + (effectiveRate != nil && !tx.status.confirmed ? " effective" : "")) }
                if let fee = tx.fee, !tx.isCoinbase {
                    Chip(text: Format.sats(fee) + (price.map { " · " + Format.fiat(fee, price: $0.price(in: currency), currency) } ?? ""))
                }
                Chip(text: "\(Format.grouped(Double(tx.vsize))) vB")
                if tx.usesSegWit { Chip(text: "SegWit") }
                if tx.usesTaproot { Chip(text: "Taproot") }
                if tx.signalsRBF && !tx.status.confirmed { Chip(text: "RBF") }
            }
        }
        .card()
    }

    @ViewBuilder
    private func status(_ tx: BitcoinTx) -> some View {
        if tx.status.confirmed {
            if let n = tx.confirmations(tip: tip) {
                StatusPill(text: n == 1 ? "Confirmed · 1 confirmation" : "Confirmed · \(Format.grouped(Double(n))) confirmations",
                           color: Theme.up, systemImage: "checkmark.circle.fill")
            } else {
                StatusPill(text: "Confirmed", color: Theme.up, systemImage: "checkmark.circle.fill")
            }
        } else {
            StatusPill(text: "Pending · \(etaText(tx))", color: Theme.orange, systemImage: "hourglass")
        }
    }

    private func shownRate(_ tx: BitcoinTx) -> Double? {
        tx.status.confirmed ? tx.feeRate : (effectiveRate ?? tx.feeRate)
    }

    private func pendingIndex(_ tx: BitcoinTx) -> Int? {
        shownRate(tx).flatMap { PendingPosition.blockIndex(feeRate: $0, projected: projected) }
    }

    private func etaText(_ tx: BitcoinTx) -> String {
        guard !projected.isEmpty else { return "waiting for a block" }
        guard let i = pendingIndex(tx) else { return "not in the next \(projected.count) blocks" }
        return i == 0 ? "next block likely" : "in ~\(PendingPosition.minutes(index: i)) min"
    }

    private func details(_ tx: BitcoinTx) -> some View {
        VStack(spacing: 10) {
            if tx.status.confirmed {
                if let height = tx.status.blockHeight {
                    RouteRow(route: .block(.height(height))) {
                        StatRow(label: "Block", value: Format.grouped(Double(height)))
                    }
                }
                if let date = tx.status.blockDate {
                    StatRow(label: "Mined", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            } else {
                StatRow(label: "Estimated", value: pendingIndex(tx).map { "~\(PendingPosition.minutes(index: $0)) min" } ?? "Not soon")
                if let i = pendingIndex(tx) {
                    RouteRow(route: .pendingBlock(i)) {
                        StatRow(label: "Position", value: i == 0 ? "Next block" : "Pending block \(i + 1)")
                    }
                }
            }
            if let rate = tx.feeRate, !tx.isCoinbase { StatRow(label: "Fee rate", value: Format.feeRate(rate)) }
            StatRow(label: "Size", value: "\(Format.grouped(Double(tx.size))) B")
            StatRow(label: "Weight", value: "\(Format.grouped(Double(tx.weight))) WU")
        }
        .card()
    }

    private func inputs(_ tx: BitcoinTx) -> some View {
        let shown = showAllInputs ? tx.vin : Array(tx.vin.prefix(Self.listLimit))
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Inputs · \(tx.vin.count)")
            ForEach(Array(shown.enumerated()), id: \.offset) { _, input in
                if input.isCoinbase {
                    ioRow(label: "Coinbase (new coins)", value: nil, route: nil, highlighted: false)
                } else {
                    ioRow(label: input.prevout?.label ?? Format.short(input.txid),
                          value: input.prevout?.value,
                          route: input.prevout?.scriptpubkeyAddress.map { .address($0) },
                          highlighted: false)
                }
            }
            if tx.vin.count > shown.count {
                Button("Show all \(Format.grouped(Double(tx.vin.count))) inputs") { showAllInputs = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange)
            }
        }
        .card()
    }

    private func outputs(_ tx: BitcoinTx) -> some View {
        let limit = max(Self.listLimit, (output ?? 0) + 1)
        let shown = showAllOutputs ? tx.vout : Array(tx.vout.prefix(limit))
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Outputs · \(tx.vout.count)")
            ForEach(Array(shown.enumerated()), id: \.offset) { index, out in
                VStack(alignment: .leading, spacing: 4) {
                    ioRow(label: out.label, value: out.value,
                          route: out.scriptpubkeyAddress.map { .address($0) },
                          highlighted: index == output)
                    if index < outspends.count, outspends[index].spent, let spender = outspends[index].txid {
                        NavigationLink(value: ExploreRoute.transaction(spender, output: nil)) {
                            Label("Spent in \(Format.short(spender))", systemImage: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 10)
                    }
                }
            }
            if tx.vout.count > shown.count {
                Button("Show all \(Format.grouped(Double(tx.vout.count))) outputs") { showAllOutputs = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange)
            }
        }
        .card()
    }

    @ViewBuilder
    private func ioRow(label: String, value: Int?, route: ExploreRoute?, highlighted: Bool) -> some View {
        let row = HStack(spacing: 10) {
            Text(label.count > 24 ? Format.short(label, head: 10, tail: 6) : label)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(route == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let value { Text(Format.btc(value)).font(.number(.footnote, weight: .medium)).lineLimit(1) }
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.orange, lineWidth: 1.5)
            }
        }
        if let route {
            NavigationLink(value: route) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

/// Lays chips out in rows, wrapping to the next line when full.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
