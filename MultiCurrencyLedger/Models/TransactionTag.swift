import Foundation
import SwiftData

@Model
final class TransactionTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookID: UUID
    var colorHex: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var transactions: [LedgerTransaction]

    init(
        id: UUID = UUID(),
        name: String,
        bookID: UUID,
        colorHex: String = "#5B8DEF",
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.bookID = bookID
        self.colorHex = colorHex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        transactions = []
    }
}
