import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RecognitionWorkflowServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var book: LedgerBook!
    private var wallet: CurrencyWallet!
    private var category: LedgerCategory!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, RecognitionImportRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        book = LedgerBook(name: "Daily")
        let account = Account(name: "Cash", type: .cash, book: book)
        wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)
        try context.save()
    }

    func testAutoEligibleDecisionWritesOnceThroughSafeEntryService() throws {
        let decision = RecognitionDecision.autoEligible(walletID: wallet.id, candidate: candidate())
        let service = RecognitionWorkflowService(context: context)

        let outcome = try service.apply(decision, in: book)

        guard case let .autoEntered(transactionID) = outcome else {
            return XCTFail("Expected auto entry")
        }
        XCTAssertEqual(wallet.balance, 15)
        let records = try context.fetch(FetchDescriptor<RecognitionImportRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].transactionID, transactionID)
        XCTAssertEqual(records[0].status, .autoEntered)
    }

    func testSameTransactionFingerprintIsBlockedBeforeAnySecondBalanceChange() throws {
        let decision = RecognitionDecision.autoEligible(walletID: wallet.id, candidate: candidate())
        let service = RecognitionWorkflowService(context: context)
        _ = try service.apply(decision, in: book)

        let outcome = try service.apply(decision, in: book)

        guard case let .duplicate(recordID) = outcome else {
            return XCTFail("Expected duplicate")
        }
        XCTAssertEqual(wallet.balance, 15)
        let records = try context.fetch(FetchDescriptor<RecognitionImportRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].id, recordID)
    }

    func testConfirmationDecisionPersistsDraftButDoesNotChangeBalance() throws {
        let decision = RecognitionDecision.needsConfirmation(reason: .accountUnmatched, candidate: candidate())

        let outcome = try RecognitionWorkflowService(context: context).apply(decision, in: book)

        guard case let .needsConfirmation(recordID) = outcome else {
            return XCTFail("Expected confirmation")
        }
        XCTAssertEqual(wallet.balance, 100)
        let records = try context.fetch(FetchDescriptor<RecognitionImportRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].id, recordID)
        XCTAssertEqual(records[0].status, .pendingConfirmation)
        XCTAssertEqual(records[0].sourceAccountHint, "Unknown wallet")
        XCTAssertEqual(records[0].confirmationDraft?.paidAmount, 85)
    }

    private func candidate() -> NormalizedRecognitionCandidate {
        NormalizedRecognitionCandidate(
            type: .expense,
            paidAmount: 85,
            originalAmount: 100,
            discountAmount: 15,
            feeAmount: 0,
            currency: .CNY,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            merchantOrCounterparty: "Coffee Shop",
            sourceAccountHint: "Unknown wallet",
            destinationAccountHint: nil,
            categoryCandidate: "餐饮",
            note: "Lunch",
            confidence: RecognitionConfidenceDTO(type: 1, paidAmount: 1, currencyCode: 1, account: 1, category: 1)
        )
    }
}
