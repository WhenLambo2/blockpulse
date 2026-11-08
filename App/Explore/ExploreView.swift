import SwiftUI
import BitcoinKit

/// Search tab: look up a block height or hash, transaction, address or date, a QR scanner,
/// the pulse line of mined and upcoming blocks, and a mempool overview below it.
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

    /// Worked out once per edit rather than on every redraw.
    @State private var interpretation = SearchParser.interpret("", tip: nil)
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
            .navigationDestination(for: ExploreRoute.self) { ExploreDestination(route: $0, model: model) }
            .fullScreenCover(isPresented: $showScanner) {
                QRScannerSheet(tip: model.tip) { route in navigate(to: route) }
            }
        }
        .tint(Theme.orange)
        .task { await model.refresh() }
        // Live updates pause while a detail page is open; that page refreshes itself.
        .task(id: appState.explorePath.isEmpty) {
            guard appState.explorePath.isEmpty else { return }
            await model.runLiveUpdates()
        }
        .task(id: text) { await lookUpPrefix() }
        .onChange(of: text, initial: true) { _, new in interpretation = SearchParser.interpret(new, tip: model.tip) }
        .onChange(of: model.tip) { _, tip in interpretation = SearchParser.interpret(text, tip: tip) }
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
        case .latestBlocks: "All blocks"
        }
    }

    private func icon(for route: ExploreRoute) -> String {
        switch route {
        case .block: "cube"
        case .transaction: "arrow.left.arrow.right"
        case .address: "bitcoinsign.circle"
        case .pendingBlock: "hourglass"
        case .latestBlocks: "square.stack.3d.up"
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
        } else if let first = suggestions.first, first.lowercased().hasPrefix(i.query.lowercased()) {
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
        let i = SearchParser.interpret(text, tip: model.tip)
        // Suggestions for an earlier prefix go at once, so Return can't open one of them.
        suggestions = suggestions.filter { $0.lowercased().hasPrefix(i.query.lowercased()) }
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
            MempoolOverview(model: model)
            DataCredit()
        } else if model.isLoading {
            ProgressView().tint(Theme.orange).padding(.top, 60)
        }
    }
}

extension ExploreRoute {
    var isBlock: Bool { if case .block = self { true } else { false } }
}

/// The pulse line: time runs left to right. Mined blocks are solid cubes on the left, a heartbeat
/// marks "now" with the time since the last block, and the blocks still to come are outlined cubes
/// on the right that glow brighter as fees rise. It opens centred on the heartbeat.
struct BlockStrip: View {
    let projected: [ProjectedBlock]
    let blocks: [Block]
    private static let now = "now"
    /// While the strip is being dragged or is still gliding, a new block doesn't pull it back to "now".
    @State private var scrolling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Blocks")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 4) {
                        if !blocks.isEmpty {
                            NavigationLink(value: ExploreRoute.latestBlocks) { AllBlocksTile() }
                                .buttonStyle(.plain)
                        }
                        ForEach(blocks.reversed()) { block in
                            NavigationLink(value: ExploreRoute.block(.hash(block.id))) { MinedCube(block: block) }
                                .buttonStyle(.plain)
                        }
                        NowBeat(lastBlock: blocks.first)
                            .id(Self.now)
                        ForEach(Array(projected.prefix(8).enumerated()), id: \.offset) { index, block in
                            NavigationLink(value: ExploreRoute.pendingBlock(index)) {
                                PendingCube(block: block, index: index)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onScrollPhaseChange { _, phase in scrolling = phase != .idle }
                .onAppear { proxy.scrollTo(Self.now, anchor: .center) }
                .onChange(of: projected.isEmpty) { _, _ in proxy.scrollTo(Self.now, anchor: .center) }
                .onChange(of: blocks.first?.id) { _, _ in
                    guard !scrolling else { return }
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
}

/// Size of a cube in the pulse line, and the width of each slot under it.
private enum StripMetrics {
    static let cube: CGFloat = 38
    static let slot: CGFloat = 66
}

/// "Now" in the pulse line: the heartbeat from the logo and the time since the last block.
struct NowBeat: View {
    let lastBlock: Block?
    @ScaledMetric(relativeTo: .caption2) private var slot: CGFloat = StripMetrics.slot

    var body: some View {
        VStack(spacing: 4) {
            HeartbeatShape()
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: slot, height: StripMetrics.cube * 1.08)
            Text("now").font(.number(.caption, weight: .bold)).foregroundStyle(Theme.orange)
            if let lastBlock {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.sinceText(lastBlock, now: context.date))
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .frame(width: slot)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lastBlock.map { "Now. \(Self.sinceText($0, now: .now)) since the last block" } ?? "Now")
    }

    private static func sinceText(_ block: Block, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince1970 - TimeInterval(block.timestamp)) / 60)
        return "\(minutes) min"
    }
}

