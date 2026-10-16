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

    /// Home: one slow scroll from the top to the end of the page, then a flick back to the top.
    /// The page is only about 400 points taller than the screen: more scrolling hits the end and bounces.
    func test2HomeScroll() {
        launch(["-selectedTab", "pulse"])
        wait(4)
        // The finger stops before lifting (hold), so the page glides at an even speed and doesn't fling past the end.
        drag(from: CGVector(dx: 0.5, dy: 0.8), to: CGVector(dx: 0.5, dy: 0.36), velocity: 320, hold: 0.3)
        wait(2.5)
        drag(from: CGVector(dx: 0.5, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.85), velocity: 2600)
        wait(3)
    }

    /// Charts: swipe sideways from Market through Fees and Mempool to Mining, then up through the mining charts.
    /// Runs twice: the first pass draws every chart once, so the second (the one to use) has no first-draw hitches.
    /// Nothing is tapped in the category bar: it scrolls along with the swipes, so a chip can be off screen.
    func test3ChartsSwipe() {
        // -demoStartCategory, not -chartsCategory: a launch argument would pin the bar on top while the pages move.
        launch(["-selectedTab", "charts", "-demoStartCategory", "market"])
        wait(3)
        let left = (CGVector(dx: 0.85, dy: 0.215), CGVector(dx: 0.2, dy: 0.215))
        let up = (CGVector(dx: 0.5, dy: 0.78), CGVector(dx: 0.5, dy: 0.35))
        for pass in 0..<2 {
            let pause = pass == 0 ? 1.5 : 2.2
            // Over the card's title, not the plot, so the swipe pages instead of scrubbing the chart.
            for _ in 0..<3 { drag(from: left.0, to: left.1, velocity: 1400); wait(pause) }
            for _ in 0..<2 { drag(from: up.0, to: up.1, velocity: 1600); wait(pause) }
            if pass == 0 {
                // Back to Mining's first chart and then to Market, for the pass that counts.
                for _ in 0..<2 { drag(from: up.1, to: up.0, velocity: 1600); wait(1.2) }
                for _ in 0..<3 { drag(from: left.1, to: left.0, velocity: 1400); wait(1.2) }
                wait(1.5)
            }
        }
    }

    /// Charts: switch the price chart's period, then scrub across it with a finger, slowly enough to read.
    /// Both drags start inside the plot (it ends at about 0.84): from the axis labels a drag pages instead.
    func test4PriceScrub() {
        launch(["-selectedTab", "charts", "-chartsCategory", "favourites"])
        wait(4)
        tapIfPresent("1Y"); wait(2.5)
        drag(from: CGVector(dx: 0.1, dy: 0.6), to: CGVector(dx: 0.8, dy: 0.6), velocity: 140, hold: 0.8, press: 0.5)
        wait(1.5)
        drag(from: CGVector(dx: 0.8, dy: 0.6), to: CGVector(dx: 0.35, dy: 0.6), velocity: 120, hold: 0.8, press: 0.5)
        wait(2)
    }
}
