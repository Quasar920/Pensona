import Foundation
import SwiftData

@MainActor
final class LedgerBookService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func createBook(name: String) throws -> LedgerBook {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError("请输入账本名称") }

        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        guard !books.contains(where: {
            $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw ValidationError("已有同名账本")
        }

        let nextOrder = (books.map(\.sortOrder).max() ?? -1) + 1
        let book = LedgerBook(name: cleanName, sortOrder: nextOrder)
        context.insert(book)
        try context.save()
        return book
    }

    func rename(_ book: LedgerBook, to name: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError("请输入账本名称") }

        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        guard !books.contains(where: {
            $0.id != book.id
                && $0.name.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw ValidationError("已有同名账本")
        }

        book.name = cleanName
        book.updatedAt = .now
        try context.save()
    }
}
