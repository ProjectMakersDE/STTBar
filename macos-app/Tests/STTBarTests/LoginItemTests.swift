import XCTest
@testable import STTBar

final class LoginItemTests: XCTestCase {
    // SMAppService registration cannot run unsandboxed in CI; we only assert the
    // type surface compiles and `isEnabled` is readable without throwing.
    func testIsEnabledIsReadable() {
        _ = LoginItem.isEnabled
    }
}
