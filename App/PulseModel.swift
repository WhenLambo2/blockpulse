import Foundation
import Observation
import WidgetKit
import BitcoinKit

@MainActor
@Observable
final class PulseModel {
    static let liveInterval: Duration = .seconds(60)

    private(set) var result: SnapshotResult?
    private(set) var extras: PulseExtras = .empty
    private(set) var isLoading = false
    /// Bumps when a new block arrives, to pulse the heartbeat.
    private(set) var blockBeat = 0

    /// Always hits the network (no reuse window). Overlapping calls are dropped while one is in flight.
    /// `reloadWidgets`: nudge widgets to pick up the fresh cache (launch, foreground, pull to refresh; not the minute timer).
    func refresh(reloadWidgets: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let settings = AppSettings.shared()
        let client = settings.makeClient(transport: DemoMode.transport)
        let service = SnapshotService(client: client, store: SnapshotStore.appGroup())
        async let snapshot = service.load(reuseIfYoungerThan: 0)
        async let live = PulseExtras.load(client)
        let (newResult, newExtras) = await (snapshot, live)

        let previousTip = result?.snapshot?.tipHeight
        result = newResult
        extras = newExtras
        if let tip = newResult.snapshot?.tipHeight, let previousTip, tip > previousTip { blockBeat += 1 }
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Refreshes every minute while the Pulse tab is on screen; cancelled with the view's task.
    func runLiveUpdates() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: DemoMode.liveInterval ?? Self.liveInterval)
            guard !Task.isCancelled else { return }
            await refresh(reloadWidgets: false)
        }
    }
}
