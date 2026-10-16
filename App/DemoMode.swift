import Foundation
import BitcoinKit

/// Launch options for marketing captures (scripts/mac-capture.sh). Everything here is off unless the
/// app is launched with `-demoData YES`; the widgets never use it.
///
/// - `-demoData YES`: replay saved mempool responses (recorded on first use) so every take shows the same numbers.
/// - `-demoNewBlockAfter 9`: hold the newest block back for 9 s after launch, then let it arrive, which plays
///   the real block-found flow on the home screen.
/// - `-demoAutoScroll 4`: 4 s after launch, glide the home screen to its end and back.
/// - `-demoStartCategory market`: open the Charts tab on that category. Unlike `-chartsCategory`, which
///   pins the category for the whole run, the category bar still follows swipes.
enum DemoMode {
    /// Set in `BlockpulseApp.init`, so "seconds after launch" counts from the launch.
    static let launchedAt = Date()

    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demoData") }

    static var autoScrollAfter: TimeInterval? {
        let seconds = UserDefaults.standard.double(forKey: "demoAutoScroll")
        return isOn && seconds > 0 ? seconds : nil
    }

    /// Called once at launch: stores the start category as if the user had picked it.
    static func applyLaunchOptions() {
        let defaults = UserDefaults.standard
        guard isOn, let category = defaults.string(forKey: "demoStartCategory") else { return }
        defaults.set(category, forKey: "chartsCategory")
    }

    static var newBlockAfter: TimeInterval? {
        let seconds = UserDefaults.standard.double(forKey: "demoNewBlockAfter")
        return isOn && seconds > 0 ? seconds : nil
    }

    /// Every app request goes through this; outside demo mode it is the normal network transport.
    static let transport: any HTTPTransport = {
        guard isOn else { return URLSessionTransport() }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return FixtureTransport(
            directory: caches.appendingPathComponent("demo-data"),
            newBlockAt: newBlockAfter.map { launchedAt.addingTimeInterval($0) }
        )
    }()

    /// While a new block is pending, refresh every second so it shows up the moment it is "found".
    static var liveInterval: Duration? { newBlockAfter == nil ? nil : .seconds(1) }
}
