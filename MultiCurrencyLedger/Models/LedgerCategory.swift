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

    init(
        id: UUID = UUID(),
        name: String,
        type: CategoryKind,
        symbolName: String,
        sortOrder: Int,
        isSystem: Bool = false
    ) {
        self.id = id
        self.name = name
        typeRawValue = type.rawValue
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isSystem = isSystem
    }

    var type: CategoryKind { CategoryKind(rawValue: typeRawValue) ?? .expense }
}
