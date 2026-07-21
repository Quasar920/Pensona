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
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            AASplit.self, AASettlement.self, RepaymentReminder.self
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
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, bookID: book.id,
            systemLocalizationKey: "category.expense.food",
            iconSource: .userUploaded,
            placeholderResourceName: "category-placeholder-food",
            userIconRelativePath: "category-icons/food.png"
        )
        context.insert(book); context.insert(account); context.insert(wallet); context.insert(category)
        let expense = try LedgerService(context: context).createExpense(
            bookID: book.id, amount: 20, wallet: wallet, category: category, date: .now, note: "午餐"
        )
        let split = try AASplitService(context: context).upsert(
            AASplitDraft(
                otherPeopleCount: 1,
                calculationMode: .equal,
                othersOwedAmount: 10,
                note: "同事午餐",
                basedOnAmount: 20
            ),
            for: expense
        )
        _ = try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 4,
            wallet: wallet,
            date: .now,
            note: "部分收款"
        )
        let goal = SavingsGoal(bookID: book.id, name: "旅行", targetAmount: 1_000, currencyCode: "CNY")
        context.insert(goal)
        context.insert(SavingsAllocation(amount: 100, goal: goal))
        let reminder = RepaymentReminder(
            accountID: account.id,
            currencyCode: "CNY",
            outstandingAmount: 88,
            dueDate: .now.addingTimeInterval(86_400)
        )
        context.insert(reminder)
        try context.save()

        let sourceStore = AttachmentStore(rootURL: temporaryFolder("source"))
        let iconURL = try sourceStore.url(for: "category-icons/food.png")
        try FileManager.default.createDirectory(
            at: iconURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let iconData = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        try iconData.write(to: iconURL)
        let data = try BackupService.encode(BackupService.makeDocument(
            context: context,
            baseCurrencyCode: "CNY",
            attachmentStore: sourceStore
        ))
        let preview = try BackupService.preview(data: data)
        XCTAssertEqual(preview.transactionCount, 2)
        XCTAssertEqual(preview.bookCount, 1)

        try LedgerService(context: context).deleteTransactions(
            try context.fetch(FetchDescriptor<LedgerTransaction>())
        )
        XCTAssertEqual(wallet.balance, 100)

        let restoredStore = AttachmentStore(rootURL: temporaryFolder("restored"))
        let result = try BackupService.restore(
            data: data,
            context: context,
            currentBaseCurrencyCode: "USD",
            attachmentStore: restoredStore
        )

        XCTAssertEqual(result.settings.baseCurrencyCode, "CNY")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CurrencyWallet>()).first?.balance, 84)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AASplit>()).first?.othersOwedAmount, 10)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AASettlement>()).first?.amount, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavingsAllocation>()).first?.goal?.name, "旅行")
        let restoredCategory = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerCategory>()).first)
        XCTAssertEqual(restoredCategory.systemLocalizationKey, "category.expense.food")
        XCTAssertEqual(restoredCategory.iconSource, .userUploaded)
        XCTAssertEqual(
            try Data(contentsOf: restoredStore.url(for: "category-icons/food.png")),
            iconData
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<RepaymentReminder>()).first?.outstandingAmount, 88)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).allSatisfy { $0.bookID == book.id })
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

    func testVersionSixBackupInfersTransactionBookFromLegacyAccount() throws {
        let book = LedgerBook(name: "旧账本")
        let account = Account(name: "旧账户", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        context.insert(book); context.insert(account); context.insert(wallet)
        _ = try LedgerService(context: context).createExpense(
            bookID: book.id, amount: 10, wallet: wallet, category: nil, date: .now, note: nil
        )
        var document = try BackupService.makeDocument(context: context, baseCurrencyCode: "CNY")
        document.version = 6
        document.transactions = document.transactions.map {
            var value = $0
            value.bookID = nil
            value.reimbursementStatus = nil
            return value
        }

        _ = try BackupService.restore(
            data: BackupService.encode(document),
            context: context,
            currentBaseCurrencyCode: "CNY",
            attachmentStore: AttachmentStore(rootURL: temporaryFolder("legacy-restored"))
        )

        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerTransaction>()).first)
        XCTAssertEqual(restored.bookID, book.id)
        XCTAssertEqual(restored.reimbursementStatus, .none)
    }

    func testCategoryIconBackupRejectsUnsafeRelativePathBeforeDeletingData() throws {
        let book = LedgerBook(name: "日常")
        let category = LedgerCategory(
            name: "自定义", type: .expense, symbolName: "star", sortOrder: 0,
            iconSource: .userUploaded, userIconRelativePath: "../secret.png"
        )
        context.insert(book); context.insert(category)
        try context.save()
        let originalBookCount = try context.fetchCount(FetchDescriptor<LedgerBook>())
        let document = try BackupService.makeDocument(
            context: context,
            baseCurrencyCode: "CNY",
            attachmentStore: AttachmentStore(rootURL: temporaryFolder("unsafe"))
        )

        XCTAssertThrowsError(try BackupService.restore(
            data: BackupService.encode(document),
            context: context,
            currentBaseCurrencyCode: "CNY",
            attachmentStore: AttachmentStore(rootURL: temporaryFolder("unsafe-restored"))
        )) { error in
            XCTAssertEqual(error as? BackupServiceError, .unsafeAttachmentPath)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerBook>()), originalBookCount)
    }

    func testMissingCategoryIconFileProducesWarningAndRestoresWithoutDataLoss() throws {
        let book = LedgerBook(name: "日常")
        let category = LedgerCategory(
            name: "自定义", type: .expense, symbolName: "star", sortOrder: 0,
            iconSource: .userUploaded, userIconRelativePath: "category-icons/missing.png"
        )
        context.insert(book); context.insert(category)
        try context.save()

        let sourceStore = AttachmentStore(rootURL: temporaryFolder("missing-icon-source"))
        let document = try BackupService.makeDocument(
            context: context,
            baseCurrencyCode: "CNY",
            attachmentStore: sourceStore
        )
        let data = try BackupService.encode(document)
        let preview = try BackupService.preview(data: data)
        XCTAssertTrue(preview.warnings.contains { $0.contains("分类图标") })

        let result = try BackupService.restore(
            data: data,
            context: context,
            currentBaseCurrencyCode: "CNY",
            attachmentStore: AttachmentStore(rootURL: temporaryFolder("missing-icon-restored"))
        )
        XCTAssertTrue(result.warnings.contains { $0.contains("分类图标") })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerCategory>()), 1)
    }

    private func temporaryFolder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupServiceTests-\(name)-\(UUID())", isDirectory: true)
    }
}
