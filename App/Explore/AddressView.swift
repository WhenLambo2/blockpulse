import SwiftUI
import BitcoinKit

/// One address: balance in BTC and money, totals, and its history with what each transaction did
/// to the balance. Refreshes every minute while open.
struct AddressView: View {
    let address: String

    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @State private var info: AddressInfo?
    @State private var txs: [BitcoinTx] = []
    @State private var tip: Int?
    @State private var price: PriceInfo?
    @State private var error: MempoolError?
    @State private var loadingMore = false
    @State private var loadMoreFailed = false
    @State private var loadedAt: Date?
    @State private var reachedEnd = false
    @State private var showQR = false

    private static let pollInterval: Duration = .seconds(60)
    private static let pageSize = 25

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }
    private var route: ExploreRoute { .address(address) }
    private var kind: AddressKind { AddressKind(address) }

    var body: some View {
        ExplorePage(title: "Address", refresh: load) {
            if let info {
                header(info)
                stats(info)
                history(info)
            } else if let error {
                ExploreMessage(title: error == .http(400) ? "Not a valid Bitcoin address" : "Couldn't load this address",
                               message: error == .http(400) ? "Check the address against the original and try again." : error.exploreMessage,
                               systemImage: "exclamationmark.triangle")
            } else {
                ProgressView().tint(Theme.orange).padding(.top, 80)
            }
        }
        .toolbar { ShareTools(route: route, qrPayload: address, qrTitle: "Address", showQR: $showQR) }
        .sheet(isPresented: $showQR) {
            QRCodeSheet(kind: "\(kind.label) address", value: address, payload: address,
                        shareURL: route.webURL(base: Explore.webBase))
        }
        .task {
            if price == nil { price = Explore.cachedPrice() }
            // Coming back from a transaction opened from here: only reload when it's been a while.
            if loadedAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true { await load() }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    /// Totals and the first page. Older pages already loaded are kept below the fresh first page.
    private func load() async {
        let client = Explore.client()
        do {
            async let firstPage = client.addressTransactions(address)
            async let height = try? client.tipHeight()
            let fresh = try await client.address(address)
            let page = try await firstPage
            let ids = Set(page.map(\.txid))
            let confirmedInPage = page.filter(\.status.confirmed).count
            txs = page + txs.filter { !ids.contains($0.txid) && $0.status.confirmed }
            if txs.count == page.count { reachedEnd = confirmedInPage < Self.pageSize }
            tip = await height ?? tip
            info = fresh
            error = nil
            loadedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            if info == nil { self.error = Explore.failure(error) }
        }
    }

    private func loadMore() async {
        guard !loadingMore, !reachedEnd, let last = txs.last(where: \.status.confirmed) else { return }
        loadingMore = true
        loadMoreFailed = false
        defer { loadingMore = false }
        let more: [BitcoinTx]
        do {
            more = try await Explore.client().addressTransactions(address, after: last.txid)
        } catch {
            if !(error is CancellationError) { loadMoreFailed = true }
            return
        }
        let ids = Set(txs.map(\.txid))
        txs += more.filter { !ids.contains($0.txid) }
        if more.count < Self.pageSize { reachedEnd = true }
    }

    private func header(_ info: AddressInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("\(kind.label) address")
            MonoID(value: address)
            AmountView(sats: info.balance, price: price, currency: currency)
            if info.pendingChange != 0 {
                Label("\(Format.btc(info.pendingChange, signed: true)) pending", systemImage: "hourglass")
                    .font(.number(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.orange)
            }
        }
        .card()
    }

    private func stats(_ info: AddressInfo) -> some View {
        VStack(spacing: 10) {
            StatRow(label: "Received", value: Format.btc(info.totalReceived))
            StatRow(label: "Sent", value: Format.btc(info.totalSent))
            StatRow(label: "Transactions", value: Format.grouped(Double(info.txCount)))
            StatRow(label: "Unspent outputs", value: Format.grouped(Double(info.unspentCount)))
        }
        .card()
    }

    @ViewBuilder
    private func history(_ info: AddressInfo) -> some View {
        if info.txCount == 0 {
            ExploreMessage(title: "No transactions yet",
                           message: "This address is valid but has never received anything.",
                           systemImage: "tray")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("History").padding(.bottom, 6)
                LazyVStack(spacing: 0) {
                    ForEach(txs) { tx in
                        RouteRow(route: .transaction(tx.txid, output: nil)) { historyRow(tx) }
                            .onAppear {
                                if tx.id == txs.last?.id { Task { await loadMore() } }
                            }
                        if tx.id != txs.last?.id { Divider().overlay(Theme.border) }
                    }
                }
                if loadingMore {
                    ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(.top, 10)
                } else if loadMoreFailed {
                    Button { Task { await loadMore() } } label: {
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

    private func historyRow(_ tx: BitcoinTx) -> some View {
        let net = tx.netValue(for: address)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.short(tx.txid, head: 10, tail: 6)).font(.system(.footnote, design: .monospaced))
                Text(statusLine(tx)).font(.caption2).foregroundStyle(tx.status.confirmed ? Color.secondary : Theme.orange)
            }
            Spacer(minLength: 6)
            Text(Format.btc(net, signed: true))
                .font(.number(.footnote, weight: .semibold))
                .foregroundStyle(net >= 0 ? Theme.up : Theme.down)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
    }

    private func statusLine(_ tx: BitcoinTx) -> String {
        guard tx.status.confirmed, let height = tx.status.blockHeight else { return "Pending" }
        var line = "Block \(Format.grouped(Double(height)))"
        if let n = tx.confirmations(tip: tip) { line += " · \(Format.grouped(Double(n))) conf." }
        if let date = tx.status.blockDate { line += " · " + date.formatted(date: .abbreviated, time: .omitted) }
        return line
    }
}
