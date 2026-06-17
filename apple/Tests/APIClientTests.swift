import Testing
@testable import AppName  // FILL IN: replace with your Xcode product module name

/// Trivial smoke test using Swift Testing (Xcode 16+, the @Test macro
/// successor to XCTest). Proves the test target is wired correctly
/// once you add this file to your `AppNameTests` target in Xcode.
///
/// Steps after `Step 4. Create the Xcode project`:
///   1. File → New → Target → Unit Testing Bundle (name it `AppNameTests`)
///   2. Drag this file into the new `AppNameTests` group
///   3. ⌘U to run
///
/// Replace as the data layer grows. For async / actor / network tests
/// see `all-ios-skills:swift-testing`.
struct APIClientTests {
    @Test func clientResolves() async {
        let client = await APIClient.shared
        // Touching the singleton inside an async context confirms the
        // actor is reachable. Real tests assert decoded shape from a
        // mocked URLSession (see swift-testing skill).
        _ = client
    }
}
