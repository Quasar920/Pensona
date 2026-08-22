import Foundation
import SwiftData

enum AppModelContainer {
    @MainActor
    static func make() throws -> ModelContainer {
        let schema = Schema(versionedSchema: LedgerSchemaV4.self)
        #if PERFORMANCE_TESTING
        let isStoredInMemoryOnly = true
        #else
        let isStoredInMemoryOnly = ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1"
        #endif
        let configuration = ModelConfiguration(
            nil,
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            allowsSave: true,
            groupContainer: .automatic,
            cloudKitDatabase: .none
        )
        #if !PERFORMANCE_TESTING
        _ = try PersistentStoreSnapshotService.prepareIfNeeded(storeURL: configuration.url)
        #endif
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: LedgerMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            // SwiftData cannot stage a migration when a released schema reused
            // live model types whose checksum later changed. Core Data can still
            // infer this additive V2 -> V3 mapping directly from store metadata.
            container = try ModelContainer(for: schema, configurations: configuration)
        }
        _ = try DataScopeMigrationService(context: container.mainContext).migrateIfNeeded()
        #if !PERFORMANCE_TESTING
        PersistentStoreSnapshotService.markSchemaOpened()
        #endif
        return container
    }
}
