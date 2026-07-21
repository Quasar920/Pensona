import Foundation
import SwiftData

@Model
final class RepaymentReminder {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var currencyCode: String
    var outstandingAmount: Decimal
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        accountID: UUID,
        currencyCode: String,
        outstandingAmount: Decimal,
        dueDate: Date,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.accountID = accountID
        self.currencyCode = currencyCode
        self.outstandingAmount = outstandingAmount
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
