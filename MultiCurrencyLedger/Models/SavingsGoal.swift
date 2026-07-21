import Foundation
import SwiftData

enum SavingsGoalStatus: String, CaseIterable, Codable, Identifiable {
    case active, paused, completed, archived

    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: AppLocalization.string( "进行中")
        case .paused: AppLocalization.string( "已暂停")
        case .completed: AppLocalization.string( "已完成")
        case .archived: AppLocalization.string( "已归档")
        }
    }
}

@Model
final class SavingsGoal {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var name: String
    var targetAmount: Decimal
    var currencyCode: String
    var targetDate: Date?
    var symbolName: String
    var colorHex: String
    var statusRawValue: String
    /// `bookID` remains as provenance for restored data. Visibility is global.
    var isGloballyVisible: Bool = true
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SavingsAllocation.goal)
    var allocations: [SavingsAllocation]

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String,
        targetAmount: Decimal,
        currencyCode: String,
        targetDate: Date? = nil,
        symbolName: String = "target",
        colorHex: String = "3478F6",
        status: SavingsGoalStatus = .active,
        isGloballyVisible: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.targetAmount = targetAmount
        self.currencyCode = currencyCode
        self.targetDate = targetDate
        self.symbolName = symbolName
        self.colorHex = colorHex
        statusRawValue = status.rawValue
        self.isGloballyVisible = isGloballyVisible
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        allocations = []
    }

    var status: SavingsGoalStatus {
        get { SavingsGoalStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class SavingsAllocation {
    @Attribute(.unique) var id: UUID
    var amount: Decimal
    var date: Date
    var note: String?
    var sourceAccountID: UUID?
    var createdAt: Date
    var goal: SavingsGoal?

    init(
        id: UUID = UUID(),
        amount: Decimal,
        date: Date = .now,
        note: String? = nil,
        sourceAccountID: UUID? = nil,
        goal: SavingsGoal? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.sourceAccountID = sourceAccountID
        self.goal = goal
        self.createdAt = createdAt
    }
}
