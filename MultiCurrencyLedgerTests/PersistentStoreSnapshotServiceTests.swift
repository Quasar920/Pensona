import SwiftData
import XCTest
@testable import MultiCurrencyLedger

final class PersistentStoreSnapshotServiceTests: XCTestCase {
    func testPreMigrationSnapshotCanBeScheduledForNextLaunchRestore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistentStoreSnapshotServiceTests-\(UUID())", isDirectory: true)
        let stores = root.appendingPathComponent("Stores", isDirectory: true)
        let snapshots = root.appendingPathComponent("Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: stores, withIntermediateDirectories: true)
        let storeURL = stores.appendingPathComponent("default.store")
        try Data("before migration".utf8).write(to: storeURL)
        try Data("wal before migration".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        let defaults = UserDefaults(suiteName: "PersistentStoreSnapshotServiceTests-\(UUID())")!

        let snapshotURL = try XCTUnwrap(PersistentStoreSnapshotService.prepareIfNeeded(
            storeURL: storeURL,
            defaults: defaults,
            snapshotsRootURL: snapshots
        ))
        PersistentStoreSnapshotService.markSchemaOpened(defaults: defaults)
        try Data("after migration".utf8).write(to: storeURL)

        PersistentStoreSnapshotService.requestRestore(
            MigrationStoreSnapshot(directoryURL: snapshotURL, createdAt: .now),
            defaults: defaults
        )
        _ = try PersistentStoreSnapshotService.prepareIfNeeded(
            storeURL: storeURL,
            defaults: defaults,
            snapshotsRootURL: snapshots
        )

        XCTAssertEqual(try String(contentsOf: storeURL, encoding: .utf8), "before migration")
        XCTAssertNil(PersistentStoreSnapshotService.pendingRestore(defaults: defaults))
        XCTAssertGreaterThanOrEqual(PersistentStoreSnapshotService.snapshots(
            snapshotsRootURL: snapshots
        ).count, 2)
    }

    func testVersionedSchemaContainsEveryCurrentPersistentModel() {
        XCTAssertEqual(LedgerSchemaLegacy.versionIdentifier, .init(1, 0, 0))
        XCTAssertEqual(LedgerSchemaV1.versionIdentifier, .init(2, 0, 0))
        XCTAssertEqual(LedgerSchemaV2.versionIdentifier, .init(3, 0, 0))
        XCTAssertEqual(LedgerSchemaV3.versionIdentifier, .init(4, 0, 0))
        XCTAssertEqual(LedgerSchemaV4.versionIdentifier, .init(5, 0, 0))
        XCTAssertEqual(LedgerSchemaLegacy.models.count, 8)
        XCTAssertEqual(LedgerSchemaV1.models.count, 23)
        XCTAssertEqual(LedgerSchemaV2.models.count, 25)
        XCTAssertEqual(LedgerSchemaV3.models.count, 26)
        XCTAssertEqual(LedgerSchemaV4.models.count, 26)
        XCTAssertTrue(LedgerSchemaV4.models.contains { $0 == LedgerTransaction.self })
        XCTAssertTrue(LedgerSchemaV4.models.contains { $0 == CloudSyncConflictCopy.self })
        XCTAssertTrue(LedgerSchemaV4.models.contains { $0 == AASplit.self })
        XCTAssertTrue(LedgerSchemaV4.models.contains { $0 == AASettlement.self })
        XCTAssertTrue(LedgerSchemaV4.models.contains { $0 == RepaymentReminder.self })
    }

    @MainActor
    func testLegacyStoreMigratesToCurrentSchemaWithoutLosingLedgerData() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-migration-\(UUID()).store")
        try createLegacyStore(at: storeURL)

        let currentSchema = Schema(versionedSchema: LedgerSchemaV4.self)
        let configuration = ModelConfiguration(
            "MigrationTest",
            schema: currentSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let migrated = try ModelContainer(
            for: currentSchema,
            migrationPlan: LedgerMigrationPlan.self,
            configurations: configuration
        )
        let context = migrated.mainContext
        let defaults = UserDefaults(suiteName: "LegacyMigrationDataScope-\(UUID())")!
        _ = try DataScopeMigrationService(context: context, defaults: defaults).migrateIfNeeded()
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<Account>()).first)
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<LedgerTransaction>()).first)
        let budget = try XCTUnwrap(context.fetch(FetchDescriptor<MonthlyBudget>()).first)

        XCTAssertEqual(account.name, "旧现金")
        XCTAssertFalse(account.isArchived)
        XCTAssertEqual(transaction.amount, 20)
        XCTAssertTrue(transaction.tags.isEmpty)
        XCTAssertNotNil(transaction.bookID)
        XCTAssertEqual(budget.period, .monthly)
    }

    @MainActor
    private func createLegacyStore(at url: URL) throws {
        let schema = Schema(versionedSchema: LedgerSchemaLegacy.self)
        let configuration = ModelConfiguration(
            "LegacyMigrationTest",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let book = LedgerSchemaLegacy.LedgerBook(name: "旧账本")
        let account = LedgerSchemaLegacy.Account(name: "旧现金", typeRawValue: "cash", book: book)
        let wallet = LedgerSchemaLegacy.CurrencyWallet(currencyCode: "CNY", balance: 80, account: account)
        let category = LedgerSchemaLegacy.LedgerCategory(
            name: "餐饮", typeRawValue: "expense", symbolName: "fork.knife", sortOrder: 0
        )
        let transaction = LedgerSchemaLegacy.LedgerTransaction(typeRawValue: "expense")
        transaction.amount = 20
        transaction.currencyCode = "CNY"
        transaction.sourceAmount = 20
        transaction.sourceCurrencyCode = "CNY"
        transaction.sourceAccount = account
        transaction.sourceWallet = wallet
        transaction.category = category
        let budget = LedgerSchemaLegacy.MonthlyBudget(
            scopeKey: "legacy", bookID: book.id, monthStart: .now, currencyCode: "CNY", amount: 1_000
        )
        context.insert(book); context.insert(account); context.insert(wallet)
        context.insert(category); context.insert(transaction); context.insert(budget)
        try context.save()
    }
}
