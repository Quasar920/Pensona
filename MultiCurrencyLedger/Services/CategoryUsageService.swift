import Foundation
import SwiftData

struct CategoryUsageSummary: Equatable, Sendable {
    let directTransactionCount: Int
    let descendantTransactionCount: Int
    let directChildCount: Int

    var totalTransactionCount: Int { directTransactionCount + descendantTransactionCount }
    var requiresMigration: Bool { totalTransactionCount > 0 || directChildCount > 0 }
}

@MainActor
final class CategoryUsageService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func summary(for category: LedgerCategory) throws -> CategoryUsageSummary {
        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let directChildren = categories.filter { $0.parentID == category.id }
        let descendantIDs = Set(descendants(of: category.id, in: categories).map(\.id))
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let direct = transactions.count { $0.category?.id == category.id }
        let descendant = transactions.count {
            guard let id = $0.category?.id else { return false }
            return descendantIDs.contains(id)
        }
        return CategoryUsageSummary(
            directTransactionCount: direct,
            descendantTransactionCount: descendant,
            directChildCount: directChildren.count
        )
    }

    func transactionCount(for category: LedgerCategory) throws -> Int {
        try context.fetch(FetchDescriptor<LedgerTransaction>()).count { $0.category?.id == category.id }
    }

    private func descendants(
        of parentID: UUID,
        in categories: [LedgerCategory]
    ) -> [LedgerCategory] {
        let direct = categories.filter { $0.parentID == parentID }
        return direct + direct.flatMap { descendants(of: $0.id, in: categories) }
    }
}
