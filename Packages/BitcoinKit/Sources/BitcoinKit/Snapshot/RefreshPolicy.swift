import Foundation

public enum RefreshPolicy {
    public static let liveInterval: TimeInterval = 15 * 60
    public static let fallbackInterval: TimeInterval = 5 * 60
    public static let staleThreshold: TimeInterval = 30 * 60
    /// Several widgets reloading together share one network refresh within this window.
    public static let reuseWindow: TimeInterval = 60

    public static func nextReload(for source: SnapshotResult.Source, now: Date) -> Date {
        now.addingTimeInterval(source == .live ? liveInterval : fallbackInterval)
    }

    /// Live cadence only after a fully successful fetch; partial failures, cache and nothing retry sooner.
    public static func nextReload(for result: SnapshotResult, now: Date) -> Date {
        nextReload(for: result.source == .live && result.error == nil ? .live : .none, now: now)
    }

    /// Timeline entry dates: now, plus the moment the snapshot turns stale (so the
    /// "as of" label appears even if WidgetKit defers the next reload).
    public static func entryDates(now: Date, fetchedAt: Date?) -> [Date] {
        guard let fetchedAt else { return [now] }
        let staleAt = fetchedAt.addingTimeInterval(staleThreshold + 1)
        return staleAt > now ? [now, staleAt] : [now]
    }
}
