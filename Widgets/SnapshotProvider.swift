import Foundation
import WidgetKit
import BitcoinKit

/// One provider for every widget: fetches (or reuses) the shared snapshot and builds entries.
struct SnapshotProvider<Intent: SnapshotWidgetIntent>: AppIntentTimelineProvider {
    typealias Entry = SnapshotEntry

    func placeholder(in context: Context) -> SnapshotEntry {
        .preview()
    }

    func snapshot(for configuration: Intent, in context: Context) async -> SnapshotEntry {
        let settings = AppSettings.shared()
        let currency = configuration.currencyOption.resolve(default: settings.currency)
        // Sample data only in the widget gallery; never present it as real prices elsewhere.
        if context.isPreview {
            return SnapshotEntry(date: .now, snapshot: .sample(), source: .live, currency: currency, metric: configuration.lockMetric)
        }
        let store = SnapshotStore.appGroup()
        if let cached = store?.load() {
            return SnapshotEntry(date: .now, snapshot: cached, source: .cache, currency: currency, metric: configuration.lockMetric)
        }
        let result = await SnapshotService(client: settings.makeClient(), store: store).load()
        return SnapshotEntry(date: .now, snapshot: result.snapshot, source: result.source, currency: currency, metric: configuration.lockMetric)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<SnapshotEntry> {
        let settings = AppSettings.shared()
        let service = SnapshotService(client: settings.makeClient(), store: SnapshotStore.appGroup())
        let result = await service.load()
        let now = Date()
        let currency = configuration.currencyOption.resolve(default: settings.currency)
        let entries = RefreshPolicy.entryDates(now: now, fetchedAt: result.snapshot?.fetchedAt).map {
            SnapshotEntry(date: $0, snapshot: result.snapshot, source: result.source, currency: currency, metric: configuration.lockMetric)
        }
        return Timeline(entries: entries, policy: .after(RefreshPolicy.nextReload(for: result, now: now)))
    }
}
