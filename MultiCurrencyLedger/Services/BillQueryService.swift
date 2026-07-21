import Foundation
import SwiftData

@MainActor
struct BillQueryService {
    let context: ModelContext
    var calendar: Calendar = .current

    func load(
        bookID: UUID,
        month: Date,
        baseCurrencyCode: String,
        keyword: String = ""
    ) throws -> BillPageSnapshot {
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            return .empty(
                bookID: bookID,
                month: month,
                baseCurrencyCode: baseCurrencyCode,
                calendar: calendar
            )
        }
        let start = interval.start
        let end = interval.end
        let predicate = #Predicate<LedgerTransaction> { transaction in
            transaction.bookID == bookID
                && transaction.date >= start
                && transaction.date < end
        }
        let descriptor = FetchDescriptor<LedgerTransaction>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\LedgerTransaction.date, order: .reverse),
                SortDescriptor(\LedgerTransaction.createdAt, order: .reverse)
            ]
        )
        let monthTransactions = try context.fetch(descriptor)
        let transactions = filter(monthTransactions, keyword: keyword)
        let ids = Set(monthTransactions.map(\.id))

        let relations = try context.fetch(FetchDescriptor<TransactionRelation>()).filter {
            ids.contains($0.originalTransactionID) || ids.contains($0.relatedTransactionID)
        }
        let splits = try context.fetch(FetchDescriptor<AASplit>()).filter {
            ids.contains($0.originalTransactionID)
        }
        let splitIDs = Set(splits.map(\.id))
        let settlements = try context.fetch(FetchDescriptor<AASettlement>()).filter {
            splitIDs.contains($0.splitID) || ids.contains($0.recoveryTransactionID)
        }
        let rates = try context.fetch(FetchDescriptor<ExchangeRate>())
        let budgetPredicate = #Predicate<MonthlyBudget> { budget in
            budget.bookID == bookID
                && budget.monthStart >= start
                && budget.monthStart < end
                && budget.currencyCode == baseCurrencyCode
                && budget.categoryID == nil
        }
        let budget = try context.fetch(FetchDescriptor<MonthlyBudget>(predicate: budgetPredicate)).first
        let summary = MonthlySummaryService(
            baseCurrencyCode: baseCurrencyCode,
            rates: rates,
            calendar: calendar
        ).summary(
            for: monthTransactions,
            month: month,
            budget: budget?.amount,
            relations: relations,
            aaSplits: splits,
            aaSettlements: settlements
        )

        return BillPageSnapshot(
            bookID: bookID,
            monthInterval: interval,
            transactions: transactions,
            dayGroups: Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
                .map { BillDayGroup(date: $0.key, transactions: $0.value) }
                .sorted { $0.date > $1.date },
            summary: summary
        )
    }

    private func filter(_ transactions: [LedgerTransaction], keyword: String) -> [LedgerTransaction] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return transactions }
        return transactions.filter { transaction in
            [
                transaction.merchantOrCounterparty,
                transaction.note,
                transaction.category?.name,
                transaction.sourceAccount?.name,
                transaction.destinationAccount?.name
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }
}
