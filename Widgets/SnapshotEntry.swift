import Foundation
import WidgetKit
import BitcoinKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: BitcoinSnapshot?
    let source: SnapshotResult.Source
    let currency: Currency
    var metric: LockMetric = .price

    /// True once the shown data is older than RefreshPolicy.staleThreshold at this entry's date.
    var isStale: Bool { snapshot?.isStale(now: date) ?? false }

    static func preview(
        _ snapshot: BitcoinSnapshot? = .sample(),
        source: SnapshotResult.Source = .live,
        currency: Currency = .eur,
        metric: LockMetric = .price,
        date: Date = .now
    ) -> SnapshotEntry {
        SnapshotEntry(date: date, snapshot: snapshot, source: source, currency: currency, metric: metric)
    }

    /// Cached snapshot fetched an hour ago, shown now: renders the stale label.
    static var stalePreview: SnapshotEntry {
        preview(.sample(fetchedAt: .now.addingTimeInterval(-3600)), source: .cache)
    }

    static var emptyPreview: SnapshotEntry { preview(nil, source: .none) }
}
