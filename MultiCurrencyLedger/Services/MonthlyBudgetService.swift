import Foundation
import SwiftData

enum MonthlyBudgetError: LocalizedError, Equatable {
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .invalidAmount: AppLocalization.string( "月度预算必须大于 0")
        }
    }
}

@MainActor
final class MonthlyBudgetService {
    private let context: ModelContext
    private let calendar: Calendar

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    func budget(
        bookID: UUID,
        month date: Date,
        currencyCode: String
    ) throws -> MonthlyBudget? {
        let scope = makeScope(bookID: bookID, date: date, currencyCode: currencyCode)
        let scopeKey = scope.key
        var descriptor = FetchDescriptor<MonthlyBudget>(
            predicate: #Predicate { $0.scopeKey == scopeKey }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func upsert(
        amount: Decimal,
        bookID: UUID,
        month date: Date,
        currencyCode: String
    ) throws -> MonthlyBudget {
        guard amount > 0 else { throw MonthlyBudgetError.invalidAmount }

        return try BudgetService(context: context, calendar: calendar).upsert(
            amount: amount,
            bookID: bookID,
            period: .monthly,
            containing: date,
            currencyCode: currencyCode
        )
    }

    func remove(
        bookID: UUID,
        month date: Date,
        currencyCode: String
    ) throws {
        _ = try LedgerBookAccess.requireActiveBook(in: context, id: bookID)
        guard let value = try budget(
            bookID: bookID,
            month: date,
            currencyCode: currencyCode
        ) else { return }
        context.delete(value)
        try context.save()
    }

    func monthStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    private func makeScope(
        bookID: UUID,
        date: Date,
        currencyCode: String
    ) -> BudgetScope {
        let normalizedCode = currencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let key = "\(bookID.uuidString.lowercased())|\(year)-\(String(format: "%02d", month))|\(normalizedCode)"
        return BudgetScope(
            key: key,
            monthStart: monthStart(containing: date),
            currencyCode: normalizedCode
        )
    }
}

private struct BudgetScope {
    let key: String
    let monthStart: Date
    let currencyCode: String
}
