import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class ShortcutRecognitionImportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var book: LedgerBook!
    private var wallet: CurrencyWallet!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, RecognitionImportRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        book = LedgerBook(name: "Daily")
        let account = Account(name: "招商银行 1234", type: .bankCard, book: book)
        wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)
        try context.save()
    }

    func testShortcutJSONAndOCRCanAutoEnterWithoutAnyImageOrNetworkClient() throws {
        let json = RecognitionFixtures.all.first { $0.name == "cny-expense" }!.responseJSON
        let ocr = RecognitionFixtures.all.first { $0.name == "cny-expense" }!.ocrText

        let outcomes = try ShortcutRecognitionImportService(context: context).importResults(
            responseJSON: json,
            ocrText: ocr,
            book: book,
            allowIncomeAutoEntry: false,
            now: isoDate("2026-07-12T00:00:00Z")
        )

        XCTAssertEqual(outcomes.count, 1)
        guard case .autoEntered = outcomes[0] else { return XCTFail("Expected auto entry") }
        XCTAssertEqual(wallet.balance, 72)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LedgerTransaction>()).count, 1)
    }

    func testShortcutResultWithUnknownAccountCreatesConfirmationInsteadOfChangingBalance() throws {
        let fixture = RecognitionFixtures.all.first { $0.name == "unknown-account" }!

        let outcomes = try ShortcutRecognitionImportService(context: context).importResults(
            responseJSON: fixture.responseJSON,
            ocrText: fixture.ocrText,
            book: book,
            allowIncomeAutoEntry: false,
            now: isoDate("2026-07-12T00:00:00Z")
        )

        guard case .needsConfirmation = outcomes[0] else { return XCTFail("Expected confirmation") }
        XCTAssertEqual(wallet.balance, 100)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecognitionImportRecord>()).count, 1)
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
