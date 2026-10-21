import SwiftUI

// Empty host app: an XCUITest bundle needs an application target to be built against. The test never drives it.
@main
struct HostApp: App {
    var body: some Scene {
        WindowGroup { Text("hitch probe host") }
    }
}
