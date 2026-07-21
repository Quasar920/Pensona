import Foundation
import SwiftData

enum CategoryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidParent
    case cycle
    case maximumDepth
    case invalidReorder
    case childrenRequireMigration(Int)
    case referencesRequireMigration(Int)
    case invalidMigrationTarget

    var errorDescription: String? {
        switch self {
        case .emptyName: AppLocalization.string( "请输入分类名称")
        case .duplicateName: AppLocalization.string( "同一层级已存在同名分类")
        case .invalidParent: AppLocalization.string( "父分类与当前分类的账本或收支类型不一致")
        case .cycle: AppLocalization.string( "分类不能成为自身或子分类的下级")
        case .maximumDepth: AppLocalization.string( "分类最多只能有两层")
        case .invalidReorder: AppLocalization.string( "只能对同一层级的分类排序")
        case let .childrenRequireMigration(count): AppLocalization.string( "该分类仍有 \(count) 个子分类，请先迁移")
        case let .referencesRequireMigration(count): AppLocalization.string( "该分类仍被 \(count) 笔历史交易使用，请先迁移")
        case .invalidMigrationTarget: AppLocalization.string( "迁移目标必须是同收支类型，且不能是当前分类或其下级")
        }
    }
}

@MainActor
final class CategoryService {
    private let context: ModelContext
    private let iconStore: CategoryIconStore

    init(context: ModelContext) {
        self.context = context
        iconStore = CategoryIconStore()
    }

    init(context: ModelContext, iconStore: CategoryIconStore) {
        self.context = context
        self.iconStore = iconStore
    }

