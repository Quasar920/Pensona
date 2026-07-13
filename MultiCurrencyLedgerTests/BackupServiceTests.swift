import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class BackupServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionAttachment.self,
            TransactionTemplate.self, TransactionPaymentPart.self, TransactionRelation.self,
            RecurringSchedule.self, RecurringOccurrence.self, InstallmentPlan.self,
            InstallmentOccurrence.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self, SavingsGoal.self, SavingsAllocation.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testFullSnapshotRoundTripRestoresBalancesAndRelationships() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let category = LedgerCategory(
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, bookID: book.id
        )
        context.insert(book); context.insert(account); context.insert(wallet); context.insert(category)
        _ = try LedgerService(context: context).createExpense(
            amount: 20, wallet: wallet, category: category, date: .now, note: "午餐"
        )
        let goal = SavingsGoal(bookID: book.id, name: "旅行", targetAmount: 1_000, currencyCode: "CNY")
        context.insert(goal)
        context.insert(SavingsAllocation(amount: 100, goal: goal))
        try context.save()

        let data = try BackupService.encode(BackupService.makeDocument(
            context: context,
            baseCurrencyCode: "CNY",
            attachmentStore: AttachmentStore(rootURL: temporaryFolder("source"))
        ))
        let preview = try BackupService.preview(data: data)
        XCTAssertEqual(preview.transactionCount, 1)
        XCTAssertEqual(preview.bookCount, 1)

        try LedgerService(context: context).deleteTransactions(
            try context.fetch(FetchDescriptor<LedgerTransaction>())
        )
        XCTAssertEqual(wallet.balance, 100)

        let result = try BackupService.restore(
            data: data,
            context: context,
            currentBaseCurrencyCode: "USD",
            attachmentStore: AttachmentStore(rootURL: temporaryFolder("restored"))
        )

        XCTAssertEqual(result.settings.baseCurrencyCode, "CNY")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CurrencyWallet>()).first?.balance, 80)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavingsAllocation>()).first?.goal?.name, "旅行")
    }

    func testPreviewRejectsNewerBackupVersion() throws {
        let document = LedgerBackupDocument(
            version: LedgerBackupDocument.currentVersion + 1,
            settings: BackupSettings(baseCurrencyCode: "CNY"),
            books: [], accounts: [], wallets: [], categories: [], tags: [], transactions: [],
            relations: [], attachments: [], templates: [], recurringSchedules: [], recurringOccurrences: [],
            installmentPlans: [], installmentOccurrences: [], recognitionRecords: [], exchangeRates: [],
            budgets: [], savingsGoals: [], savingsAllocations: [], importBatches: [], importFingerprints: []
        )
        XCTAssertThrowsError(try BackupService.preview(data: BackupService.encode(document)))
    }

    private func temporaryFolder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupServiceTests-\(name)-\(UUID())", isDirectory: true)
    }
}
