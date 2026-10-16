import SwiftUI
import UIKit
import BitcoinKit

@main
struct BlockpulseApp: App {
    @AppStorage(AppPreferences.Keys.appearance) private var appearanceRaw = Appearance.dark.rawValue
    /// Launch argument `-selectedTab charts` (or `settings`) opens that tab (used for CI screenshots).
    @AppStorage("selectedTab") private var selectedTab = "pulse"
    @State private var appState = AppState()

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .dark }

    init() {
        _ = DemoMode.launchedAt
    }

    /// Every tap on a tab goes through here, including taps on the tab that is already open,
    /// which is how the Blockpulse tab counts taps for the easter egg.
    private var tabSelection: Binding<String> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == "pulse" { appState.registerHomeTabTap() }
                selectedTab = tab
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: tabSelection) {
                PulseView()
                    .tabItem { Label("Blockpulse", systemImage: "waveform.path.ecg") }
                    .tag("pulse")
                ChartsView()
                    .tabItem { Label("Charts", systemImage: "chart.xyaxis.line") }
                    .tag("charts")
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag("settings")
            }
            .tint(Theme.orange)
            .environment(appState)
            .preferredColorScheme(appearance.colorScheme)
            // preferredColorScheme(nil) doesn't hand control back to the system once a fixed
            // scheme was set, so the window's style is set directly as well.
            .onAppear { applyToWindows(appearance) }
            .onChange(of: appearanceRaw) { _, _ in applyToWindows(appearance) }
        }
    }

    private func applyToWindows(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .dark: .dark
        case .light: .light
        case .system: .unspecified
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}
