import Foundation
import SwiftData

@Model
final class LedgerBook {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Account.book)
    var accounts: [Account]

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt ?? (isArchived ? createdAt : nil)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        accounts = []
    }

    var isArchived: Bool {
        archivedAt != nil
    }
}
