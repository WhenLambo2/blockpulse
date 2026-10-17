import SwiftUI
import BitcoinKit

/// Explore tab: search like mempool.space (block height or hash, transaction, address, date), a QR
/// scanner, and the live strip of pending and mined blocks with the latest blocks below it.
struct ExploreView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ExploreModel()
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var suggestions: [String] = []
    @State private var isLookingUp = false
    @State private var showScanner = false
    @State private var recents: [ExploreRoute] = []

    private var interpretation: SearchInterpretation { SearchParser.interpret(text, tip: model.tip) }
    private var searching: Bool { focused || !text.isEmpty }

    var body: some View {
        @Bindable var appState = appState
        NavigationStack(path: $appState.explorePath) {
            VStack(spacing: 0) {
                BrandHeader()
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 12) {
                        if searching { searchPanel } else { browse }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await model.refresh() }
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ExploreRoute.self) { ExploreDestination(route: $0) }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet(tip: model.tip) { route in navigate(to: route) }
            }
        }
        .tint(Theme.orange)
        .task { await model.refresh() }
        .task { await model.runLiveUpdates() }
        .task(id: text) { await lookUpPrefix() }
        .onAppear { recents = AppPreferences().recentSearches }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onChange(of: appState.dataSourceVersion) { _, _ in
            model.reset()
            Task { await model.refresh() }
        }
        .sensoryFeedback(.selection, trigger: interpretation.target) { old, new in new != nil && old != new }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Block, transaction or address", text: $text)
                    .font(text.isEmpty ? .body : .system(.subheadline, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit(submit)
                if isLookingUp {
                    ProgressView().controlSize(.small)
                } else if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Theme.orange : Theme.border, lineWidth: focused ? 1.5 : 1)
            )
            Button { showScanner = true } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan QR code")
            if searching {
                Button("Cancel") {
                    text = ""
                    focused = false
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.orange)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: searching)
    }

    @ViewBuilder
    private var searchPanel: some View {
        let i = interpretation
        if i.query.isEmpty {
            HStack {
                SectionLabel("Recent searches")
                PasteButton(payloadType: String.self) { strings in
                    guard let value = strings.first else { return }
                    Task { @MainActor in pasted(value) }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(Theme.orange)
                .controlSize(.small)
            }
            if recents.isEmpty {
                Text("Search by block height, block hash, transaction id, address or date, or scan a QR code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.enumerated()), id: \.offset) { index, route in
                        Button { navigate(to: route) } label: { recentRow(route) }
                            .buttonStyle(.plain)
                        if index < recents.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
                .card()
                Button("Clear recent searches") {
                    AppPreferences().recentSearches = []
                    recents = []
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text("Stored on this iPhone only.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else {
            if let target = i.target {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(target.title)
                    Button { navigate(to: target.route) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: target.route))
                                .foregroundStyle(Theme.orange)
                                .frame(width: 24)
                            Text("Go to \u{201C}\(Format.short(i.query, head: 12, tail: 8))\u{201D}")
                                .font(.system(.subheadline, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "return").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Theme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .card()
            }
            if let issue = i.issue {
                ExploreMessage(title: issue.title, message: issue.message,
                               systemImage: issueIcon(issue), tint: issueTint(issue))
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Bitcoin addresses")
                    ForEach(suggestions, id: \.self) { address in
                        Button { navigate(to: .address(address)) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bitcoinsign.circle").foregroundStyle(Theme.orange).frame(width: 24)
                                highlighted(address, prefix: i.query)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
            if i.target == nil && i.issue == nil && suggestions.isEmpty && !isLookingUp && !i.allowsPrefixLookup {
                ExploreMessage(title: "No match",
                               message: "Try a block height, block hash, transaction id, address or a date like 2009-01-03.",
                               systemImage: "questionmark.circle")
            }
        }
    }

    private func recentRow(_ route: ExploreRoute) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: route)).foregroundStyle(Theme.orange).frame(width: 24)
            Text(recentLabel(route))
                .font(route.isBlock ? .subheadline : .system(.footnote, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func recentLabel(_ route: ExploreRoute) -> String {
        switch route {
        case .block(.height(let h)): "Block \(Format.grouped(Double(h)))"
        case .block(.hash(let h)): "Block " + Format.short(h, head: 10, tail: 6)
        case .block(.timestamp(let t)):
            "Block at " + Date(timeIntervalSince1970: TimeInterval(t)).formatted(date: .abbreviated, time: .shortened)
        case .transaction(let txid, _): Format.short(txid, head: 12, tail: 8)
        case .address(let a): Format.short(a, head: 14, tail: 8)
        case .pendingBlock(let i): i == 0 ? "Next block" : "Pending block \(i + 1)"
        }
    }

    private func icon(for route: ExploreRoute) -> String {
        switch route {
        case .block: "cube"
        case .transaction: "arrow.left.arrow.right"
        case .address: "bitcoinsign.circle"
        case .pendingBlock: "hourglass"
        }
    }

    private func issueIcon(_ issue: SearchIssue) -> String {
        switch issue {
        case .privateKey, .extendedPublicKey: "lock.shield"
        case .futureBlock, .futureDate: "clock"
        case .addressTypo: "exclamationmark.triangle"
        default: "nosign"
        }
    }

    private func issueTint(_ issue: SearchIssue) -> Color {
        switch issue {
        case .privateKey, .addressTypo: Theme.down
        default: Theme.orange
        }
    }

    /// The typed prefix in orange, the rest as is.
    private func highlighted(_ address: String, prefix: String) -> Text {
        guard address.lowercased().hasPrefix(prefix.lowercased()) else { return Text(address) }
        let head = String(address.prefix(prefix.count))
        let tail = String(address.dropFirst(prefix.count))
        return Text(head).foregroundColor(Theme.orange).bold() + Text(tail)
    }

    private func submit() {
        let i = interpretation
        if let target = i.target {
            navigate(to: target.route)
        } else if let first = suggestions.first {
            navigate(to: .address(first))
        }
    }

    /// Pasted text opens straight away when it is complete, otherwise it stays in the field.
    private func pasted(_ value: String) {
        let i = SearchParser.interpret(value, tip: model.tip)
        if let target = i.target { navigate(to: target.route) } else { text = i.query }
    }

    private func navigate(to route: ExploreRoute) {
        AppPreferences().remember(route)
        recents = AppPreferences().recentSearches
        text = ""
        focused = false
        appState.explorePath.append(route)
    }

    /// Up to ten known addresses starting with the text, 200 ms after the last keystroke.
    private func lookUpPrefix() async {
        isLookingUp = false
        let i = interpretation
        guard i.allowsPrefixLookup else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        isLookingUp = true
        let found = (try? await Explore.client().addressPrefix(i.query)) ?? []
        guard !Task.isCancelled else { return }
        isLookingUp = false
        suggestions = found.count == 1 && found[0] == i.query ? [] : found
    }

    // MARK: - Browse

    @ViewBuilder
    private var browse: some View {
        if let error = model.error, model.blocks.isEmpty {
            ExploreMessage(title: "Blocks didn't load", message: error.exploreMessage,
                           systemImage: "exclamationmark.triangle")
        }
        if !model.blocks.isEmpty || !model.projected.isEmpty {
            BlockStrip(projected: model.projected, blocks: Array(model.blocks.prefix(8)))
        } else if model.isLoading {
            ProgressView().tint(Theme.orange).padding(.top, 60)
        }
        if !model.blocks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Latest blocks").padding(.bottom, 6)
                LazyVStack(spacing: 0) {
                    ForEach(model.blocks) { block in
                        RouteRow(route: .block(.hash(block.id))) { LatestBlockRow(block: block) }
                            .onAppear {
                                if block.id == model.blocks.last?.id { Task { await model.loadMore() } }
                            }
                        if block.id != model.blocks.last?.id { Divider().overlay(Theme.border) }
                    }
                }
                if model.isLoadingMore {
                    ProgressView().tint(Theme.orange).frame(maxWidth: .infinity).padding(.top, 10)
                }
            }
            .card()
        }
    }
}

extension ExploreRoute {
    var isBlock: Bool { if case .block = self { true } else { false } }
}

/// Pending blocks on the left, mined blocks on the right, split by a dashed line, like mempool.space.
/// It opens centred on the line.
struct BlockStrip: View {
    let projected: [ProjectedBlock]
    let blocks: [Block]
    private static let now = "now"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Pending")
                Spacer()
                SectionLabel("Mined").fixedSize()
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array(projected.prefix(8).enumerated()).reversed(), id: \.offset) { index, block in
                            NavigationLink(value: ExploreRoute.pendingBlock(index)) {
                                PendingCube(block: block, index: index)
                            }
                            .buttonStyle(.plain)
                        }
                        Line()
                            .stroke(Theme.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(width: 2, height: 104)
                            .id(Self.now)
                        ForEach(blocks) { block in
                            NavigationLink(value: ExploreRoute.block(.hash(block.id))) { MinedCube(block: block) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(Self.now, anchor: .center) }
                .onChange(of: projected.count) { _, _ in proxy.scrollTo(Self.now, anchor: .center) }
                .onChange(of: blocks.first?.id) { _, _ in
                    withAnimation(.snappy) { proxy.scrollTo(Self.now, anchor: .center) }
                }
            }
            if let next = projected.first {
                Text("Next block ~\(Format.feeRate(next.medianFee)). Tap a block to open it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
    }
}

/// A projected block: brighter orange for higher fees, dark text on it.
struct PendingCube: View {
    let block: ProjectedBlock
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("~\(PendingPosition.minutes(index: index)) min").font(.caption2.weight(.medium)).opacity(0.75)
            Text(Format.feeRate(block.medianFee)).font(.number(.subheadline, weight: .bold))
            Text("\(Format.feeRateNumber(block.minFee))–\(Format.feeRateNumber(block.maxFee)) sat/vB")
                .font(.number(.caption2, weight: .regular)).opacity(0.75)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text("\(Format.grouped(Double(block.nTx))) tx").font(.number(.caption2, weight: .regular)).opacity(0.75)
        }
        .foregroundStyle(Color(hex: 0x1A1206))
        .padding(9)
        .frame(width: 96, height: 104, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Theme.orange, Theme.orangeDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(Theme.feeIntensity(block.medianFee))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(index == 0 ? "Next block" : "Pending block \(index + 1)")
        .accessibilityValue("\(Format.feeRate(block.medianFee)), \(block.nTx) transactions")
    }
}

struct MinedCube: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Format.grouped(Double(block.height)))
                .font(.number(.subheadline, weight: .bold))
                .foregroundStyle(Theme.orange)
            Text(Date(timeIntervalSince1970: TimeInterval(block.timestamp)), format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text("\(Format.grouped(Double(block.txCount))) tx").font(.number(.caption2, weight: .regular))
            Spacer(minLength: 0)
            Text(block.extras?.pool?.name ?? "Unknown")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(9)
        .frame(width: 96, height: 104, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Block \(block.height)")
    }
}

struct LatestBlockRow: View {
    let block: Block

    var body: some View {
        HStack(spacing: 12) {
            BlockCube(intensity: block.extras?.medianFee.map(Theme.feeIntensity) ?? 1, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.grouped(Double(block.height))).font(.number(.body, weight: .bold))
                Text("\(block.extras?.pool?.name ?? "Unknown") · \(Format.grouped(Double(block.txCount))) tx")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(Date(timeIntervalSince1970: TimeInterval(block.timestamp)), format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// The page for a route, used by the Explore stack.
struct ExploreDestination: View {
    let route: ExploreRoute

    var body: some View {
        switch route {
        case .transaction(let txid, let output): TransactionView(txid: txid, output: output)
        case .block(let ref): BlockView(ref: ref)
        case .address(let address): AddressView(address: address)
        case .pendingBlock(let index): PendingBlockView(index: index)
        }
    }
}
