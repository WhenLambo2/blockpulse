import SwiftUI
import UIKit
import BitcoinKit

/// What every Explore page needs: the client for the chosen data source, and the last known price.
enum Explore {
    static func client() -> MempoolClient { AppSettings.shared().makeClient(transport: DemoMode.transport) }

    /// The web explorer the share links point at: the data source from Settings.
    static var webBase: URL { AppSettings.shared().baseURL }

    /// Price from the shared snapshot cache, so pages show euro values without another request.
    static func cachedPrice() -> PriceInfo? { SnapshotStore.appGroup()?.load()?.price }

    /// "mempool.space", or the custom host.
    static var dataHost: String { AppSettings.shared().baseURL.host() ?? "mempool.space" }

    static func failure(_ error: Error) -> MempoolError {
        error as? MempoolError ?? .network(error.localizedDescription)
    }
}

/// A long id in monospace that can be selected, with a copy button.
struct MonoID: View {
    let value: String
    var font: Font = .system(.footnote, design: .monospaced)
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(value)
                .font(font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = value
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(copied ? Theme.up : Theme.orange)
                    .frame(width: 30, height: 30)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied" : "Copy")
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var systemImage: String = "circle.fill"

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.number(.caption, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Small uppercase heading above a group.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An empty, waiting or error state with a plain explanation.
struct ExploreMessage: View {
    let title: String
    let message: String
    var systemImage: String = "magnifyingglass"
    var tint: Color = Theme.orange

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.title2.weight(.semibold)).foregroundStyle(tint)
            Text(title).font(.system(.headline, design: .rounded)).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .card()
    }
}

/// "Data: mempool.space" under every result page.
struct DataCredit: View {
    var body: some View {
        Text("Data: \(Explore.dataHost)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

/// BTC amount with its value in the chosen currency underneath.
struct AmountView: View {
    let sats: Int
    let price: PriceInfo?
    let currency: Currency
    var signed = false
    var font: Font = .number(.title, weight: .bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.btc(sats, signed: signed))
                .font(font)
                .foregroundStyle(signed ? (sats >= 0 ? Theme.up : Theme.down) : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let price {
                Text(Format.fiat(sats, price: price.price(in: currency), currency))
                    .font(.number(.subheadline, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Common frame for result pages: scrolling cards on the app background, credit at the end.
struct ExplorePage<Content: View>: View {
    let title: String
    var refresh: @MainActor () async -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                content()
                DataCredit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .refreshable { await refresh() }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// QR and share buttons for the top bar of address and transaction pages.
struct ShareTools: ToolbarContent {
    let route: ExploreRoute
    /// What the QR code holds (an address, or the transaction's web link).
    let qrPayload: String
    let qrTitle: String
    @Binding var showQR: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showQR = true } label: { Image(systemName: "qrcode") }
                .accessibilityLabel("Show QR code")
            if let url = route.webURL(base: Explore.webBase) {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
            }
        }
    }
}

/// Opens an Explore page from a row.
struct RouteRow<Content: View>: View {
    let route: ExploreRoute
    @ViewBuilder var label: () -> Content

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                label()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension MempoolError {
    /// Wording for Explore pages, where "not found" is the common case.
    var exploreMessage: String {
        switch self {
        case .network: "Check your connection and pull down to try again."
        case .rateLimited: "The data source is busy. Try again in a minute."
        default: userMessage
        }
    }
}
