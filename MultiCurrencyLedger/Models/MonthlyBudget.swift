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
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        scopeKey: String,
        bookID: UUID,
        monthStart: Date,
        currencyCode: String,
        amount: Decimal,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.scopeKey = scopeKey
        self.bookID = bookID
        self.monthStart = monthStart
        self.currencyCode = currencyCode
        self.amount = amount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
