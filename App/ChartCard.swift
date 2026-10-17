import SwiftUI
import Charts
import BitcoinKit

/// Shared loader so every chart card reuses one cache (and one price-history download).
/// A new data source gets a fresh loader, so charts never mix instances.
@MainActor
enum ChartStore {
    private static var current: (url: URL, loader: ChartLoader)?

    static var loader: ChartLoader {
        let url = AppSettings.shared().baseURL
        if let current, current.url == url { return current.loader }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let file = url == MempoolClient.defaultBaseURL ? "price-history.json" : "price-history-\(url.host() ?? "custom").json"
        let loader = ChartLoader(client: MempoolClient(baseURL: url, transport: DemoMode.transport), priceHistoryFile: caches?.appendingPathComponent(file))
        current = (url, loader)
        return loader
    }
}

/// One full-screen chart: title, current value, period picker, chart or table, favourite star.
struct ChartCard: View {
    let id: ChartID
    let isFavourite: Bool
    let onToggleFavourite: () -> Void

    @Environment(AppState.self) private var appState
    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @State private var period: ChartPeriod?
    @State private var showTable = false
    @State private var hiddenLines: Set<String> = []
    @State private var showFullTable = false
    @State private var result: ChartResult?
    @State private var error: String?
    @State private var isLoading = false
    /// Loading has taken long enough to show it; quick loads swap (or morph) without a dim and spinner flash.
    @State private var isSlow = false
    /// The value under the finger while scrubbing; the headline shows it instead of the latest value.
    @State private var scrub: ChartScrub?

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }

    /// The result on screen belongs to another period than the one picked (a load is running).
    private var isStale: Bool { result.map { $0.period != (period ?? id.defaultPeriod) } ?? false }

    init(id: ChartID, isFavourite: Bool, onToggleFavourite: @escaping () -> Void) {
        self.id = id
        self.isFavourite = isFavourite
        self.onToggleFavourite = onToggleFavourite
        _period = State(initialValue: id.defaultPeriod)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if id.periods.count > 1 {
                Picker("Period", selection: $period) {
                    ForEach(id.periods) { p in Text(p.label).tag(Optional(p)) }
                }
                .pickerStyle(.segmented)
            }
            ZStack {
                if let result {
                    if showTable && id.hasTable {
                        ChartTableView(table: result.table, limit: 12) { showFullTable = true }
                    } else {
                        // Single-line charts morph from one period into the next (both are resampled to the
                        // same points). Others get a fresh chart per period: animating one data set into another
                        // with a different number of points smears the lines and fills the area under them.
                        ChartCanvas(result: result, hidden: $hiddenLines, scrub: $scrub)
                            .id("\(result.id.rawValue)|\(ChartCanvas.morphs(result) ? "-" : result.period?.rawValue ?? "-")|\(currency.code)")
                            .opacity(isStale && isSlow ? 0.35 : 1)
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await load(force: true) } }
                    }
                }
                if isLoading && isSlow && (result == nil || isStale) { ProgressView().tint(Theme.orange) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(id.subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .card()
        .task(id: "\(period?.rawValue ?? "-")|\(currency.code)|\(appState.dataSourceVersion)") { await load(force: false) }
        .sheet(isPresented: $showFullTable) {
            if let result {
                NavigationStack {
                    ScrollView { ChartTableView(table: result.table, limit: nil, onShowAll: nil).padding() }
                        .background(Theme.background)
                        .navigationTitle(id.title(currency))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFullTable = false } } }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(id.title(currency)).font(.headline)
                Spacer()
                if id.hasTable {
                    Button {
                        withAnimation(.snappy) { showTable.toggle() }
                    } label: {
                        Image(systemName: showTable ? "chart.xyaxis.line" : "tablecells")
                    }
                    .accessibilityLabel(showTable ? "Show chart" : "Show table")
                }
                Button(action: onToggleFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .foregroundStyle(isFavourite ? Theme.orange : .secondary)
                }
                .padding(.leading, 12)
                .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
            }
            .font(.title3)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scrub?.value ?? result?.headline ?? "—")
                    .font(.number(.title, weight: .bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                if let scrub {
                    Text(scrub.date, format: scrubDateFormat)
                        .font(.number(.subheadline))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                } else if let change = result?.change {
                    Text(Format.change(change))
                        .font(.number(.subheadline))
                        .lineLimit(1)
                        .foregroundStyle(Theme.change(change))
                }
            }
        }
    }

    /// Hours only matter on the short periods.
    private var scrubDateFormat: Date.FormatStyle {
        switch period ?? id.defaultPeriod {
        case .twoHours, .day, .week: .dateTime.day().month(.abbreviated).hour().minute()
        default: .dateTime.day().month(.abbreviated).year()
        }
    }

    /// A new period's chart morphs in (single-line charts) or fades in, and the headline rolls to its value.
    private func show(_ new: ChartResult) {
        guard new != result else { return }
        withAnimation(result == nil ? nil : .smooth(duration: 0.55)) { result = new }
    }

    private func load(force: Bool) async {
        // Show what's cached for this period straight away; otherwise the previous period stays, dimmed.
        if let cached = await ChartStore.loader.cached(id, period: period, currency: currency) { show(cached) }
        isLoading = true
        let slow = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { isSlow = true }
        }
        defer { slow.cancel(); isLoading = false; isSlow = false }
        do {
            let loaded = try await ChartStore.loader.load(id, period: period, currency: currency, force: force)
            show(loaded)
            error = nil
        } catch {
            self.error = (error as? MempoolError)?.userMessage ?? error.localizedDescription
            if result?.period != period || result?.id != id { result = nil }
        }
    }
}

