import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class LedgerSchemaMigrationTests: XCTestCase {
    func testDataScopeMigrationBackfillsEveryLegacyShapeAndIsIdempotent() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: LedgerSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let sourceBook = LedgerBook(name: "来源", sortOrder: 0)
        let destinationBook = LedgerBook(name: "目标", sortOrder: 1)
        let sourceAccount = Account(name: "来源账户", type: .cash, book: sourceBook)
        let destinationAccount = Account(name: "目标账户", type: .cash, book: destinationBook)
        let sourceWallet = CurrencyWallet(currency: .CNY, balance: 800, account: sourceAccount)
        let destinationWallet = CurrencyWallet(currency: .CNY, balance: 200, account: destinationAccount)
        let sourceOnly = LedgerTransaction(type: .expense, sourceAccount: sourceAccount, sourceWallet: sourceWallet)
        let destinationOnly = LedgerTransaction(
            type: .income, destinationAccount: destinationAccount, destinationWallet: destinationWallet
        )
        let accountless = LedgerTransaction(type: .expense)
        let crossBook = LedgerTransaction(
            type: .transfer,
            sourceAccount: sourceAccount,
            sourceWallet: sourceWallet,
            destinationAccount: destinationAccount,
            destinationWallet: destinationWallet
        )
        let systemCategory = LedgerCategory(
            name: "系统分类", type: .expense, symbolName: "circle", sortOrder: 0,
            isSystem: true, bookID: sourceBook.id
        )
        let customCategory = LedgerCategory(
            name: "自定义", type: .expense, symbolName: "star", sortOrder: 1,
            bookID: sourceBook.id, parentID: systemCategory.id
        )
        let goal = SavingsGoal(
            bookID: destinationBook.id,
            name: "旅行",
            targetAmount: 1_000,
            currencyCode: "CNY",
            isGloballyVisible: false
        )
        [sourceBook, destinationBook].forEach(context.insert)
        [sourceAccount, destinationAccount].forEach(context.insert)
        [sourceWallet, destinationWallet].forEach(context.insert)
        [sourceOnly, destinationOnly, accountless, crossBook].forEach(context.insert)
        [systemCategory, customCategory].forEach(context.insert)
        context.insert(goal)
        try context.save()

        let sourceBalance = sourceWallet.balance
        let destinationBalance = destinationWallet.balance
        let defaults = UserDefaults(suiteName: "DataScopeMigrationTests-\(UUID())")!
        let service = DataScopeMigrationService(context: context, defaults: defaults)
        let first = try service.migrateIfNeeded()

        XCTAssertTrue(first.didRun)
        XCTAssertEqual(first.backfilledTransactionCount, 4)
        XCTAssertEqual(first.crossBookTransferCount, 1)
        XCTAssertEqual(sourceOnly.bookID, sourceBook.id)
        XCTAssertEqual(destinationOnly.bookID, destinationBook.id)
        XCTAssertEqual(accountless.bookID, sourceBook.id)
        XCTAssertEqual(crossBook.bookID, sourceBook.id)
        XCTAssertEqual(sourceAccount.book?.id, sourceBook.id)
        XCTAssertNil(systemCategory.bookID)
        XCTAssertEqual(customCategory.bookID, sourceBook.id)
        XCTAssertEqual(customCategory.parentID, systemCategory.id)
        XCTAssertTrue(goal.isGloballyVisible)
        XCTAssertEqual(goal.bookID, destinationBook.id)
        XCTAssertEqual(sourceWallet.balance, sourceBalance)
        XCTAssertEqual(destinationWallet.balance, destinationBalance)
        XCTAssertTrue(defaults.bool(forKey: DataScopeMigrationService.completionKey))

        let second = try service.migrateIfNeeded()
        XCTAssertFalse(second.didRun)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerBook>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 4)
        XCTAssertEqual(sourceWallet.balance, sourceBalance)
        XCTAssertEqual(destinationWallet.balance, destinationBalance)
    }

    func testMigrationCreatesDefaultBookWhenStoreIsEmpty() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: LedgerSchemaV3.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let defaults = UserDefaults(suiteName: "DataScopeEmptyMigrationTests-\(UUID())")!
        let result = try DataScopeMigrationService(
            context: container.mainContext,
            defaults: defaults
        ).migrateIfNeeded()

        let books = try container.mainContext.fetch(FetchDescriptor<LedgerBook>())
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.name, "日常账本")
        XCTAssertEqual(result.defaultBookID, books.first?.id)
    }

    func testV2FileStoreMigratesToV3AndAddsReminderModel() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2-to-v3-\(UUID()).store")
        do {
            let oldSchema = Schema(versionedSchema: LedgerSchemaV2.self)
            let configuration = ModelConfiguration("V2", schema: oldSchema, url: storeURL)
            let oldContainer = try ModelContainer(for: oldSchema, configurations: configuration)
            let book = LedgerBook(name: "旧账本")
            let transaction = LedgerTransaction(type: .expense)
            oldContainer.mainContext.insert(book)
            oldContainer.mainContext.insert(transaction)
            try oldContainer.mainContext.save()
        }

        let currentSchema = Schema(versionedSchema: LedgerSchemaV3.self)
        let configuration = ModelConfiguration("V3", schema: currentSchema, url: storeURL)
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: LedgerMigrationPlan.self,
            configurations: configuration
        )
        let defaults = UserDefaults(suiteName: "V2ToV3DataScope-\(UUID())")!
        _ = try DataScopeMigrationService(context: migrated.mainContext, defaults: defaults).migrateIfNeeded()

        XCTAssertNotNil(try migrated.mainContext.fetch(FetchDescriptor<LedgerTransaction>()).first?.bookID)
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<RepaymentReminder>()), 0)
    }
}
