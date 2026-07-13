import CloudKit
import CryptoKit
import Foundation
import SwiftData

struct SyncManifest: Codable, Equatable {
    var entities: [String: [UUID]]

    init(document: LedgerBackupDocument) {
        entities = [
            "book": document.books.map(\.id), "account": document.accounts.map(\.id),
            "wallet": document.wallets.map(\.id), "category": document.categories.map(\.id),
            "tag": document.tags.map(\.id), "transaction": document.transactions.map(\.id),
            "relation": document.relations.map(\.id), "attachment": document.attachments.map(\.id),
            "template": document.templates.map(\.id),
            "recurringSchedule": document.recurringSchedules.map(\.id),
            "recurringOccurrence": document.recurringOccurrences.map(\.id),
            "installmentPlan": document.installmentPlans.map(\.id),
            "installmentOccurrence": document.installmentOccurrences.map(\.id),
            "recognitionRecord": document.recognitionRecords.map(\.id),
            "exchangeRate": document.exchangeRates.map(\.id), "budget": document.budgets.map(\.id),
            "savingsGoal": document.savingsGoals.map(\.id),
            "savingsAllocation": document.savingsAllocations.map(\.id),
            "importBatch": document.importBatches.map(\.id),
            "importFingerprint": document.importFingerprints.map(\.id)
        ]
    }

    func deletions(since previous: SyncManifest) -> [(String, UUID)] {
        previous.entities.flatMap { type, oldIDs in
            let current = Set(entities[type] ?? [])
            return oldIDs.filter { !current.contains($0) }.map { (type, $0) }
        }
    }
}

struct SyncTombstonePayload: Codable, Equatable {
    let entityType: String
    let entityID: UUID
    let deletedAt: Date
}

struct CloudSyncPayload: Codable {
    let revision: String
    let deviceID: String
    let createdAt: Date
    let semanticHash: String
    let backupData: Data
    let manifest: SyncManifest
    let tombstones: [SyncTombstonePayload]
}

struct CloudSnapshot {
    let payloadData: Data
    let revision: String
    let deviceID: String
    let semanticHash: String
    let modifiedAt: Date
    let changeTag: String?
}

enum CloudAccountAvailability: Equatable {
    case available
    case unavailable(String)
}

protocol CloudSnapshotTransport {
    func accountAvailability() async -> CloudAccountAvailability
    func fetch() async throws -> CloudSnapshot?
    func save(payloadData: Data, payload: CloudSyncPayload, expectedChangeTag: String?) async throws -> CloudSnapshot
    func delete() async throws
}

enum CloudSnapshotTransportError: LocalizedError, Equatable {
    case accountUnavailable
    case malformedRecord
    case remoteChanged

    var errorDescription: String? {
        switch self {
        case .accountUnavailable: "当前设备没有可用的 iCloud 私有数据库"
        case .malformedRecord: "iCloud 中的同步记录不完整"
        case .remoteChanged: "同步期间云端内容发生变化，请重新同步"
        }
    }
}

