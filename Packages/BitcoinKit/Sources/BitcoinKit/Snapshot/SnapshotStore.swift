import Foundation

public enum AppGroup {
    public static let identifier = "group.com.lazet.blockpulse"
}

/// Last good snapshot as JSON on disk (App Group container on iOS).
public struct SnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    /// Nil when missing or unreadable — a corrupt cache must never crash a widget.
    public func load() -> BitcoinSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(BitcoinSnapshot.self, from: data)
    }

    public func save(_ snapshot: BitcoinSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    #if canImport(Darwin)
    public static func appGroup(_ identifier: String = AppGroup.identifier) -> SnapshotStore? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return SnapshotStore(fileURL: container.appendingPathComponent("snapshot.json"))
    }
    #endif
}
