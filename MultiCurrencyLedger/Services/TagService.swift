import Foundation
import SwiftData

enum TagError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case wrongBook

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入标签名称"
        case .duplicateName: "当前账本已存在同名标签"
        case .wrongBook: "标签与交易不属于同一账本"
        }
    }
}

@MainActor
final class TagService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func scoped(bookID: UUID, includeArchived: Bool = false) throws -> [TransactionTag] {
        try context.fetch(FetchDescriptor<TransactionTag>())
            .filter { $0.bookID == bookID && (includeArchived || !$0.isArchived) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func create(name: String, colorHex: String, bookID: UUID) throws -> TransactionTag {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TagError.emptyName }
        guard try !scoped(bookID: bookID, includeArchived: true).contains(where: {
            $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw TagError.duplicateName }
        let tag = TransactionTag(name: clean, bookID: bookID, colorHex: colorHex)
        context.insert(tag)
        try context.save()
        return tag
    }

    func update(_ tag: TransactionTag, name: String, colorHex: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TagError.emptyName }
        guard try !scoped(bookID: tag.bookID, includeArchived: true).contains(where: {
            $0.id != tag.id
                && $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw TagError.duplicateName }
        tag.name = clean
        tag.colorHex = colorHex
        tag.updatedAt = .now
        try context.save()
    }

    func setArchived(_ archived: Bool, tag: TransactionTag) throws {
        tag.isArchived = archived
        tag.updatedAt = .now
        try context.save()
    }

    func setTags(_ tags: [TransactionTag], on transaction: LedgerTransaction) throws {
        guard let bookID = transaction.sourceAccount?.book?.id,
              tags.allSatisfy({ $0.bookID == bookID && !$0.isArchived }) else {
            throw TagError.wrongBook
        }
        transaction.tags = Array(Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) }).values)
            .sorted { $0.name < $1.name }
        transaction.updatedAt = .now
        try context.save()
    }
}