/// A block still to come: an outlined cube, filled brighter for higher fees.
struct PendingCube: View {
    let block: ProjectedBlock
    let index: Int
    @ScaledMetric(relativeTo: .caption2) private var slot: CGFloat = StripMetrics.slot

    var body: some View {
        let intensity = Theme.feeIntensity(block.medianFee)
        VStack(spacing: 4) {
            OutlineCube(intensity: intensity, size: StripMetrics.cube)
            Text(Format.feeRate(block.medianFee))
                .font(.number(.caption, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("~\(PendingPosition.minutes(index: index)) min")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: slot)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(index == 0 ? "Next block" : "Pending block \(index + 1)")
        .accessibilityValue("\(Format.feeRate(block.medianFee)), \(block.nTx) transactions")
    }
}

/// A mined block: the solid logo cube, its height and how long ago it was found.
struct MinedCube: View {
    let block: Block
    @ScaledMetric(relativeTo: .caption2) private var slot: CGFloat = StripMetrics.slot

    var body: some View {
        VStack(spacing: 4) {
            BlockCube(size: StripMetrics.cube)
            Text(Format.grouped(Double(block.height)))
                .font(.number(.caption, weight: .bold))
                .foregroundStyle(Theme.orange)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(Date(timeIntervalSince1970: TimeInterval(block.timestamp)), format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: slot)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Block \(block.height)")
        .accessibilityValue("\(block.txCount) transactions, \(block.extras?.pool?.name ?? "unknown pool")")
    }
}

/// The logo cube drawn as an outline, for blocks that are not mined yet.
struct OutlineCube: View {
    var intensity: Double = 1
    var size: CGFloat = 38

    var body: some View {
        Canvas { context, canvas in
            let inset: CGFloat = 1
            let w = canvas.width - inset * 2, h = canvas.height - inset * 2
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: inset + w * x, y: inset + h * y) }
            let outline = Path { p in
                p.move(to: pt(0.5, 0))
                p.addLine(to: pt(1, 0.25))
                p.addLine(to: pt(1, 0.75))
                p.addLine(to: pt(0.5, 1))
                p.addLine(to: pt(0, 0.75))
                p.addLine(to: pt(0, 0.25))
                p.closeSubpath()
            }
            let edges = Path { p in
                p.move(to: pt(0, 0.25)); p.addLine(to: pt(0.5, 0.5)); p.addLine(to: pt(1, 0.25))
                p.move(to: pt(0.5, 0.5)); p.addLine(to: pt(0.5, 1))
            }
            context.fill(outline, with: .color(Theme.orange.opacity(0.08 + 0.3 * intensity)))
            let stroke = StrokeStyle(lineWidth: 1.5, lineJoin: .round)
            context.stroke(outline, with: .color(Theme.orange.opacity(0.35 + 0.65 * intensity)), style: stroke)
            context.stroke(edges, with: .color(Theme.orange.opacity(0.35 + 0.65 * intensity)), style: stroke)
        }
        .frame(width: size, height: size * 1.08)
        .accessibilityHidden(true)
    }
}

/// The start of the strip: opens the full block list.
struct AllBlocksTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up").font(.title3)
            Text("All blocks").font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.orange)
        .frame(width: 70, height: StripMetrics.cube * 1.08 + 36)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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
    let model: ExploreModel

    var body: some View {
        switch route {
        case .transaction(let txid, let output): TransactionView(txid: txid, output: output)
        case .block(let ref): BlockView(ref: ref)
        case .address(let address): AddressView(address: address)
        case .pendingBlock(let index): PendingBlockView(index: index)
        case .latestBlocks: LatestBlocksView(model: model)
        }
    }
}