struct CloudKitSnapshotTransport: CloudSnapshotTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: "primary-ledger-snapshot")

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.ian.MultiCurrencyLedger")) {
        self.container = container
        database = container.privateCloudDatabase
    }

    func accountAvailability() async -> CloudAccountAvailability {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .unavailable("请先在系统设置中登录 iCloud")
            case .restricted: return .unavailable("此设备限制了 iCloud 访问")
            case .couldNotDetermine: return .unavailable("暂时无法确认 iCloud 状态")
            case .temporarilyUnavailable: return .unavailable("iCloud 暂时不可用，请稍后重试")
            @unknown default: return .unavailable("当前 iCloud 状态不受支持")
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func fetch() async throws -> CloudSnapshot? {
        do {
            let record = try await database.record(for: recordID)
            return try snapshot(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func save(
        payloadData: Data,
        payload: CloudSyncPayload,
        expectedChangeTag: String?
    ) async throws -> CloudSnapshot {
        let record: CKRecord
        do {
            let existing = try await database.record(for: recordID)
            if let expectedChangeTag, existing.recordChangeTag != expectedChangeTag {
                throw CloudSnapshotTransportError.remoteChanged
            }
            record = existing
        } catch let error as CKError where error.code == .unknownItem {
            guard expectedChangeTag == nil else { throw CloudSnapshotTransportError.remoteChanged }
            record = CKRecord(recordType: "LedgerSnapshot", recordID: recordID)
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-snapshot-\(UUID()).json")
        try payloadData.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        record["revision"] = payload.revision as CKRecordValue
        record["deviceID"] = payload.deviceID as CKRecordValue
        record["semanticHash"] = payload.semanticHash as CKRecordValue
        record["createdAt"] = payload.createdAt as CKRecordValue
        record["payload"] = CKAsset(fileURL: fileURL)
        let saved = try await database.save(record)
        return try snapshot(from: saved)
    }

    func delete() async throws {
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    private func snapshot(from record: CKRecord) throws -> CloudSnapshot {
        guard let revision = record["revision"] as? String,
              let deviceID = record["deviceID"] as? String,
              let semanticHash = record["semanticHash"] as? String,
              let asset = record["payload"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudSnapshotTransportError.malformedRecord
        }
        return CloudSnapshot(
            payloadData: try Data(contentsOf: fileURL, options: .mappedIfSafe),
            revision: revision, deviceID: deviceID, semanticHash: semanticHash,
            modifiedAt: record.modificationDate ?? .now, changeTag: record.recordChangeTag
        )
    }
}

enum CloudSyncOutcome: Equatable {
    case uploaded
    case downloaded
    case noChanges
    case conflictCreated

    var message: String {
        switch self {
        case .uploaded: "本机数据已上传到 iCloud 私有数据库"
        case .downloaded: "已应用云端数据；恢复前快照保留在本机"
        case .noChanges: "本机与 iCloud 已是最新状态"
        case .conflictCreated: "检测到两端同时修改，已保留本机并生成冲突副本"
        }
    }
}

@MainActor
final class CloudSyncService {
    static let enabledKey = "cloudSyncEnabled"
    static let lastSyncAtKey = "cloudSyncLastSyncAt"
    static let lastErrorKey = "cloudSyncLastError"

    private enum Key {
        static let deviceID = "cloudSyncDeviceID"
        static let lastRemoteRevision = "cloudSyncLastRemoteRevision"
        static let lastLocalHash = "cloudSyncLastLocalHash"
        static let lastManifest = "cloudSyncLastManifest"
    }

    private let transport: CloudSnapshotTransport
    private let defaults: UserDefaults

    init(
        transport: CloudSnapshotTransport = CloudKitSnapshotTransport(),
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.defaults = defaults
    }

    func availability() async -> CloudAccountAvailability {
        await transport.accountAvailability()
    }

    func synchronize(context: ModelContext, baseCurrencyCode: String) async throws -> CloudSyncOutcome {
        guard case .available = await transport.accountAvailability() else {
            throw CloudSnapshotTransportError.accountUnavailable
        }
        let localDocument = try BackupService.makeDocument(context: context, baseCurrencyCode: baseCurrencyCode)
        let localHash = try semanticHash(localDocument)
        let localManifest = SyncManifest(document: localDocument)
        try recordLocalDeletions(current: localManifest, context: context)
        let remote = try await transport.fetch()
        let lastRemoteRevision = defaults.string(forKey: Key.lastRemoteRevision)
        let lastLocalHash = defaults.string(forKey: Key.lastLocalHash)

        if let remote {
            if remote.semanticHash == localHash {
                remember(remote: remote, localHash: localHash, manifest: localManifest)
                return .noChanges
            }
            let remoteChanged = lastRemoteRevision == nil || lastRemoteRevision != remote.revision
            let localChanged = lastLocalHash == nil || lastLocalHash != localHash
            if remoteChanged && localChanged {
                try createConflict(from: remote, context: context)
                defaults.set(Date.now, forKey: Self.lastSyncAtKey)
                return .conflictCreated
            }
            if remoteChanged {
                let payload = try decodePayload(remote.payloadData)
                let result = try BackupService.restore(
                    data: payload.backupData,
                    context: context,
                    currentBaseCurrencyCode: baseCurrencyCode
                )
                defaults.set(result.settings.baseCurrencyCode, forKey: "baseCurrencyCode")
                try apply(payload.tombstones, context: context)
                remember(remote: remote, localHash: payload.semanticHash, manifest: payload.manifest)
                return .downloaded
            }
            let snapshot = try await upload(
                document: localDocument, manifest: localManifest, context: context,
                expectedChangeTag: remote.changeTag
            )
            remember(remote: snapshot, localHash: localHash, manifest: localManifest)
            return .uploaded
        }

        let snapshot = try await upload(
            document: localDocument, manifest: localManifest, context: context, expectedChangeTag: nil
        )
        remember(remote: snapshot, localHash: localHash, manifest: localManifest)
        return .uploaded
    }

    func resolveKeepingLocal(
        _ conflict: CloudSyncConflictCopy,
        context: ModelContext,
        baseCurrencyCode: String
    ) async throws {
        let document = try BackupService.makeDocument(context: context, baseCurrencyCode: baseCurrencyCode)
        let manifest = SyncManifest(document: document)
        let remote = try await transport.fetch()
        let snapshot = try await upload(
            document: document, manifest: manifest, context: context,
            expectedChangeTag: remote?.changeTag
        )
        conflict.resolvedAt = .now
        conflict.resolutionRawValue = "local"
        try context.save()
        remember(remote: snapshot, localHash: try semanticHash(document), manifest: manifest)
    }

    func resolveUsingRemote(
        _ conflict: CloudSyncConflictCopy,
        context: ModelContext,
        currentBaseCurrencyCode: String
    ) throws -> BackupSettings {
        let payload = try decodePayload(conflict.remotePayloadData)
        let result = try BackupService.restore(
            data: payload.backupData,
            context: context,
            currentBaseCurrencyCode: currentBaseCurrencyCode
        )
        try apply(payload.tombstones, context: context)
        conflict.resolvedAt = .now
        conflict.resolutionRawValue = "remote"
        try context.save()
        defaults.set(payload.revision, forKey: Key.lastRemoteRevision)
        defaults.set(payload.semanticHash, forKey: Key.lastLocalHash)
        defaults.set(try JSONEncoder().encode(payload.manifest), forKey: Key.lastManifest)
        defaults.set(Date.now, forKey: Self.lastSyncAtKey)
        return result.settings
    }

    func deleteCloudData() async throws {
        try await transport.delete()
        defaults.removeObject(forKey: Key.lastRemoteRevision)
        defaults.removeObject(forKey: Key.lastLocalHash)
        defaults.removeObject(forKey: Key.lastManifest)
        defaults.removeObject(forKey: Self.lastSyncAtKey)
        defaults.removeObject(forKey: Self.lastErrorKey)
    }

    private func upload(
        document: LedgerBackupDocument,
        manifest: SyncManifest,
        context: ModelContext,
        expectedChangeTag: String?
    ) async throws -> CloudSnapshot {
        let payload = CloudSyncPayload(
            revision: UUID().uuidString.lowercased(), deviceID: deviceID,
            createdAt: .now, semanticHash: try semanticHash(document),
            backupData: try BackupService.encode(document), manifest: manifest,
            tombstones: try context.fetch(FetchDescriptor<CloudSyncTombstone>()).map {
                SyncTombstonePayload(entityType: $0.entityType, entityID: $0.entityID, deletedAt: $0.deletedAt)
            }
        )
        let payloadData = try JSONEncoder().encode(payload)
        return try await transport.save(
            payloadData: payloadData, payload: payload, expectedChangeTag: expectedChangeTag
        )
    }

    private func createConflict(from remote: CloudSnapshot, context: ModelContext) throws {
        let unresolved = try context.fetch(FetchDescriptor<CloudSyncConflictCopy>())
        guard !unresolved.contains(where: { $0.remoteRevision == remote.revision && $0.resolvedAt == nil }) else { return }
        context.insert(CloudSyncConflictCopy(
            remoteRevision: remote.revision, remoteDeviceID: remote.deviceID,
            remoteModifiedAt: remote.modifiedAt, remotePayloadData: remote.payloadData
        ))
        try context.save()
    }

    private func recordLocalDeletions(current: SyncManifest, context: ModelContext) throws {
        guard let data = defaults.data(forKey: Key.lastManifest),
              let previous = try? JSONDecoder().decode(SyncManifest.self, from: data) else { return }
        let existing = try context.fetch(FetchDescriptor<CloudSyncTombstone>())
        let existingIDs = Set(existing.map(\.id))
        for (type, id) in current.deletions(since: previous) {
            let key = "\(type):\(id.uuidString.lowercased())"
            if !existingIDs.contains(key) { context.insert(CloudSyncTombstone(entityType: type, entityID: id)) }
        }
        try context.save()
    }

    private func apply(_ tombstones: [SyncTombstonePayload], context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<CloudSyncTombstone>())
        let values = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for item in tombstones {
            let id = "\(item.entityType):\(item.entityID.uuidString.lowercased())"
            if let value = values[id] { value.deletedAt = max(value.deletedAt, item.deletedAt) }
            else { context.insert(CloudSyncTombstone(entityType: item.entityType, entityID: item.entityID, deletedAt: item.deletedAt)) }
        }
        try context.save()
    }

    private func remember(
        remote: CloudSnapshot,
        localHash: String,
        manifest: SyncManifest
    ) {
        defaults.set(remote.revision, forKey: Key.lastRemoteRevision)
        defaults.set(localHash, forKey: Key.lastLocalHash)
        if let data = try? JSONEncoder().encode(manifest) {
            defaults.set(data, forKey: Key.lastManifest)
        }
        defaults.set(Date.now, forKey: Self.lastSyncAtKey)
        defaults.removeObject(forKey: Self.lastErrorKey)
    }

    private func decodePayload(_ data: Data) throws -> CloudSyncPayload {
        try JSONDecoder().decode(CloudSyncPayload.self, from: data)
    }

    private func semanticHash(_ document: LedgerBackupDocument) throws -> String {
        var value = document
        value.exportedAt = Date(timeIntervalSince1970: 0)
        value.books.sort { $0.id.uuidString < $1.id.uuidString }
        value.accounts.sort { $0.id.uuidString < $1.id.uuidString }
        value.wallets.sort { $0.id.uuidString < $1.id.uuidString }
        value.categories.sort { $0.id.uuidString < $1.id.uuidString }
        value.tags.sort { $0.id.uuidString < $1.id.uuidString }
        value.transactions.sort { $0.id.uuidString < $1.id.uuidString }
        for index in value.transactions.indices {
            value.transactions[index].tagIDs?.sort { $0.uuidString < $1.uuidString }
            value.transactions[index].paymentParts?.sort { $0.id.uuidString < $1.id.uuidString }
        }
        value.relations.sort { $0.id.uuidString < $1.id.uuidString }
        value.attachments.sort { $0.id.uuidString < $1.id.uuidString }
        value.templates.sort { $0.id.uuidString < $1.id.uuidString }
        for index in value.templates.indices {
            value.templates[index].tagIDs.sort { $0.uuidString < $1.uuidString }
            value.templates[index].paymentParts.sort { $0.walletID.uuidString < $1.walletID.uuidString }
        }
        value.recurringSchedules.sort { $0.id.uuidString < $1.id.uuidString }
        value.recurringOccurrences.sort { $0.id.uuidString < $1.id.uuidString }
        value.installmentPlans.sort { $0.id.uuidString < $1.id.uuidString }
        value.installmentOccurrences.sort { $0.id.uuidString < $1.id.uuidString }
        value.recognitionRecords.sort { $0.id.uuidString < $1.id.uuidString }
        value.exchangeRates.sort { $0.id.uuidString < $1.id.uuidString }
        value.budgets.sort { $0.id.uuidString < $1.id.uuidString }
        value.savingsGoals.sort { $0.id.uuidString < $1.id.uuidString }
        value.savingsAllocations.sort { $0.id.uuidString < $1.id.uuidString }
        value.importBatches.sort { $0.id.uuidString < $1.id.uuidString }
        value.importFingerprints.sort { $0.id.uuidString < $1.id.uuidString }
        let digest = SHA256.hash(data: try BackupService.encode(value))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var deviceID: String {
        if let value = defaults.string(forKey: Key.deviceID) { return value }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: Key.deviceID)
        return value
    }
}
