import XCTest

/// One long XCUITest run that swipes Mobile Safari on request: a swipe up, a hold, a swipe down, a hold (the end-of-page push of the
/// morph). The Node probe writes `go-<n>` into the directory FW_DIR (its text names the target, see below) and waits for `done-<n>`;
/// this test writes `ready` once Safari is in front and stops on a `stop` file or after MAX_S seconds. One xcodebuild start per job
/// instead of one per window. `done-<n>` holds `ok <up ms> <down ms>`: how long each press call took inside XCUITest.
/// Parameters arrive as TEST_RUNNER_FW_* variables: DIR, DRAG_PT (points per drag), VELOCITY (points per second), HOLD_MS, MAX_S.
///
/// Target. XCUITest resolves the element a coordinate belongs to before each synthesized event, and waits for that element's
/// application to be idle before and after the event (XCUIApplicationProcess pre-event and post-event quiescence, INFERRED from the driver log and framework strings, not read from source). `go-<n>` holding
/// `safari` takes the coordinates from Safari's window, so every press waits for Safari (a page that animates keeps it busy).
/// Holding `springboard` takes them from SpringBoard, which is idle while Safari is in front: the touch lands on the same screen
/// point and reaches Safari, but the wait is on SpringBoard. Any other text counts as `springboard`.
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
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let gesture = XCUIGestureVelocity(rawValue: velocity)
        func points(_ target: String) -> (XCUICoordinate, XCUICoordinate) {
            let base: XCUIElement = target == "safari" ? window : springboard
            return (base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)),
                    base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span)))
        }
        put("ready", String(describing: height))

        let started = Date()
        var next = 0
        while Date().timeIntervalSince(started) < maxSeconds && !files.fileExists(atPath: dir + "/stop") {
            let goFile = dir + "/go-\(next)"
            if files.fileExists(atPath: goFile) {
                let text = (try? String(contentsOfFile: goFile, encoding: .utf8)) ?? ""
                let (from, to) = points(text.trimmingCharacters(in: .whitespacesAndNewlines) == "safari" ? "safari" : "springboard")
                // finger moves up: the page is already at its end, the morph opens
                let t0 = Date()
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: gesture, thenHoldForDuration: hold)
                let t1 = Date()
                // finger moves down: the morph closes
                to.press(forDuration: 0.05, thenDragTo: from, withVelocity: gesture, thenHoldForDuration: hold)
                let t2 = Date()
                put("done-\(next)", "ok \(Int(t1.timeIntervalSince(t0) * 1000)) \(Int(t2.timeIntervalSince(t1) * 1000))")
                next += 1
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
}
