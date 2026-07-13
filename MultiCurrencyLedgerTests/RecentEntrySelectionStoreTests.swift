import XCTest
@testable import MultiCurrencyLedger

final class RecentEntrySelectionStoreTests: XCTestCase {
    func testSelectionsAreIsolatedByBookAndTransactionKind() throws {
        let suite = "RecentEntrySelectionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentEntrySelectionStore(defaults: defaults)
        let firstBook = UUID()
        let secondBook = UUID()
        let expenseWallet = UUID()
        let incomeWallet = UUID()

        store.save(
            RecentEntrySelection(sourceWalletID: expenseWallet),
            bookID: firstBook,
            kind: .expense
        )
        store.save(
            RecentEntrySelection(sourceWalletID: incomeWallet),
            bookID: firstBook,
            kind: .income
        )

        XCTAssertEqual(store.selection(bookID: firstBook, kind: .expense).sourceWalletID, expenseWallet)
        XCTAssertEqual(store.selection(bookID: firstBook, kind: .income).sourceWalletID, incomeWallet)
        XCTAssertNil(store.selection(bookID: secondBook, kind: .expense).sourceWalletID)
    }
}
