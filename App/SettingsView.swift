import SwiftUI
import WidgetKit
import BitcoinKit

/// Settings tab: a plain grouped list. Every change applies straight away.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue
    @AppStorage(AppPreferences.Keys.appearance) private var appearanceRaw = Appearance.dark.rawValue
    @AppStorage(AppPreferences.Keys.feeTilesShowFiat) private var feeTilesShowFiat = false

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }

    private var dataHost: String {
        _ = appState.dataSourceVersion  // re-read after a change
        return AppSettings.shared().baseURL.host() ?? "mempool.space"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrandHeader()
                Form {
                    Section("Display") {
                        Picker("Appearance", selection: $appearanceRaw) {
                            ForEach(Appearance.allCases, id: \.self) { a in Text(a.label).tag(a.rawValue) }
                        }
                        Picker("Currency", selection: $currencyRaw) {
                            ForEach(Currency.allCases, id: \.self) { c in Text("\(c.code) (\(c.symbol))").tag(c.rawValue) }
                        }
                        Picker("Fee tiles show", selection: $feeTilesShowFiat) {
                            Text("sat/vB").tag(false)
                            Text("Cost in \(currency.symbol)").tag(true)
                        }
                    }
                    Section {
                        NavigationLink {
                            HomeCardsEditor()
                        } label: {
                            LabeledContent("Card order", value: appState.cardOrder == HomeCard.allCases ? "Default" : "Custom")
                        }
                        NavigationLink {
                            FavouritesEditor()
                        } label: {
                            LabeledContent("Chart favourites", value: "\(appState.favourites.count)")
                        }
                    } header: {
                        Text("Home and charts")
                    } footer: {
                        Text("You can also hold and drag a card on the home screen, or tap the star on a chart.")
                    }
                    DataSourceSection()
                    Section("About") {
                        HStack(spacing: 14) {
                            BlockpulseLogo(size: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Blockpulse").font(.system(.title3, design: .rounded, weight: .bold))
                                Text("The heartbeat of the Bitcoin network.").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        LabeledContent("Version", value: Bundle.main.versionString)
                        LabeledContent("Data", value: dataHost)
                        LabeledContent("Made by", value: "Arterion")
                        // Apple requires the privacy policy to be reachable from inside the app.
                        Link(destination: URL(string: "https://blockpul.se/privacy")!) {
                            Label("Privacy policy", systemImage: "hand.raised")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: currencyRaw) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}

/// Public mempool.space or any other mempool.space-compatible URL.
struct DataSourceSection: View {
    enum Source: String, CaseIterable, Identifiable {
        case mempool, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .mempool: "mempool.space"
            case .custom: "Custom"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @State private var source: Source
    @State private var customText: String
    @State private var check: ConnectionCheck?
    @State private var isChecking = false

    init() {
        let url = AppSettings.shared().baseURL
        let source: Source = url == MempoolClient.defaultBaseURL ? .mempool : .custom
        _source = State(initialValue: source)
        _customText = State(initialValue: source == .custom ? url.absoluteString : "")
    }

    private var selectedURL: URL? {
        switch source {
        case .mempool: MempoolClient.defaultBaseURL
        case .custom: AppSettings.validatedBaseURL(customText)
        }
    }

    var body: some View {
        Section {
            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { Text($0.label).tag($0) }
            }
            if source == .custom {
                TextField("https://mempool.example.com", text: $customText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(apply)
                    .onDisappear(perform: apply)
            }
            Button {
                Task { await runCheck() }
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    if isChecking { ProgressView() }
                }
            }
            .disabled(isChecking || selectedURL == nil)
            if let check {
                Label(check.summary, systemImage: check.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(check.succeeded ? Color.green : Color.red)
            }
        } header: {
            Text("Data source")
        } footer: {
            if source == .custom && selectedURL == nil && !customText.isEmpty {
                Text("Enter a valid http(s) URL. Until then the app keeps using mempool.space.").foregroundStyle(.red)
            } else {
                Text("Any mempool.space-compatible instance works, such as your own node. The widgets use it too.")
            }
        }
        .onChange(of: source) { _, _ in
            check = nil
            apply()
        }
    }

    /// Saves the choice; an invalid custom URL falls back to mempool.space.
    private func apply() {
        let settings = AppSettings.shared()
        let before = settings.baseURL
        settings.baseURLString = source == .mempool ? nil : selectedURL?.absoluteString
        guard settings.baseURL != before else { return }
        WidgetCenter.shared.reloadAllTimelines()
        appState.dataSourceChanged()
    }

    /// Tests exactly the chosen URL; never silently substitutes another one.
    private func runCheck() async {
        guard let url = selectedURL else { return }
        apply()
        isChecking = true
        defer { isChecking = false }
        check = await MempoolClient(baseURL: url).checkConnection()
    }
}

/// Reorder the home screen cards; the block header always stays on top.
struct HomeCardsEditor: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        List {
            Section {
                ForEach(appState.cardOrder) { card in
                    Label(card.title, systemImage: card.systemImage)
                }
                .onMove { appState.cardOrder.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("The block number and price always stay on top.")
            }
            Section {
                Button("Reset to default order") {
                    withAnimation { appState.cardOrder = HomeCard.allCases }
                }
                .disabled(appState.cardOrder == HomeCard.allCases)
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Card order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Reorder or remove favourites, and add any chart that isn't one yet.
struct FavouritesEditor: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppSettings.Keys.currency, store: AppSettings.sharedDefaults)
    private var currencyRaw = Currency.eur.rawValue

    private var currency: Currency { Currency(rawValue: currencyRaw) ?? .eur }

    var body: some View {
        @Bindable var appState = appState
        List {
            Section("Favourites") {
                if appState.favourites.isEmpty {
                    Text("None yet. Add charts below.").foregroundStyle(.secondary)
                }
                ForEach(appState.favourites) { id in
                    Label(id.title(currency), systemImage: id.category.systemImage)
                }
                .onMove { appState.favourites.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { appState.favourites.remove(atOffsets: $0) }
            }
            Section("Add") {
                ForEach(ChartID.allCases.filter { !appState.favourites.contains($0) }) { id in
                    Button {
                        withAnimation { appState.favourites.append(id) }
                    } label: {
                        HStack {
                            Label(id.title(currency), systemImage: id.category.systemImage)
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.orange)
                        }
                    }
                    .tint(.primary)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Chart favourites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

extension HomeCard {
    var systemImage: String {
        switch self {
        case .fees: "gauge.with.dots.needle.33percent"
        case .mempool: "tray.full"
        case .difficulty: "dial.medium"
        case .halving: "scissors"
        case .blocks: "cube"
        }
    }
}

#Preview {
    SettingsView().environment(AppState())
}
