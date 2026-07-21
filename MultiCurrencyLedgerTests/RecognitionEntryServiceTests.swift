import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RecognitionEntryServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var bookID: UUID { try! context.fetch(FetchDescriptor<LedgerBook>()).first!.id }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, RecognitionImportRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testConfirmCreatesTransactionUpdatesBalanceAndWritesSanitizedAuditRecord() throws {
        let (wallet, category) = try makeWalletAndCategory()
        let draft = makeDraft()

        let transaction = try RecognitionEntryService(context: context).confirm(
            draft, bookID: bookID, wallet: wallet, category: category
        )
        let records = try context.fetch(FetchDescriptor<RecognitionImportRecord>())

        XCTAssertEqual(wallet.balance, 915)
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.bookID, bookID)
        XCTAssertEqual(transaction.merchantOrCounterparty, "Coffee Shop")
        XCTAssertEqual(transaction.originalAmount, 100)
        XCTAssertEqual(transaction.discountAmount, 15)
        XCTAssertNotNil(transaction.recognitionImportID)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].transactionID, transaction.id)
        XCTAssertEqual(records[0].status, .confirmed)
        XCTAssertEqual(records[0].decisionReason, .accountUnmatched)
    }

    func testRejectsCurrencyMismatchWithoutWritingAnythingOrChangingBalance() throws {
        let (wallet, category) = try makeWalletAndCategory()
        var draft = makeDraft()
        draft.currency = .USD

        XCTAssertThrowsError(try RecognitionEntryService(context: context).confirm(
            draft, bookID: bookID, wallet: wallet, category: category
        )) { error in
            XCTAssertEqual(error as? RecognitionEntryError, .walletCurrencyMismatch)
        }
        XCTAssertEqual(wallet.balance, 1_000)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RecognitionImportRecord>()).isEmpty)
    }

    func testRejectsFeeAndTransferWithoutWritingAnythingOrChangingBalance() throws {
        let (wallet, category) = try makeWalletAndCategory()
        var feeDraft = makeDraft()
        feeDraft.feeAmount = 1
        XCTAssertThrowsError(try RecognitionEntryService(context: context).confirm(
            feeDraft, bookID: bookID, wallet: wallet, category: category
        )) { XCTAssertEqual($0 as? RecognitionEntryError, .feeRequiresManualEntry) }

        var transferDraft = makeDraft()
        transferDraft.type = .transfer
        XCTAssertThrowsError(try RecognitionEntryService(context: context).confirm(
            transferDraft, bookID: bookID, wallet: wallet, category: category
        )) { XCTAssertEqual($0 as? RecognitionEntryError, .unsupportedType) }

        XCTAssertEqual(wallet.balance, 1_000)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RecognitionImportRecord>()).isEmpty)
    }

    private func makeWalletAndCategory() throws -> (CurrencyWallet, LedgerCategory) {
        let book = LedgerBook(name: "Daily")
        let account = Account(name: "Cash", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 1_000, account: account)
        let category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)
        try context.save()
        return (wallet, category)
    }

    private func makeDraft() -> RecognitionConfirmationDraft {
        RecognitionConfirmationDraft(
            type: .expense,
            paidAmount: 85,
            currency: .CNY,
            occurredAt: .now,
            merchantOrCounterparty: "Coffee Shop",
            note: "午餐",
            originalAmount: 100,
            discountAmount: 15,
            feeAmount: 0,
            decisionReason: .accountUnmatched
        )
    }
}
