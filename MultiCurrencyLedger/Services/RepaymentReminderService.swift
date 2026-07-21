import Foundation
import SwiftData

enum RepaymentReminderError: LocalizedError, Equatable {
    case invalidAmount
    case invalidAccount
    case unsupportedCurrency

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            AppLocalization.string( "待还金额必须大于 0")
        case .invalidAccount:
            AppLocalization.string( "请选择可用账户")
        case .unsupportedCurrency:
            AppLocalization.string( "所选账户不支持该币种")
        }
    }
}

@MainActor
final class RepaymentReminderService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func create(
        accountID: UUID,
        currencyCode: String,
        outstandingAmount: Decimal,
        dueDate: Date
    ) throws -> RepaymentReminder {
        let code = try validatedCurrency(
            accountID: accountID,
            currencyCode: currencyCode,
            outstandingAmount: outstandingAmount
        )
        let reminder = RepaymentReminder(
            accountID: accountID,
            currencyCode: code,
            outstandingAmount: outstandingAmount,
            dueDate: dueDate
        )
        context.insert(reminder)
        try context.save()
        return reminder
    }

    func update(
        _ reminder: RepaymentReminder,
        accountID: UUID,
        currencyCode: String,
        outstandingAmount: Decimal,
        dueDate: Date
    ) throws {
        let code = try validatedCurrency(
            accountID: accountID,
            currencyCode: currencyCode,
            outstandingAmount: outstandingAmount
        )
        reminder.accountID = accountID
        reminder.currencyCode = code
        reminder.outstandingAmount = outstandingAmount
        reminder.dueDate = dueDate
        reminder.updatedAt = .now
        try context.save()
    }

    func setCompleted(_ isCompleted: Bool, reminder: RepaymentReminder) throws {
        reminder.isCompleted = isCompleted
        reminder.completedAt = isCompleted ? .now : nil
        reminder.updatedAt = .now
        try context.save()
    }

    func delete(_ reminder: RepaymentReminder) throws {
        context.delete(reminder)
        try context.save()
    }

    private func validatedCurrency(
        accountID: UUID,
        currencyCode: String,
        outstandingAmount: Decimal
    ) throws -> String {
        guard outstandingAmount > 0 else { throw RepaymentReminderError.invalidAmount }
        guard let account = try context.fetch(FetchDescriptor<Account>()).first(where: {
            $0.id == accountID && !$0.isArchived
        }) else {
            throw RepaymentReminderError.invalidAccount
        }
        let code = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard account.allWallets.contains(where: { $0.currencyCode == code }) else {
            throw RepaymentReminderError.unsupportedCurrency
        }
        return code
    }
}
