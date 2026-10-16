import XCTest

/// Scripted takes for the launch film. Not part of the app's tests: scripts/mac-capture.sh runs each one
/// while the Simulator screen is recorded. Gestures use fixed speeds so every run moves the same way,
/// and demo data (`-demoData YES`) keeps the numbers the same in every take.
final class CaptureTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = ["-appearance", "dark", "-demoData", "YES", "-feeTilesShowFiat", "NO"] + arguments
        app.launch()
    }

    private func wait(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    /// A finger drag between two points of the screen (0...1), at `velocity` points per second.
    /// `hold` 0 lifts the finger while moving, so iOS carries the scroll on with its own deceleration.
    private func drag(from: CGVector, to: CGVector, velocity: CGFloat, hold: TimeInterval = 0, press: TimeInterval = 0.05) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: from)
            .press(forDuration: press, thenDragTo: window.coordinate(withNormalizedOffset: to),
                   withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: hold)
    }

    private func tapIfPresent(_ label: String) {
        let button = app.buttons[label].firstMatch
        if button.waitForExistence(timeout: 2) { button.tap() }
    }

    /// Records the demo data and warms the chart caches, so the recorded takes never show a spinner.
    func test0WarmUp() {
        launch(["-selectedTab", "pulse"])
        wait(6)
        for category in ["favourites", "market", "fees", "mempool", "mining", "blocks"] {
            app.terminate()
            launch(["-selectedTab", "charts", "-chartsCategory", category])
            wait(5)
            for _ in 0..<4 {
                drag(from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.3), velocity: 1500)
                wait(3)
            }
        }
        app.terminate()
        launch(["-selectedTab", "charts", "-chartsCategory", "favourites"])
        wait(4)
        for period in ["24H", "1W", "1M", "1Y", "5Y"] { tapIfPresent(period); wait(3) }
    }

    /// Home: the heartbeat searches, then a new block arrives and the app celebrates it.
    func test1HomeBlockFound() {
        launch(["-selectedTab", "pulse", "-demoNewBlockAfter", "10"])
        wait(17)
    }

    /// Home: scroll down through fees, mempool and difficulty, then flick back to the top.
    func test2HomeScroll() {
        launch(["-selectedTab", "pulse"])
        wait(4)
        for _ in 0..<3 {
            drag(from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.42), velocity: 700)
            wait(2.4)
        }
        drag(from: CGVector(dx: 0.5, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.85), velocity: 2600)
        wait(3)
    }

    /// Charts: swipe sideways through the categories, then up through the mempool charts.
    func test3ChartsSwipe() {
        launch(["-selectedTab", "charts", "-chartsCategory", "favourites"])
        wait(4)
        for _ in 0..<3 {
            // Over the card's title, not the plot, so the swipe pages instead of scrubbing the chart.
            drag(from: CGVector(dx: 0.85, dy: 0.215), to: CGVector(dx: 0.2, dy: 0.215), velocity: 1400)
            wait(2.2)
        }
        for _ in 0..<2 {
            drag(from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.35), velocity: 1600)
            wait(2.2)
        }
    }

    /// Charts: switch the price chart's period, then scrub across it with a finger.
    func test4PriceScrub() {
        launch(["-selectedTab", "charts", "-chartsCategory", "favourites"])
        wait(4)
        tapIfPresent("1Y"); wait(2)
        tapIfPresent("5Y"); wait(2)
        drag(from: CGVector(dx: 0.12, dy: 0.6), to: CGVector(dx: 0.88, dy: 0.6), velocity: 260, hold: 0.8, press: 0.35)
        wait(1)
        drag(from: CGVector(dx: 0.88, dy: 0.6), to: CGVector(dx: 0.45, dy: 0.6), velocity: 200, hold: 0.8, press: 0.35)
        wait(2)
    }
}
