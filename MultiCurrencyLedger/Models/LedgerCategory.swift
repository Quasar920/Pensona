import Foundation
import SwiftData

@Model
final class LedgerCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var typeRawValue: String
    var symbolName: String
    var sortOrder: Int
    var isSystem: Bool
    var bookID: UUID?
    var parentID: UUID?
    var isArchived: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        type: CategoryKind,
        symbolName: String,
        sortOrder: Int,
        isSystem: Bool = false,
        bookID: UUID? = nil,
        parentID: UUID? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        typeRawValue = type.rawValue
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.bookID = bookID
        self.parentID = parentID
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: CategoryKind { CategoryKind(rawValue: typeRawValue) ?? .expense }
}
