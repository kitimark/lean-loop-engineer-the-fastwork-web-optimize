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

    /// Finish drags. The page is already near its end (the Node probe scrolled it). Each cycle: a drag up past the end, so the morph panel
    /// opens; a drag down that closes the panel (the site takes that whole gesture, the page stays); a shorter drag down that scrolls the
    /// page back and lets the toolbar return. FW_TARGET `springboard` (default) takes the screen coordinates from SpringBoard, which is idle
    /// while Safari is in front, so the waits around each press are not on the animating page; `safari` takes them from Safari's window.
    /// Parameters: CYCLES, DRAG_PT (points per drag), BACK_PT (points of the scroll-back drag), VELOCITY (points per second), HOLD_MS, TARGET.
    func testFinish() throws {
        let cycles = Int(env("CYCLES", 3))
        let dragPt = env("DRAG_PT", 480)
        let backPt = env("BACK_PT", 240)
        let velocity = env("VELOCITY", 150)
        let hold = env("HOLD_MS", 600) / 1000
        let target = ProcessInfo.processInfo.environment["FW_TARGET"] ?? "springboard"

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "Safari is not in the foreground")
        let window = safari.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "no Safari window")
        let height = window.frame.height
        XCTAssertGreaterThan(height, 0)
        let span = min(dragPt, height * 0.6) / height
        let base: XCUIElement = target == "safari" ? window : XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let from = base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let to = base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span))
        let back = base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span + min(backPt, dragPt) / height))
        let gesture = XCUIGestureVelocity(rawValue: velocity)

        for _ in 0..<cycles {
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: gesture, thenHoldForDuration: hold)
            to.press(forDuration: 0.05, thenDragTo: from, withVelocity: gesture, thenHoldForDuration: hold)
            to.press(forDuration: 0.05, thenDragTo: back, withVelocity: gesture, thenHoldForDuration: hold)
        }
    }
}
