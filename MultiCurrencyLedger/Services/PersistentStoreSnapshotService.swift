import Foundation

struct MigrationStoreSnapshot: Identifiable {
    let directoryURL: URL
    let createdAt: Date
    var id: String { directoryURL.path }
    var title: String {
        createdAt.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}

enum PersistentStoreSnapshotError: LocalizedError, Equatable {
    case unsafeSnapshot
    case emptySnapshot

    var errorDescription: String? {
        switch self {
        case .unsafeSnapshot: AppLocalization.string( "恢复快照不在 App 的受控目录中")
        case .emptySnapshot: AppLocalization.string( "快照中没有可恢复的数据库文件")
        }
    }
}

enum PersistentStoreSnapshotService {
    static let schemaVersion = "4.1.0-foreign-card-settlement"
    static let pendingRestoreKey = "pendingMigrationStoreRestorePath"
    private static let preparedVersionKey = "preparedPersistentSchemaVersion"

    static func prepareIfNeeded(
        storeURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        snapshotsRootURL: URL? = nil
    ) throws -> URL? {
        let root = snapshotsRootURL ?? snapshotsRoot(fileManager: fileManager)
        try applyPendingRestore(storeURL: storeURL, defaults: defaults, fileManager: fileManager, root: root)
        guard defaults.string(forKey: preparedVersionKey) != schemaVersion,
              storeFiles(for: storeURL, fileManager: fileManager).isEmpty == false else { return nil }
        let directory = try newSnapshotDirectory(prefix: "pre-migration", fileManager: fileManager, root: root)
        for source in storeFiles(for: storeURL, fileManager: fileManager) {
            try fileManager.copyItem(at: source, to: directory.appendingPathComponent(source.lastPathComponent))
        }
        try pruneSnapshots(keeping: 5, fileManager: fileManager, root: root)
        return directory
    }

    static func markSchemaOpened(defaults: UserDefaults = .standard) {
        defaults.set(schemaVersion, forKey: preparedVersionKey)
    }

    static func snapshots(
        fileManager: FileManager = .default,
        snapshotsRootURL: URL? = nil
    ) -> [MigrationStoreSnapshot] {
        let root = snapshotsRootURL ?? snapshotsRoot(fileManager: fileManager)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            return MigrationStoreSnapshot(directoryURL: url, createdAt: values?.creationDate ?? .distantPast)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    static func requestRestore(_ snapshot: MigrationStoreSnapshot, defaults: UserDefaults = .standard) {
        defaults.set(snapshot.directoryURL.path, forKey: pendingRestoreKey)
    }

    static func cancelPendingRestore(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingRestoreKey)
    }

    static func pendingRestore(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: pendingRestoreKey)
    }

    private static func applyPendingRestore(
        storeURL: URL,
        defaults: UserDefaults,
        fileManager: FileManager,
        root: URL
    ) throws {
        guard let path = defaults.string(forKey: pendingRestoreKey) else { return }
        let sourceDirectory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let safeRoot = root.standardizedFileURL
        guard sourceDirectory.path.hasPrefix(safeRoot.path + "/") else {
            defaults.removeObject(forKey: pendingRestoreKey)
            throw PersistentStoreSnapshotError.unsafeSnapshot
        }
        let sources = (try? fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.lastPathComponent.hasPrefix(storeURL.lastPathComponent) } ?? []
        guard !sources.isEmpty else { throw PersistentStoreSnapshotError.emptySnapshot }

        if !storeFiles(for: storeURL, fileManager: fileManager).isEmpty {
            let emergency = try newSnapshotDirectory(
                prefix: "pre-restore", fileManager: fileManager, root: safeRoot
            )
            for source in storeFiles(for: storeURL, fileManager: fileManager) {
                try fileManager.copyItem(at: source, to: emergency.appendingPathComponent(source.lastPathComponent))
            }
        }
        for current in storeFiles(for: storeURL, fileManager: fileManager) {
            try fileManager.removeItem(at: current)
        }
        for source in sources {
            try fileManager.copyItem(at: source, to: storeURL.deletingLastPathComponent().appendingPathComponent(source.lastPathComponent))
        }
        defaults.removeObject(forKey: pendingRestoreKey)
        defaults.removeObject(forKey: preparedVersionKey)
    }

    private static func storeFiles(for storeURL: URL, fileManager: FileManager) -> [URL] {
        [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func snapshotsRoot(fileManager: FileManager) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("MultiCurrencyLedger/MigrationSnapshots", isDirectory: true)
    }

    private static func newSnapshotDirectory(
        prefix: String,
        fileManager: FileManager,
        root: URL
    ) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let directory = root.appendingPathComponent("\(prefix)-\(formatter.string(from: .now))", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func pruneSnapshots(keeping count: Int, fileManager: FileManager, root: URL) throws {
        for snapshot in snapshots(fileManager: fileManager, snapshotsRootURL: root).dropFirst(count) {
            try? fileManager.removeItem(at: snapshot.directoryURL)
        }
    }
}