// MARK: - Chart drawing

/// What the card's headline shows while a finger is on the chart.
struct ChartScrub: Equatable {
    let value: String
    let date: Date
}

/// Draws a `ChartResult` in its chart style, with press-and-drag to read values.
struct ChartCanvas: View {
    let result: ChartResult
    @State private var selectedDate: Date?
    @State private var selectedLabel: String?
    /// Lines hidden by tapping their legend entry (hashrate chart); kept by the card across periods.
    @Binding var hidden: Set<String>
    /// Single-series charts report the value under the finger here, for the card's headline.
    @Binding var scrub: ChartScrub?

    /// Points every morphing chart is resampled to, so one period's line can move point by point into the next.
    static let morphPoints = 240

    /// Single-line charts (price, sats, block fees...) morph between periods instead of being replaced.
    static func morphs(_ result: ChartResult) -> Bool {
        result.id.style == .line && result.series.count == 1
    }

    /// One drawn point, numbered so a morphing chart keeps the same points across periods.
    private struct DrawnPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    private func drawn(_ line: Line) -> [DrawnPoint] {
        let points = Self.morphs(result) ? Downsample.resample(line.points, count: Self.morphPoints) : line.points
        return points.enumerated().map { DrawnPoint(id: $0.offset, date: $0.element.date, value: $0.element.value) }
    }

    var body: some View {
        switch result.id.style {
        case .line, .area, .band: timeChart
        case .bars: barChart
        case .donut: donutChart
        case .blocks: RecentBlocksView(blocks: result.blocks)
        }
    }

    /// One drawn line. Series on another unit (difficulty) are rescaled onto the first series' range,
    /// because their shape matters, not their axis.
    struct Line: Identifiable {
        let series: ChartSeries
        let points: [ChartPoint]
        let color: Color
        let width: CGFloat
        let dashed: Bool
        var id: String { series.name }
    }

    private var lines: [Line] {
        guard let primary = result.series.first else { return [] }
        if result.series.count == 1 {
            return [Line(series: primary, points: primary.points, color: Theme.orange, width: 2, dashed: false)]
        }
        let sameUnit = result.series.filter { $0.unit == primary.unit }
        let scaleMax = sameUnit.flatMap(\.points).map(\.value).max() ?? 0
        let start = primary.points.first?.date ?? .distantPast
        return result.series.enumerated().map { i, s in
            if s.unit == primary.unit {
                // Raw daily values faint, the moving average bold.
                let isRaw = i == 0 && sameUnit.count > 1
                return Line(series: s, points: s.points, color: isRaw ? Theme.orange.opacity(0.22) : Theme.orange,
                            width: isRaw ? 0.8 : 2.4, dashed: false)
            }
            let maxValue = s.points.map(\.value).max() ?? 0
            let factor = maxValue > 0 && scaleMax > 0 ? scaleMax / maxValue : 1
            let points = s.points.filter { $0.date >= start }.map { ChartPoint(date: $0.date, value: $0.value * factor) }
            return Line(series: s, points: points, color: Theme.orangeDeep, width: 1.5, dashed: true)
        }
    }

