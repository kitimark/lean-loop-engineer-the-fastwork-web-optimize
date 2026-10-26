import XCTest

/// One long XCUITest run that does one finish cycle of DragTests.testFinish per request (task push-cycle-separate): a drag up past the end
/// (the morph panel opens), a drag down that closes it, a shorter drag down that scrolls back, each with the hold. The Node probe writes
/// `go-<n>` into FW_DIR and waits for `done-<n>` (`ok <ms of press 1> <ms of press 2> <ms of press 3>`); this test writes `ready` once Safari
/// is in front and stops on a `stop` file or after MAX_S seconds. One xcodebuild start per pass, so the time between two cycles is the
/// Node side's to set (a rest), not the start-up cost of a test run. The presses and their parameters equal testFinish; the page is
/// already near its end. Parameters: DIR, DRAG_PT, BACK_PT, VELOCITY, HOLD_MS, MAX_S; `go-<n>` holding `safari` takes the coordinates from
/// Safari's window, anything else from SpringBoard.
final class FinishServer: XCTestCase {
    private func number(_ key: String, _ fallback: Double) -> Double {
        Double(ProcessInfo.processInfo.environment["FW_" + key] ?? "") ?? fallback
    }

    func testServe() throws {
        let dir = ProcessInfo.processInfo.environment["FW_DIR"] ?? ""
        XCTAssertFalse(dir.isEmpty, "FW_DIR is not set")
        let dragPt = number("DRAG_PT", 480)
        let backPt = number("BACK_PT", 240)
        let velocity = number("VELOCITY", 150)
        let hold = number("HOLD_MS", 600) / 1000
        let maxSeconds = number("MAX_S", 2400)
        let files = FileManager.default
        func put(_ name: String, _ text: String) {
            files.createFile(atPath: dir + "/" + name, contents: text.data(using: .utf8))
        }

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.activate()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20 * number("WAIT_SCALE", 1)), "Safari is not in the foreground")
        let window = safari.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10 * number("WAIT_SCALE", 1)), "no Safari window")
        let height = window.frame.height
        XCTAssertGreaterThan(height, 0)
        let span = min(dragPt, height * 0.6) / height
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let gesture = XCUIGestureVelocity(rawValue: velocity)
        func points(_ target: String) -> (XCUICoordinate, XCUICoordinate, XCUICoordinate) {
            let base: XCUIElement = target == "safari" ? window : springboard
            return (base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)),
                    base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span)),
                    base.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78 - span + min(backPt, dragPt) / height)))
        }
        put("ready", String(describing: height))

        let started = Date()
        var next = 0
        while Date().timeIntervalSince(started) < maxSeconds && !files.fileExists(atPath: dir + "/stop") {
            let goFile = dir + "/go-\(next)"
            if files.fileExists(atPath: goFile) {
                let text = (try? String(contentsOfFile: goFile, encoding: .utf8)) ?? ""
                let (from, to, back) = points(text.trimmingCharacters(in: .whitespacesAndNewlines) == "safari" ? "safari" : "springboard")
                let t0 = Date()
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: gesture, thenHoldForDuration: hold)
                let t1 = Date()
                to.press(forDuration: 0.05, thenDragTo: from, withVelocity: gesture, thenHoldForDuration: hold)
                let t2 = Date()
                to.press(forDuration: 0.05, thenDragTo: back, withVelocity: gesture, thenHoldForDuration: hold)
                let t3 = Date()
                put("done-\(next)", "ok \(Int(t1.timeIntervalSince(t0) * 1000)) \(Int(t2.timeIntervalSince(t1) * 1000)) \(Int(t3.timeIntervalSince(t2) * 1000))")
                next += 1
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
}
