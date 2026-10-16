import SwiftUI
import BitcoinKit

/// Home: what matters right now, as foldable cards answering practical questions.
/// The block header stays on top; the cards below can be reordered by holding and dragging.
struct PulseView: View {
    @Environment(AppState.self) private var appState
    @State private var model = PulseModel()
    @State private var dropTarget: HomeCard?
    /// Block number on screen. It trails the real tip so it rolls over when the celebration bursts.
    @State private var shownTip: Int?
    /// While the old number is held for the celebration, the old block's time, so "since the last block"
    /// resets together with the number instead of a second before it.
    @State private var heldBlockDate: Date?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @AppStorage(AppPreferences.Keys.feeTilesShowFiat) private var feeTilesShowFiat = false

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            content
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let result = model.result, let error = result.error {
                    errorBanner(error, cached: result.source == .cache)
                }
                if let snapshot = model.result?.snapshot {
                    header(snapshot)
                    ForEach(appState.cardOrder) { card in
                        homeCard(card, snapshot: snapshot)
                            .overlay {
                                if dropTarget == card {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.orange, lineWidth: 2)
                                }
                            }
                            .draggable(card.rawValue) {
                                Label(card.title, systemImage: card.systemImage)
                                    .font(.headline)
                                    .padding(14)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .dropDestination(for: String.self) { items, _ in
                                move(items.first, to: card)
                            } isTargeted: { targeted in
                                if targeted { dropTarget = card } else if dropTarget == card { dropTarget = nil }
                            }
                    }
                } else if !model.isLoading {
                    ContentUnavailableView("No data", systemImage: "bitcoinsign.circle", description: Text("Pull to refresh."))
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .overlay {
            if model.isLoading && model.result == nil { ProgressView().tint(Theme.orange) }
        }
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .task { await model.runLiveUpdates() }
        .task {
            // CI screenshots: `-celebrateAfter 18` plays the block-found animation that many seconds after launch.
            let delay = UserDefaults.standard.double(forKey: "celebrateAfter")
            guard delay > 0 else { return }
            try? await Task.sleep(for: .seconds(delay))
            appState.celebrate()
        }
        // Returning to the foreground refreshes (and, via refresh(), the widgets). Overlapping calls are dropped.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onChange(of: appState.dataSourceVersion) { _, _ in Task { await model.refresh() } }
    }

    /// Drops `raw` (a dragged card) where `target` is: before it when moving up, after it when moving down.
    private func move(_ raw: String?, to target: HomeCard) -> Bool {
        dropTarget = nil
        guard let raw, let card = HomeCard(rawValue: raw), card != target else { return false }
        var order = appState.cardOrder
        guard let from = order.firstIndex(of: card), let to = order.firstIndex(of: target) else { return false }
        order.remove(at: from)
        order.insert(card, at: to)
        withAnimation(.snappy) { appState.cardOrder = order }
        return true
    }

    @ViewBuilder
    private func homeCard(_ card: HomeCard, snapshot: BitcoinSnapshot) -> some View {
        switch card {
        case .fees:
            if let fees = snapshot.fees { feeCard(fees, price: snapshot.price) }
        case .mempool:
            if let mempool = snapshot.mempool { mempoolCard(mempool) }
        case .difficulty:
            if let difficulty = snapshot.difficulty { difficultyCard(difficulty) }
        case .halving:
            if let tip = snapshot.tipHeight, let tipDate = snapshot.lastBlockDate {
                halvingCard(HalvingCountdown(tipHeight: tip, tipDate: tipDate))
            }
        case .blocks:
            if !snapshot.blocks.isEmpty { recentBlocksCard(snapshot.blocks) }
        }
    }

    // MARK: - Header

