import SwiftData

enum AppModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema(versionedSchema: LedgerSchemaV1.self)
        let configuration = ModelConfiguration(
            nil,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .automatic,
            cloudKitDatabase: .none
        )
        _ = try PersistentStoreSnapshotService.prepareIfNeeded(storeURL: configuration.url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: LedgerMigrationPlan.self,
            configurations: configuration
        )
        PersistentStoreSnapshotService.markSchemaOpened()
        return container
    }
}
