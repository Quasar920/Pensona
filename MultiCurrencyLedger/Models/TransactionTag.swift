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

/// Compatibility-only cleanup for stores created before tags were removed.
///
/// `TransactionTag` stays in the persisted schema so existing 2.0 stores can still
/// open. The product no longer creates or exposes tags, and this cleanup makes the
/// legacy relationship permanently empty without folding tag text into notes.
enum LegacyTagRemovalService {
    static func removeAll(context: ModelContext) throws {
        var changed = false

        for transaction in try context.fetch(FetchDescriptor<LedgerTransaction>())
        where !transaction.tags.isEmpty {
            transaction.tags.removeAll()
            changed = true
        }

        for template in try context.fetch(FetchDescriptor<TransactionTemplate>())
        where !template.tagIDsData.isEmpty {
            template.tagIDsData = Data()
            changed = true
        }

        let tags = try context.fetch(FetchDescriptor<TransactionTag>())
        for tag in tags {
            context.delete(tag)
            changed = true
        }

        if changed {
            try context.save()
        }
    }
}
