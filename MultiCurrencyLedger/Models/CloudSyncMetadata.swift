import Foundation
import SwiftData

@Model
final class CloudSyncTombstone {
    @Attribute(.unique) var id: String
    var entityType: String
    var entityID: UUID
    var deletedAt: Date

    init(entityType: String, entityID: UUID, deletedAt: Date = .now) {
        id = "\(entityType):\(entityID.uuidString.lowercased())"
        self.entityType = entityType
        self.entityID = entityID
        self.deletedAt = deletedAt
    }
}

@Model
final class CloudSyncConflictCopy {
    @Attribute(.unique) var id: UUID
    var remoteRevision: String
    var remoteDeviceID: String
    var remoteModifiedAt: Date
    @Attribute(.externalStorage) var remotePayloadData: Data
    var createdAt: Date
    var resolvedAt: Date?
    var resolutionRawValue: String?

    init(
        id: UUID = UUID(),
        remoteRevision: String,
        remoteDeviceID: String,
        remoteModifiedAt: Date,
        remotePayloadData: Data,
        createdAt: Date = .now,
        resolvedAt: Date? = nil,
        resolutionRawValue: String? = nil
    ) {
        self.id = id
        self.remoteRevision = remoteRevision
        self.remoteDeviceID = remoteDeviceID
        self.remoteModifiedAt = remoteModifiedAt
        self.remotePayloadData = remotePayloadData
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolutionRawValue = resolutionRawValue
    }
}