    func scoped(
        bookID: UUID,
        type: CategoryKind? = nil,
        includeArchived: Bool = false
    ) throws -> [LedgerCategory] {
        try context.fetch(FetchDescriptor<LedgerCategory>())
            .filter { category in
                (type == nil || category.type == type)
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
        try validateParent(parent, type: type)
        try ensureUnique(
            name: cleanName,
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
            bookID: nil,
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
        try validateParent(parent, type: category.type)
        if parent?.id == category.id || isDescendant(parent, of: category) {
            throw CategoryError.cycle
        }
        try ensureUnique(
            name: cleanName,
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

    func updateNameAndIcon(
        _ category: LedgerCategory,
        name: String,
        symbolName: String,
        iconSource: CategoryIconSource = .builtIn,
        userIconRelativePath: String? = nil
    ) throws {
        let previousIconPath = category.userIconRelativePath
        let cleanName = try validatedName(name)
        try ensureUnique(
            name: cleanName,
            type: category.type,
            parentID: category.parentID,
            excluding: category.id
        )
        category.name = cleanName
        category.symbolName = symbolName
        category.iconSource = iconSource
        category.userIconRelativePath = userIconRelativePath
        if category.isSystem, cleanName != category.localizedName(locale: Locale(identifier: "zh-Hans")) {
            category.isSystem = false
            category.systemLocalizationKey = nil
        }
        category.updatedAt = .now
        try context.save()
        if let previousIconPath, previousIconPath != userIconRelativePath {
            let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
            try? iconStore.removeIfUnreferenced(relativePath: previousIconPath, categories: categories)
        }
    }

    func reorder(_ orderedCategories: [LedgerCategory]) throws {
        guard let first = orderedCategories.first else { return }
        let ids = Set(orderedCategories.map(\.id))
        guard ids.count == orderedCategories.count,
              orderedCategories.allSatisfy({
                  $0.type == first.type && $0.parentID == first.parentID && !$0.isArchived
              }) else {
            throw CategoryError.invalidReorder
        }
        let allSiblings = try context.fetch(FetchDescriptor<LedgerCategory>()).filter {
            $0.type == first.type && $0.parentID == first.parentID && !$0.isArchived
        }
        guard Set(allSiblings.map(\.id)) == ids else { throw CategoryError.invalidReorder }
        for (index, category) in orderedCategories.enumerated() {
            category.sortOrder = index
            category.updatedAt = .now
        }
        try context.save()
    }

    func convertRootToChild(_ category: LedgerCategory, under parent: LedgerCategory) throws {
        guard category.parentID == nil else { throw CategoryError.invalidParent }
        let all = try context.fetch(FetchDescriptor<LedgerCategory>())
        let childCount = all.count { $0.parentID == category.id }
        guard childCount == 0 else { throw CategoryError.childrenRequireMigration(childCount) }
        try move(category, under: parent)
    }

    func moveChild(_ category: LedgerCategory, to parent: LedgerCategory) throws {
        guard category.parentID != nil else { throw CategoryError.invalidParent }
        try move(category, under: parent)
    }

    func promoteToRoot(_ category: LedgerCategory) throws {
        guard category.parentID != nil else { return }
        try ensureUnique(name: category.name, type: category.type, parentID: nil, excluding: category.id)
        let roots = try context.fetch(FetchDescriptor<LedgerCategory>()).filter {
            $0.type == category.type && $0.parentID == nil
        }
        category.parentID = nil
        category.sortOrder = (roots.map(\.sortOrder).max() ?? -1) + 1
        category.updatedAt = .now
        try context.save()
    }

    func usageSummary(for category: LedgerCategory) throws -> CategoryUsageSummary {
        try CategoryUsageService(context: context).summary(for: category)
    }

    func delete(
        _ category: LedgerCategory,
        migratingReferencesTo target: LedgerCategory? = nil
    ) throws {
        let iconPath = category.userIconRelativePath
        let summary = try usageSummary(for: category)
        if let target {
            try validateMigrationTarget(target, for: category)
            if summary.directChildCount > 0, target.parentID != nil {
                throw CategoryError.invalidMigrationTarget
            }
            let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
            var nextChildOrder = nextSortOrder(parentID: target.id, type: category.type, in: categories)
            for child in categories where child.parentID == category.id {
                child.parentID = target.id
                child.sortOrder = nextChildOrder
                nextChildOrder += 1
                child.updatedAt = .now
            }
            let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
            for transaction in transactions where transaction.category?.id == category.id {
                transaction.category = target
                transaction.updatedAt = .now
            }
        } else {
            if summary.directChildCount > 0 {
                throw CategoryError.childrenRequireMigration(summary.directChildCount)
            }
            if summary.directTransactionCount > 0 {
                throw CategoryError.referencesRequireMigration(summary.directTransactionCount)
            }
        }
        context.delete(category)
        try context.save()
        if let iconPath {
            let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
            try? iconStore.removeIfUnreferenced(relativePath: iconPath, categories: categories)
        }
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
        type: CategoryKind
    ) throws {
        guard let parent else { return }
        guard parent.type == type,
              !parent.isArchived,
              parent.parentID == nil else {
            throw CategoryError.invalidParent
        }
    }

    private func ensureUnique(
        name: String,
        type: CategoryKind,
        parentID: UUID?,
        excluding id: UUID?
    ) throws {
        let duplicate = try context.fetch(FetchDescriptor<LedgerCategory>()).contains {
            $0.id != id
                && $0.type == type
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

    private func move(_ category: LedgerCategory, under parent: LedgerCategory) throws {
        try validateParent(parent, type: category.type)
        guard parent.id != category.id, !isDescendant(parent, of: category) else {
            throw CategoryError.cycle
        }
        try ensureUnique(
            name: category.name,
            type: category.type,
            parentID: parent.id,
            excluding: category.id
        )
        let siblings = try context.fetch(FetchDescriptor<LedgerCategory>()).filter {
            $0.parentID == parent.id && $0.id != category.id
        }
        category.parentID = parent.id
        category.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        category.updatedAt = .now
        try context.save()
    }

    private func validateMigrationTarget(
        _ target: LedgerCategory,
        for category: LedgerCategory
    ) throws {
        guard target.id != category.id,
              target.type == category.type,
              !target.isArchived,
              !isDescendant(target, of: category) else {
            throw CategoryError.invalidMigrationTarget
        }
    }

    private func nextSortOrder(
        parentID: UUID?,
        type: CategoryKind,
        in categories: [LedgerCategory]
    ) -> Int {
        (categories.filter { $0.parentID == parentID && $0.type == type }.map(\.sortOrder).max() ?? -1) + 1
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