    // Line, area and band charts over time.
    private var timeChart: some View {
        let all = lines
        let visible = all.filter { !hidden.contains($0.id) }
        let anchor = visible.first ?? all.first
        // Rescaled lines (difficulty) have no axis of their own, so the axis labels only show for real-scale lines.
        let axisUnit = visible.first(where: { !$0.dashed })?.series.unit
        let primaryPoints = result.series.first?.points ?? []
        let selected = selectedDate.flatMap { d in anchor.flatMap { nearest(to: d, in: $0.points) } }
        return Chart {
            if !hidden.contains(all.first?.id ?? "") {
                ForEach(primaryPoints) { p in
                    if result.id.style == .band, let low = p.low, let high = p.high {
                        AreaMark(x: .value("Date", p.date), yStart: .value("Low", low), yEnd: .value("High", high))
                            .foregroundStyle(Theme.orange.opacity(0.25))
                            .interpolationMethod(.monotone)
                    }
                    if result.id.style == .area {
                        AreaMark(x: .value("Date", p.date), y: .value("Value", p.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.orange.opacity(0.45), Theme.orange.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            ForEach(visible) { line in
                ForEach(drawn(line)) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value), series: .value("Series", line.id))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: line.width, dash: line.dashed ? [4, 3] : []))
                        .interpolationMethod(line.dashed ? .stepEnd : .monotone)
                }
            }
            if let selected {
                // Plain lines show the value in the card's headline; the readout is for bands and several lines.
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        if !headlineFollows {
                            readout(date: selected.date, lines: readoutLines(at: selected.date, visible: visible))
                        }
                    }
                PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                    .foregroundStyle(Theme.orange)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: .automatic(includesZero: result.id.style == .area))
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel { if let v = value.as(Double.self), let axisUnit { Text(axisUnit.axis(v)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel()
            }
        }
        .chartXSelection(value: $selectedDate)
        .onChange(of: selected?.date) { _, _ in
            guard let s = result.series.first, result.series.count == 1 else { return }
            scrub = selected.map { ChartScrub(value: s.unit.format($0.value), date: $0.date) }
        }
        .onDisappear { scrub = nil }
        .padding(.top, all.count > 1 ? 36 : 28)  // room for the readout and legend
        .overlay(alignment: .topLeading) {
            if all.count > 1 {
                HStack(spacing: 6) {
                    ForEach(all) { line in legend(line) }
                }
                .fixedSize()
                .opacity(selected == nil ? 1 : 0)
            }
        }
    }

    /// The card's headline carries the scrubbed value for a single plain line.
    private var headlineFollows: Bool {
        result.series.count == 1 && result.id.style != .band
    }

    /// Tappable legend entry that shows or hides its line.
    private func legend(_ line: Line) -> some View {
        let isHidden = hidden.contains(line.id)
        return Button {
            withAnimation(.snappy) {
                if isHidden { hidden.remove(line.id) } else { hidden.insert(line.id) }
            }
        } label: {
            HStack(spacing: 5) {
                Capsule().fill(line.color).frame(width: line.dashed ? 8 : 14, height: 3)
                Text(line.id).font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isHidden ? Color.secondary : Color.primary)
            .background(isHidden ? Color.clear : Theme.cardRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
            .opacity(isHidden ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(line.id), \(isHidden ? "hidden" : "shown")")
        .accessibilityHint("Shows or hides this line")
    }

    /// Readout at a date: each visible line's real (unscaled) value.
    private func readoutLines(at date: Date, visible: [Line]) -> [String] {
        if result.series.count == 1, let s = result.series.first, let p = nearest(to: date, in: s.points) {
            var lines = [s.unit.format(p.value)]
            if let low = p.low, let high = p.high { lines.append("\(s.unit.format(low)) – \(s.unit.format(high))") }
            return lines
        }
        return visible.compactMap { line in
            // Step lines (difficulty) read the last value at or before the date.
            let source = line.dashed ? line.series.points.filter { $0.date <= date } : line.series.points
            guard let p = line.dashed ? source.last : nearest(to: date, in: source) else { return nil }
            return "\(line.id) \(line.series.unit.format(p.value))"
        }
    }

    private var barChart: some View {
        let unit = result.barUnit ?? .count
        let bars = result.bars
        let selected = selectedLabel.flatMap { label in bars.first { $0.label == label } }
        return Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Item", bar.label), y: .value("Value", bar.value))
                    .foregroundStyle(barColor(bar, unit: unit))
                    .cornerRadius(3)
            }
            if let selected {
                RuleMark(x: .value("Item", selected.label))
                    .foregroundStyle(Color.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        readout(date: nil, lines: [selected.label, unit.format(selected.value)])
                    }
            }
        }
        .chartXAxis(bars.count > 12 ? .hidden : .automatic)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel { if let v = value.as(Double.self) { Text(unit.axis(v)) } }
            }
        }
        .chartXSelection(value: $selectedLabel)
        .padding(.top, 28)
    }