    private func header(_ s: BitcoinSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                FreshnessDot(fresh: !s.isStale(now: Date()))
                Text((shownTip ?? s.tipHeight).map(Format.blockHeight) ?? "—")
                    .font(.number(.largeTitle, weight: .bold))
                    .contentTransition(.numericText(value: Double(shownTip ?? s.tipHeight ?? 0)))
                Spacer()
                if let p = s.price {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.price(p.price(in: currency), currency))
                            .font(.number(.title3))
                            .contentTransition(.numericText())
                        if let change = p.change24hPercent(in: currency) {
                            Text("\(Format.signedPercent(change)) 24h")
                                .font(.number(.caption, weight: .medium))
                                .foregroundStyle(Theme.change(change))
                        }
                    }
                }
            }
            if let last = heldBlockDate ?? s.lastBlockDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(elapsed(since: last, now: context.date)) since the last block")
                        .font(.number(.subheadline, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            HeartbeatLine(beat: celebrationBeat)
            HStack {
                Spacer()
                Text(updatedLine(s.fetchedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
        .modifier(BlockFoundEffect(beat: celebrationBeat))
        .zIndex(1)  // the flare draws over the card below
        .onChange(of: s.tipHeight) { old, new in
            guard let new else { return }
            if let old, new > old {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {  // keep the old number until the burst
                    shownTip = old
                    heldBlockDate = s.blocks.first { $0.height == old }?.timestamp
                }
                rollTip(from: old, to: new)
            } else {
                shownTip = new
            }
        }
        .onChange(of: appState.celebration) { _, _ in
            if let tip = s.tipHeight { rollTip(from: tip - 1, to: tip) }
        }
    }

    private var celebrationBeat: Int { model.blockBeat &+ appState.celebration }

    /// Holds `from` on screen until the celebration bursts, then rolls the digits to `to`.
    private func rollTip(from: Int, to: Int) {
        Task {
            try? await Task.sleep(for: .seconds(BlockFound.burstDelay))
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { shownTip = from }
            try? await Task.sleep(for: .milliseconds(40))
            heldBlockDate = nil
            withAnimation(.spring(duration: 0.8, bounce: 0.35)) { shownTip = to }
        }
    }

    /// "Updated 21:05", plus the host when it isn't public mempool.space.
    private func updatedLine(_ date: Date) -> String {
        _ = appState.dataSourceVersion
        let time = date.formatted(.dateTime.hour().minute())
        let settings = AppSettings.shared()
        guard settings.usesCustomInstance, let host = settings.baseURL.host() else { return "Updated \(time)" }
        return "Updated \(time) · \(host)"
    }

    // MARK: - Cards

    private func feeCard(_ fees: RecommendedFees, price: PriceInfo?) -> some View {
        let congestion = Congestion(nextBlockFee: fees.fastestFee)
        let fiat = price?.price(in: currency)
        let showFiat = feeTilesShowFiat && fiat != nil
        let tiers: [(String, Double)] = [
            ("Next block", fees.fastestFee), ("~30 min", fees.halfHourFee),
            ("~1 hour", fees.hourFee), ("Economy", fees.economyFee),
        ]
        return FoldableCard("What fee to pay", systemImage: "gauge.with.dots.needle.33percent", key: "fees") {
            Text(congestion.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.congestion(congestion))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(tiers, id: \.0) { label, rate in
                        feeTile(label, rate: rate, cost: FeeCost(rate: rate, price: fiat), showFiat: showFiat)
                    }
                }
                CongestionMeter(congestion: congestion)
                Text(fiat == nil
                     ? "Cost shown for a typical payment of \(FeeCost.typicalVSize) vB."
                     : "Typical payment of \(FeeCost.typicalVSize) vB. Tap a tile to show \(showFiat ? "sat/vB" : "the cost in \(currency.symbol)").")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Tapping any tile swaps every tile between sat/vB and the cost in money.
    private func feeTile(_ label: String, rate: Double, cost: FeeCost, showFiat: Bool) -> some View {
        Button {
            withAnimation(.snappy) { feeTilesShowFiat.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if showFiat, let money = cost.fiat {
                        Text(currency.symbol + String(format: "%.2f", money))
                            .font(.number(.title2, weight: .bold))
                    } else {
                        Text(Format.feeRateNumber(rate)).font(.number(.title2, weight: .bold))
                        Text("sat/vB").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentTransition(.numericText())
                Text(showFiat ? "\(Format.feeRate(rate)) · \(Format.sats(cost.sats))" : cost.summary(currency))
                    .font(.number(.caption, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(label == "Next block" ? Theme.orange.opacity(0.12) : Theme.cardRaised,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(showFiat ? "Shows fee rates" : "Shows the cost")
    }

    private func mempoolCard(_ m: MempoolStats) -> some View {
        FoldableCard("Mempool traffic", systemImage: "tray.full", key: "mempool", openByDefault: true) {
            Text(Format.vMB(m.vsize)).font(.number(.subheadline)).foregroundStyle(.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if !model.extras.projectedBlocks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(model.extras.projectedBlocks.prefix(8).enumerated()), id: \.offset) { i, block in
                                VStack(spacing: 6) {
                                    BlockCube(intensity: Theme.feeIntensity(block.medianFee))
                                    Text("~\(Format.feeRateNumber(block.medianFee))")
                                        .font(.number(.caption, weight: .semibold))
                                    Text(i == 0 ? "next" : "+\(i)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Projected block \(i + 1), median \(Format.feeRate(block.medianFee))")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Text("Projected blocks, median sat/vB. Brighter means pricier.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    StatRow(label: "Transactions waiting", value: Format.grouped(Double(m.count)))
                    StatRow(label: "Blocks to clear", value: "~\(m.blocksToClear)")
                    if let inflow = model.extras.inflow {
                        StatRow(label: "Incoming", value: "\(Format.grouped(inflow)) vB/s")
                    }
                    StatRow(label: "Fees waiting", value: Format.sats(m.totalFee))
                }
            }
        }
    }

    private func difficultyCard(_ d: DifficultyAdjustment) -> some View {
        FoldableCard("Next difficulty adjustment", systemImage: "dial.medium", key: "difficulty") {
            Text(Format.signedPercent(d.difficultyChange))
                .font(.number(.subheadline))
                .foregroundStyle(Theme.change(d.difficultyChange))
        } content: {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(progress: d.progressPercent / 100)
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f%%", d.progressPercent)).font(.number(.title3, weight: .bold))
                        Text("of cycle").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.difficultyChange >= 0 ? "Difficulty goes up" : "Difficulty goes down")
                        .font(.subheadline.weight(.semibold))
                    Text("\(Format.signedPercent(d.difficultyChange)) estimated")
                        .font(.number(.title3, weight: .bold))
                        .foregroundStyle(Theme.change(d.difficultyChange))
                    Text(d.retargetDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                        .font(.number(.caption, weight: .regular))
                    Text("\(Format.grouped(Double(d.remainingBlocks))) blocks to go · block \(Format.grouped(Double(d.nextRetargetHeight)))")
                        .font(.number(.caption, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func halvingCard(_ h: HalvingCountdown) -> some View {
        FoldableCard("Next halving", systemImage: "scissors", key: "halving", openByDefault: false) {
            Text(Format.grouped(Double(h.remainingBlocks)) + " blocks").font(.number(.subheadline)).foregroundStyle(.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: h.progress).tint(Theme.orange)
                StatRow(label: "Halving block", value: Format.blockHeight(h.nextHeight))
                StatRow(label: "Blocks to go", value: Format.grouped(Double(h.remainingBlocks)))
                HStack {
                    Text("Estimated").foregroundStyle(.secondary)
                    Spacer()
                    Text(h.estimatedDate, format: .dateTime.day().month(.abbreviated).year()).font(.number(.body, weight: .medium))
                }
                .font(.subheadline)
                Text("Assumes 10-minute blocks from the latest block.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recentBlocksCard(_ blocks: [BlockSummary]) -> some View {
        FoldableCard("Recent blocks", systemImage: "cube", key: "blocks") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(blocks) { b in
                        VStack(alignment: .leading, spacing: 6) {
                            BlockCube(size: 34)
                            Text(Format.blockHeight(b.height)).font(.number(.subheadline, weight: .bold))
                            Text(b.timestamp, style: .relative).font(.caption2).foregroundStyle(.secondary)
                            Text("\(Format.compactCount(b.txCount)) tx").font(.number(.caption, weight: .regular))
                            if let fee = b.medianFee {
                                Text("~\(Format.feeRate(fee))").font(.number(.caption, weight: .regular))
                            }
                            Text(b.poolName ?? "Unknown").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(12)
                        .frame(width: 128, alignment: .leading)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func errorBanner(_ error: MempoolError, cached: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.orange)
                .font(.subheadline.weight(.semibold))
            if cached { Text("Showing cached data.").font(.caption).foregroundStyle(.secondary) }
        }
        .card()
    }

    /// "4m 12s", "1h 03m"
    private func elapsed(since date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s >= 3_600 { return String(format: "%dh %02dm", s / 3_600, (s % 3_600) / 60) }
        return String(format: "%dm %02ds", s / 60, s % 60)
    }
}

#Preview {
    PulseView().environment(AppState())
}
