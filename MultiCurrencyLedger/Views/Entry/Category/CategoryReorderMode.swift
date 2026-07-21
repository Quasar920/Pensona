import Foundation

enum CategoryReorderMode {
    static func moving(
        sourceID: UUID,
        before targetID: UUID,
        in categories: [LedgerCategory]
    ) -> [LedgerCategory] {
        guard sourceID != targetID,
              let sourceIndex = categories.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = categories.firstIndex(where: { $0.id == targetID }) else {
            return categories
        }
        var result = categories
        let moved = result.remove(at: sourceIndex)
        let insertion = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        result.insert(moved, at: insertion)
        return result
    }
}