    private func barColor(_ bar: ChartBar, unit: ChartUnit) -> Color {
        if unit == .percent && result.id == .difficultyHistory { return bar.value >= 0 ? Theme.up : Theme.down }
        if unit == .satPerVB { return Theme.orange.opacity(Theme.feeIntensity(bar.value)) }
        return Theme.orange
    }

    private var donutChart: some View {
        let bars = result.bars
        let labels = bars.map(\.label)
        return VStack(spacing: 16) {
            Chart(bars) { bar in
                SectorMark(angle: .value("Share", bar.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(by: .value("Pool", bar.label))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: labels, range: Array(Theme.slices.prefix(max(labels.count, 1))))
            .chartLegend(.hidden)
            .frame(maxHeight: 220)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, bar in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.slices[min(i, Theme.slices.count - 1)]).frame(width: 8, height: 8)
                        Text(bar.label).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(String(format: "%.1f%%", bar.value)).font(.number(.caption, weight: .medium))
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func readout(date: Date?, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let date {
                Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(lines, id: \.self) { Text($0).font(.number(.caption, weight: .semibold)) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func nearest(to date: Date, in points: [ChartPoint]) -> ChartPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Table

struct ChartTableView: View {
    let table: ChartTable
    /// Rows shown inline; nil shows every row.
    let limit: Int?
    let onShowAll: (() -> Void)?

    var body: some View {
        let rows = limit.map { Array(table.rows.prefix($0)) } ?? table.rows
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { i, column in
                        Text(column)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(i == 0 ? .leading : .trailing)
                    }
                }
                Divider().overlay(Theme.border)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.number(.caption, weight: .regular)).lineLimit(1)
                        }
                    }
                }
            }
            if let limit, table.rows.count > limit, let onShowAll {
                Button("Show all \(table.rows.count) rows", action: onShowAll)
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: limit == nil ? nil : .infinity, alignment: .topLeading)
    }
}

// MARK: - Recent blocks

/// The latest blocks as a sideways row of block cards with their details, newest first.
struct RecentBlocksView: View {
    let blocks: [Block]
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(blocks) { block in
                    Button { appState.open(.block(.hash(block.id))) } label: { BlockDetailCard(block: block) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

struct BlockDetailCard: View {
    let block: Block

    private var date: Date { Date(timeIntervalSince1970: TimeInterval(block.timestamp)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                BlockCube(intensity: block.extras?.medianFee.map(Theme.feeIntensity) ?? 1, size: 56)
                Spacer()
                Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.blockHeight(block.height)).font(.number(.title2, weight: .bold))
                Text(block.extras?.pool?.name ?? "Unknown pool")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.orange)
                    .lineLimit(1)
            }
            Divider().overlay(Theme.border)
            VStack(spacing: 11) {
                detail("Time", date.formatted(.dateTime.hour().minute()))
                detail("Transactions", Format.grouped(Double(block.txCount)))
                if let median = block.extras?.medianFee { detail("Median fee", Format.feeRate(median)) }
                if let range = block.extras?.feeRange, let low = range.first, let high = range.last {
                    detail("Fee range", "\(Format.feeRateNumber(low))–\(Format.feeRateNumber(high))")
                }
                detail("Size", String(format: "%.2f MB", Double(block.size) / 1_000_000))
                if let fees = block.extras?.totalFees {
                    detail("Total fees", String(format: "%.3f BTC", Double(fees) / 100_000_000))
                }
            }
        }
        .padding(16)
        .frame(width: 236, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.number(.subheadline, weight: .medium)).lineLimit(1)
        }
        .font(.subheadline)
    }
}
