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
        XCTAssertEqual(LedgerSchemaV1.versionIdentifier, .init(1, 0, 0))
        XCTAssertEqual(LedgerSchemaV1.models.count, 23)
        XCTAssertTrue(LedgerSchemaV1.models.contains { $0 == LedgerTransaction.self })
        XCTAssertTrue(LedgerSchemaV1.models.contains { $0 == CloudSyncConflictCopy.self })
    }
}
