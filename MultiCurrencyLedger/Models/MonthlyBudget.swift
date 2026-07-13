import Foundation
import SwiftData

@Model
final class MonthlyBudget {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var scopeKey: String
    var bookID: UUID
    var monthStart: Date
    var currencyCode: String
    var amount: Decimal
    var periodRawValue: String = BudgetPeriod.monthly.rawValue
    var categoryID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scopeKey: String,
        bookID: UUID,
        monthStart: Date,
        currencyCode: String,
        amount: Decimal,
        period: BudgetPeriod = .monthly,
        categoryID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.scopeKey = scopeKey
        self.bookID = bookID
        self.monthStart = monthStart
        self.currencyCode = currencyCode
        self.amount = amount
        periodRawValue = period.rawValue
        self.categoryID = categoryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var period: BudgetPeriod {
        BudgetPeriod(rawValue: periodRawValue) ?? .monthly
    }
}

enum BudgetPeriod: String, CaseIterable, Codable, Identifiable {
    case weekly, monthly, yearly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: "周"
        case .monthly: "月"
        case .yearly: "年"
        }
    }
}
