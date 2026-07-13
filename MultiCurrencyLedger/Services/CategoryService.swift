import Foundation
import SwiftData

enum CategoryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidParent
    case cycle

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入分类名称"
        case .duplicateName: "同一层级已存在同名分类"
        case .invalidParent: "父分类与当前分类的账本或收支类型不一致"
        case .cycle: "分类不能成为自身或子分类的下级"
        }
    }
}

@MainActor
final class CategoryService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func scoped(
        bookID: UUID,
        type: CategoryKind? = nil,
        includeArchived: Bool = false
    ) throws -> [LedgerCategory] {
        try context.fetch(FetchDescriptor<LedgerCategory>())
            .filter { category in
                (category.bookID == nil || category.bookID == bookID)
                    && (type == nil || category.type == type)
                    && (includeArchived || !category.isArchived)
            }
            .sorted(by: categorySort)
    }

    func children(
        of parentID: UUID?,
        bookID: UUID,
        type: CategoryKind,
        includeArchived: Bool = false
    ) throws -> [LedgerCategory] {
        try scoped(bookID: bookID, type: type, includeArchived: includeArchived)
            .filter { $0.parentID == parentID }
    }

    @discardableResult
    func create(
        name: String,
        type: CategoryKind,
        symbolName: String,
        bookID: UUID,
        parent: LedgerCategory? = nil
    ) throws -> LedgerCategory {
        let cleanName = try validatedName(name)
        try validateParent(parent, bookID: bookID, type: type)
        try ensureUnique(
            name: cleanName,
            bookID: bookID,
            type: type,
            parentID: parent?.id,
            excluding: nil
        )
        let siblings = try children(of: parent?.id, bookID: bookID, type: type, includeArchived: true)
        let category = LedgerCategory(
            name: cleanName,
            type: type,
            symbolName: symbolName,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1,
            bookID: bookID,
            parentID: parent?.id
        )
        context.insert(category)
        try context.save()
        return category
    }

    func update(
        _ category: LedgerCategory,
        name: String,
        symbolName: String,
        parent: LedgerCategory?
    ) throws {
        let cleanName = try validatedName(name)
        let scopeBookID = category.bookID
        guard let scopeBookID else { throw CategoryError.invalidParent }
        try validateParent(parent, bookID: scopeBookID, type: category.type)
        if parent?.id == category.id || isDescendant(parent, of: category) {
            throw CategoryError.cycle
        }
        try ensureUnique(
            name: cleanName,
            bookID: scopeBookID,
            type: category.type,
            parentID: parent?.id,
            excluding: category.id
        )
        category.name = cleanName
        category.symbolName = symbolName
        category.parentID = parent?.id
        category.updatedAt = .now
        try context.save()
    }

    func setArchived(_ archived: Bool, category: LedgerCategory) throws {
        category.isArchived = archived
        category.updatedAt = .now
        let all = try context.fetch(FetchDescriptor<LedgerCategory>())
        for child in descendants(of: category, in: all) {
            child.isArchived = archived
            child.updatedAt = .now
        }
        try context.save()
    }

    private func validatedName(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw CategoryError.emptyName }
        return clean
    }

    private func validateParent(
        _ parent: LedgerCategory?,
        bookID: UUID,
        type: CategoryKind
    ) throws {
        guard let parent else { return }
        guard parent.type == type,
              !parent.isArchived,
              parent.bookID == nil || parent.bookID == bookID else {
            throw CategoryError.invalidParent
        }
    }

    private func ensureUnique(
        name: String,
        bookID: UUID,
        type: CategoryKind,
        parentID: UUID?,
        excluding id: UUID?
    ) throws {
        let duplicate = try scoped(bookID: bookID, type: type, includeArchived: true).contains {
            $0.id != id
                && $0.bookID == bookID
                && $0.parentID == parentID
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if duplicate { throw CategoryError.duplicateName }
    }

    private func isDescendant(_ candidate: LedgerCategory?, of ancestor: LedgerCategory) -> Bool {
        guard var current = candidate else { return false }
        let all = (try? context.fetch(FetchDescriptor<LedgerCategory>())) ?? []
        var visited = Set<UUID>()
        while let parentID = current.parentID,
              !visited.contains(parentID),
              let parent = all.first(where: { $0.id == parentID }) {
            if parent.id == ancestor.id { return true }
            visited.insert(parentID)
            current = parent
        }
        return false
    }

    private func descendants(
        of category: LedgerCategory,
        in all: [LedgerCategory]
    ) -> [LedgerCategory] {
        let direct = all.filter { $0.parentID == category.id }
        return direct + direct.flatMap { descendants(of: $0, in: all) }
    }

    private func categorySort(_ lhs: LedgerCategory, _ rhs: LedgerCategory) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.createdAt < rhs.createdAt
    }
}
