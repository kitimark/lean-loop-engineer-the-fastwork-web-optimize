import XCTest

/// Real touches on Mobile Safari: slow upward drags that collapse the toolbar, a hold, then the drags back. The page is
/// already open and recording (the Node probe reads the frames through the Web Inspector); this test only touches.
/// Parameters arrive as TEST_RUNNER_FW_* variables: CYCLES, DRAG_PT (points per drag), VELOCITY (points per second), HOLD_MS.
final class DragTests: XCTestCase {
    private func env(_ key: String, _ fallback: Double) -> Double {
        Double(ProcessInfo.processInfo.environment["FW_" + key] ?? "") ?? fallback
    }

    func testDrags() throws {
        let cycles = Int(env("CYCLES", 4))
        let dragPt = env("DRAG_PT", 360)
        let velocity = env("VELOCITY", 120)
        let hold = env("HOLD_MS", 600) / 1000

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "Safari is not in the foreground")
        let window = safari.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "no Safari window")
        let height = window.frame.height
        XCTAssertGreaterThan(height, 0)
        let span = min(dragPt, height * 0.6) / height
        let from = CGVector(dx: 0.5, dy: 0.78)
        let to = CGVector(dx: 0.5, dy: 0.78 - span)

        for _ in 0..<cycles {
            // finger moves up: the page scrolls down and the toolbar collapses
            window.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: to),
                       withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: hold)
            // finger moves down: the page scrolls back up and the toolbar returns
            window.coordinate(withNormalizedOffset: to)
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: from),
                       withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: hold)
        }
    }
}
