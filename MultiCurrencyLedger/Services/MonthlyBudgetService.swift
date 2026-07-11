import Foundation
import SwiftData

enum MonthlyBudgetError: LocalizedError, Equatable {
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "月度预算必须大于 0"
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

        let scope = makeScope(bookID: bookID, date: date, currencyCode: currencyCode)
        if let existing = try budget(
            bookID: bookID,
            month: date,
            currencyCode: scope.currencyCode
        ) {
            existing.amount = amount
            existing.monthStart = scope.monthStart
            existing.updatedAt = .now
            try context.save()
            return existing
        }

        let value = MonthlyBudget(
            scopeKey: scope.key,
            bookID: bookID,
            monthStart: scope.monthStart,
            currencyCode: scope.currencyCode,
            amount: amount
        )
        context.insert(value)
        try context.save()
        return value
    }

    func remove(
        bookID: UUID,
        month date: Date,
        currencyCode: String
    ) throws {
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
