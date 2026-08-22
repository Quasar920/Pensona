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
        let summaryService = MonthlySummaryService(
            baseCurrencyCode: baseCurrencyCode,
            rates: rates,
            calendar: calendar
        )
        let summary = summaryService.summary(
            for: monthTransactions,
            month: month,
            budget: budget?.amount,
            relations: relations,
            aaSplits: splits,
            aaSettlements: settlements
        )
        let transactionsByID = Dictionary(uniqueKeysWithValues: monthTransactions.map { ($0.id, $0) })
        let refundDisplays = refundDisplaySummaries(
            relations: relations,
            transactionsByID: transactionsByID
        )
        let refundIncomeDisplays = refundIncomeDisplays(
            relations: relations,
            transactionsByID: transactionsByID
        )

        let allTransactionsByDay = Dictionary(grouping: monthTransactions) {
            calendar.startOfDay(for: $0.date)
        }
        let dayGroups = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
            .map { date, visibleTransactions in
                let daySummary = summaryService.summary(
                    for: allTransactionsByDay[date] ?? [],
                    month: date,
                    relations: relations,
                    aaSplits: splits,
                    aaSettlements: settlements
                )
                return BillDayGroup(
                    date: date,
                    transactions: visibleTransactions,
                    income: daySummary.income,
                    expense: daySummary.expense,
                    refundDisplays: refundDisplays.filter { display in
                        visibleTransactions.contains { $0.id == display.key }
                    },
                    refundIncomeDisplays: refundIncomeDisplays.filter { display in
                        visibleTransactions.contains { $0.id == display.key }
                    }
                )
            }
            .sorted { $0.date > $1.date }

        return BillPageSnapshot(
            bookID: bookID,
            monthInterval: interval,
            transactions: transactions,
            dayGroups: dayGroups,
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

    private func refundDisplaySummaries(
        relations: [TransactionRelation],
        transactionsByID: [UUID: LedgerTransaction]
    ) -> [UUID: RefundDisplaySummary] {
        var recoveredByOriginal: [UUID: Decimal] = [:]
        var excessByOriginal: [UUID: Decimal] = [:]
        for relation in relations where relation.kind == .refund {
            recoveredByOriginal[relation.originalTransactionID, default: 0] += relation.amount
            excessByOriginal[relation.originalTransactionID, default: 0] += relation.excessIncomeAmount ?? 0
        }
        return recoveredByOriginal.reduce(into: [:]) { result, item in
            guard let original = transactionsByID[item.key] else { return }
            result[item.key] = RefundDisplaySummary(
                recoveredAmount: item.value,
                excessIncomeAmount: excessByOriginal[item.key, default: 0],
                originalNetAmount: original.netExpenseAmount
            )
        }
    }

    private func refundIncomeDisplays(
        relations: [TransactionRelation],
        transactionsByID: [UUID: LedgerTransaction]
    ) -> [UUID: RefundIncomeDisplay] {
        Dictionary(uniqueKeysWithValues: relations.compactMap { relation in
            guard relation.kind == .refund,
                  relation.excessIncomeTransactionID == nil,
                  let excess = relation.excessIncomeAmount,
                  excess > 0,
                  let deposit = transactionsByID[relation.relatedTransactionID],
                  let original = transactionsByID[relation.originalTransactionID]
            else { return nil }
            let code = deposit.sourceCurrencyCode ?? deposit.currencyCode ?? "CNY"
            let merchant = original.merchantOrCounterparty
                ?? original.displayNote
                ?? AppLocalization.string("原支出")
            return (deposit.id, RefundIncomeDisplay(
                id: relation.id,
                refundDepositTransactionID: deposit.id,
                amount: excess,
                currencyCode: code,
                date: deposit.date,
                merchant: merchant,
                accountName: deposit.receiptFundingText ?? deposit.homeAccountName
            ))
        })
    }
}
