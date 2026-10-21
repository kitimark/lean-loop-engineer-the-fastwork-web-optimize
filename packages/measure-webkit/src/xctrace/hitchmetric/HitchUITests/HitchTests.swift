import XCTest

// xctrace-ci-probe, method 3: does XCTHitchMetric (Xcode 27.1 SDK, iOS 26.0+) report a number when it targets Mobile Safari in the
// iOS Simulator on a GitHub macOS runner? The page is opened before the test by `xcrun simctl openurl`; the test only swipes.
// Zone A is the first screen of the page (swipe from the top); zone B is the last screen (swipe up from one screen above the end).
// XCTClockMetric rides along as a control: if it reports and the hitch metric does not, the harness records metrics and only hitches are missing.
// Each measured block swipes once, slowly, then undoes the swipe outside the measured part (manual start/stop).
final class HitchTests: XCTestCase {
    private let safariId = "com.apple.mobilesafari"

    override func setUpWithError() throws { continueAfterFailure = false }

    private func safari() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: safariId)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "Safari did not come to the foreground")
        return app
    }

    private func options() -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = 3
        o.invocationOptions = [.manuallyStart, .manuallyStop] // stopMeasuring() is an error in the default autoStop mode
        return o
    }

    func testZoneA_heroExit() throws {
        let app = safari()
        for _ in 0..<6 { app.swipeDown(velocity: .fast) } // to the top
        measure(metrics: [XCTClockMetric(), XCTHitchMetric(application: app)], options: options()) {
            self.startMeasuring()
            app.swipeUp(velocity: .slow)
            self.stopMeasuring()
            app.swipeDown(velocity: .slow)
        }
    }

    func testZoneB_endOfPage() throws {
        let app = safari()
        for _ in 0..<14 { app.swipeUp(velocity: .fast) } // to the end
        measure(metrics: [XCTClockMetric(), XCTHitchMetric(application: app)], options: options()) {
            app.swipeDown(velocity: .slow)
            self.startMeasuring()
            app.swipeUp(velocity: .slow)
            self.stopMeasuring()
        }
    }
}
