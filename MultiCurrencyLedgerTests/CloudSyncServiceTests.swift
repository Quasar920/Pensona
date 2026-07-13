import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class CloudSyncServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionAttachment.self,
            TransactionTemplate.self, TransactionPaymentPart.self, TransactionRelation.self,
            RecurringSchedule.self, RecurringOccurrence.self, InstallmentPlan.self,
            InstallmentOccurrence.self, RecognitionImportRecord.self, ExchangeRate.self,
            MonthlyBudget.self, SavingsGoal.self, SavingsAllocation.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            CloudSyncTombstone.self, CloudSyncConflictCopy.self
        ])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        defaults = UserDefaults(suiteName: "CloudSyncServiceTests-\(UUID())")!
    }

    func testUploadNoChangeDeletionTombstoneAndConflictCopy() async throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, bookID: book.id)
        context.insert(book); context.insert(account); context.insert(wallet); context.insert(category)
        let transaction = try LedgerService(context: context).createExpense(
            amount: 20, wallet: wallet, category: category, date: .now, note: nil
        )

        let transport = FakeCloudTransport()
        let service = CloudSyncService(transport: transport, defaults: defaults)
        let first = try await service.synchronize(context: context, baseCurrencyCode: "CNY")
        XCTAssertEqual(first, .uploaded)
        let unchanged = try await service.synchronize(context: context, baseCurrencyCode: "CNY")
        XCTAssertEqual(unchanged, .noChanges)

        try LedgerService(context: context).deleteTransaction(transaction)
        let deletionUpload = try await service.synchronize(context: context, baseCurrencyCode: "CNY")
        XCTAssertEqual(deletionUpload, .uploaded)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncTombstone>()).contains {
            $0.entityType == "transaction" && $0.entityID == transaction.id
        })

        account.name = "本机现金"
        account.updatedAt = .now
        try context.save()
        try transport.simulateRemoteEdit()

        let conflict = try await service.synchronize(context: context, baseCurrencyCode: "CNY")
        XCTAssertEqual(conflict, .conflictCreated)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflictCopy>()), 1)
        XCTAssertEqual(account.name, "本机现金")
    }
}

private final class FakeCloudTransport: CloudSnapshotTransport {
    private var snapshot: CloudSnapshot?
    private var counter = 0

    func accountAvailability() async -> CloudAccountAvailability { .available }

    func fetch() async throws -> CloudSnapshot? { snapshot }

    func save(
        payloadData: Data,
        payload: CloudSyncPayload,
        expectedChangeTag: String?
    ) async throws -> CloudSnapshot {
        if let expectedChangeTag, expectedChangeTag != snapshot?.changeTag {
            throw CloudSnapshotTransportError.remoteChanged
        }
        counter += 1
        let value = CloudSnapshot(
            payloadData: payloadData, revision: payload.revision, deviceID: payload.deviceID,
            semanticHash: payload.semanticHash, modifiedAt: .now, changeTag: "tag-\(counter)"
        )
        snapshot = value
        return value
    }

    func delete() async throws { snapshot = nil }

    func simulateRemoteEdit() throws {
        guard let snapshot else { return }
        let original = try JSONDecoder().decode(CloudSyncPayload.self, from: snapshot.payloadData)
        let changed = CloudSyncPayload(
            revision: "remote-\(UUID())", deviceID: "other-device", createdAt: .now,
            semanticHash: "remote-changed-\(UUID())", backupData: original.backupData,
            manifest: original.manifest, tombstones: original.tombstones
        )
        counter += 1
        self.snapshot = CloudSnapshot(
            payloadData: try JSONEncoder().encode(changed), revision: changed.revision,
            deviceID: changed.deviceID, semanticHash: changed.semanticHash,
            modifiedAt: .now, changeTag: "tag-\(counter)"
        )
    }
}
