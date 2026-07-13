import XCTest
@testable import MultiCurrencyLedger

final class AppLockServiceTests: XCTestCase {
    func testPasswordLifecycleUsesIsolatedKeychainItem() throws {
        let store = AppLockCredentialStore(service: "AppLockServiceTests.\(UUID())")
        XCTAssertFalse(store.hasCredential())

        try store.setPassword("123456")
        XCTAssertTrue(store.hasCredential())
        XCTAssertTrue(try store.verify("123456"))
        XCTAssertFalse(try store.verify("654321"))

        try store.setPassword("abcdef", currentPassword: "123456")
        XCTAssertFalse(try store.verify("123456"))
        XCTAssertTrue(try store.verify("abcdef"))

        try store.remove(currentPassword: "abcdef")
        XCTAssertFalse(store.hasCredential())
    }

    func testPasswordMustHaveAtLeastSixCharacters() {
        let store = AppLockCredentialStore(service: "AppLockServiceTests.\(UUID())")
        XCTAssertThrowsError(try store.setPassword("12345")) { error in
            XCTAssertEqual(error as? AppLockError, .passwordTooShort)
        }
    }
}
