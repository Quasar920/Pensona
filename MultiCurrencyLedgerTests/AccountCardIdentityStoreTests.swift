import XCTest
@testable import MultiCurrencyLedger

final class AccountCardIdentityStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AccountCardIdentityStore!

    override func setUp() {
        super.setUp()
        suiteName = "AccountCardIdentityStoreTests-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
        store = AccountCardIdentityStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testStoresLeadingZeroAndBuildsMaskedNumber() throws {
        let accountID = UUID()
        try store.setLastFour("0012", for: accountID)

        XCTAssertEqual(store.lastFour(for: accountID), "0012")
        XCTAssertEqual(AccountCardIdentityStore.maskedNumber(lastFour: "0012"), "•••• •••• •••• 0012")
    }

    func testBlankValueRemovesStoredSuffix() throws {
        let accountID = UUID()
        try store.setLastFour("1234", for: accountID)
        try store.setLastFour("", for: accountID)

        XCTAssertNil(store.lastFour(for: accountID))
        XCTAssertEqual(AccountCardIdentityStore.maskedNumber(lastFour: nil), "•••• •••• •••• ••••")
    }

    func testRejectsIncompleteOrNonNumericSuffix() {
        XCTAssertThrowsError(try AccountCardIdentityStore.validated("123"))
        XCTAssertThrowsError(try AccountCardIdentityStore.validated("12A4"))
        XCTAssertThrowsError(try AccountCardIdentityStore.validated("12345"))
    }

    func testSanitizedInputKeepsOnlyFirstFourASCIIDigits() {
        XCTAssertEqual(AccountCardIdentityStore.sanitizedInput("1a23-456"), "1234")
    }
}
