import XCTest

/// One long XCUITest run that swipes Mobile Safari on request: a swipe up, a hold, a swipe down, a hold (the end-of-page push of the
/// morph). The Node probe writes `go-<n>` into the directory FW_DIR and waits for `done-<n>`; this test writes `ready` once Safari is
/// in front and stops on a `stop` file or after MAX_S seconds. One xcodebuild start per job instead of one per window.
/// Parameters arrive as TEST_RUNNER_FW_* variables: DIR, DRAG_PT (points per drag), VELOCITY (points per second), HOLD_MS, MAX_S.
final class PushServer: XCTestCase {
    private func number(_ key: String, _ fallback: Double) -> Double {
        Double(ProcessInfo.processInfo.environment["FW_" + key] ?? "") ?? fallback
    }

    func testServe() throws {
        let dir = ProcessInfo.processInfo.environment["FW_DIR"] ?? ""
        XCTAssertFalse(dir.isEmpty, "FW_DIR is not set")
        let dragPt = number("DRAG_PT", 300)
        let velocity = number("VELOCITY", 600)
        let hold = number("HOLD_MS", 1000) / 1000
        let maxSeconds = number("MAX_S", 2400)
        let files = FileManager.default
        func put(_ name: String, _ text: String) {
            files.createFile(atPath: dir + "/" + name, contents: text.data(using: .utf8))
        }

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "Safari is not in the foreground")
        let window = safari.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "no Safari window")
        let height = window.frame.height
        XCTAssertGreaterThan(height, 0)
        let span = min(dragPt, height * 0.6) / height
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span))
        let gesture = XCUIGestureVelocity(rawValue: velocity)
        put("ready", String(describing: height))

        let started = Date()
        var next = 0
        while Date().timeIntervalSince(started) < maxSeconds && !files.fileExists(atPath: dir + "/stop") {
            if files.fileExists(atPath: dir + "/go-\(next)") {
                // finger moves up: the page is already at its end, the morph opens
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: gesture, thenHoldForDuration: hold)
                // finger moves down: the morph closes
                to.press(forDuration: 0.05, thenDragTo: from, withVelocity: gesture, thenHoldForDuration: hold)
                put("done-\(next)", "ok")
                next += 1
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
}
