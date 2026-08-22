import Foundation

/// The complete-search predicate and aggregation live here so the summary,
/// pagination and dynamic category pages always start from identical data.
struct BillSearchService {
    var calendar: Calendar = .current

    func search(
        transactions: [LedgerTransaction],
        books: [LedgerBook],
        relations: [TransactionRelation],
        settlements: [AASettlement],
        aaSplits: [AASplit] = [],
        query: BillSearchQuery,
        referenceDate: Date = .now
    ) -> BillSearchResult {
        let bookNames = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.name) })
        let matched = transactions.filter {
            matches($0, query: query, bookNames: bookNames, referenceDate: referenceDate)
        }
        let sorted = matched.sorted { sort($0, $1, mode: query.sortMode) }
        let relatedByOriginal = Dictionary(grouping: relations, by: \.originalTransactionID)
        let relatedByIncome = Dictionary(uniqueKeysWithValues: relations
            .filter { $0.amount > 0 }
            .map { ($0.relatedTransactionID, $0) })
        let collectionByTransaction = Dictionary(uniqueKeysWithValues: settlements.map {
            ($0.recoveryTransactionID, $0.amount)
        })
        let incomeIDs = Set(relations.filter { $0.amount > 0 }.map(\.relatedTransactionID))
        let splitByOriginalTransaction = Dictionary(uniqueKeysWithValues: aaSplits.map {
            ($0.originalTransactionID, $0)
        })

        var income = BillSearchAmountAndCount()
        var expense = BillSearchAmountAndCount()
        var dynamic = [BillSearchDynamicCategory: BillSearchAmountAndCount]()
        for transaction in matched {
            let amount = primaryAmount(transaction)
            switch transaction.type {
            case .income where collectionByTransaction[transaction.id] != nil:
                break
            case .income where !incomeIDs.contains(transaction.id):
                income.amount += amount
                income.count += 1
            case .income:
                expense.amount += amount
                expense.count += 1
            case .expense:
                expense.amount += max(0, amount - (splitByOriginalTransaction[transaction.id]?.othersOwedAmount ?? 0))
                expense.count += 1
            case .transfer, .exchange, .adjustment:
                break
            }
            if let fee = transaction.feeAmount, fee != 0 {
                expense.amount += abs(fee)
            }
            for contribution in dynamicContributions(
                transaction: transaction,
                relationsForOriginal: relatedByOriginal[transaction.id] ?? [],
                relatedIncome: relatedByIncome[transaction.id],
                collectionAmount: collectionByTransaction[transaction.id]
            ) {
                var aggregate = dynamic[contribution.category] ?? BillSearchAmountAndCount()
                aggregate.amount += contribution.amount
                aggregate.count += 1
                dynamic[contribution.category] = aggregate
            }
        }
        let summaries: [BillSearchDynamicSummary] = BillSearchDynamicCategory.allCases.compactMap { category in
            guard let value = dynamic[category], value.count > 0 else { return nil }
            return BillSearchDynamicSummary(category: category, amount: value.amount, count: value.count)
        }
        return BillSearchResult(
            allTransactions: sorted,
            totalCount: sorted.count,
            income: income,
            expense: expense,
            dynamicSummaries: summaries
        )
    }

    func transactions(
        for category: BillSearchDynamicCategory,
        in result: BillSearchResult,
        relations: [TransactionRelation],
        settlements: [AASettlement]
    ) -> [LedgerTransaction] {
        let relatedByOriginal = Dictionary(grouping: relations, by: \.originalTransactionID)
        let relatedByIncome = Dictionary(uniqueKeysWithValues: relations
            .filter { $0.amount > 0 }
            .map { ($0.relatedTransactionID, $0) })
        let collectionByTransaction = Dictionary(uniqueKeysWithValues: settlements.map {
            ($0.recoveryTransactionID, $0.amount)
        })
        return result.allTransactions.filter { transaction in
            dynamicContributions(
                transaction: transaction,
                relationsForOriginal: relatedByOriginal[transaction.id] ?? [],
                relatedIncome: relatedByIncome[transaction.id],
                collectionAmount: collectionByTransaction[transaction.id]
            ).contains { $0.category == category }
        }
        .sorted { sort($0, $1, mode: .dateDescending) }
    }

    func categoryAmount(
        _ transaction: LedgerTransaction,
        category: BillSearchDynamicCategory,
        relations: [TransactionRelation],
        settlements: [AASettlement]
    ) -> Decimal? {
        let contributions = dynamicContributions(
            transaction: transaction,
            relationsForOriginal: relations.filter { $0.originalTransactionID == transaction.id },
            relatedIncome: relations.first { $0.amount > 0 && $0.relatedTransactionID == transaction.id },
            collectionAmount: settlements.first { $0.recoveryTransactionID == transaction.id }?.amount
        )
        return contributions.first { $0.category == category }?.amount
    }

    private func matches(
        _ transaction: LedgerTransaction,
        query: BillSearchQuery,
        bookNames: [UUID: String],
        referenceDate: Date
    ) -> Bool {
        guard (query.bookID == nil || transaction.bookID == query.bookID),
              matchesTime(transaction.date, range: query.timeRange, referenceDate: referenceDate),
              matchesAmount(transaction, minimum: query.minimumAmount, maximum: query.maximumAmount),
              (query.accountIDs.isEmpty || transactionAccountIDs(transaction).contains(where: query.accountIDs.contains))
        else { return false }
        let text = [
            transaction.merchantOrCounterparty, transaction.note, transaction.category?.name,
            transaction.sourceAccount?.name, transaction.destinationAccount?.name,
            transaction.bookID.flatMap { bookNames[$0] }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        return query.normalizedTokens.allSatisfy { token in
            if let requestedAmount = DecimalParser.parse(token) {
                // A token made entirely from a valid number expresses an
                // amount search, not a fuzzy text search. Comparing Decimals
                // avoids formatting differences such as `12.9` vs `12.90`
                // and prevents an unrelated note containing "12" from
                // returning a transaction whose amount is 10.
                return abs(primaryAmount(transaction)) == abs(requestedAmount)
            }
            return text.range(
                of: token,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    private func matchesTime(_ date: Date, range: BillSearchTimeRange, referenceDate: Date) -> Bool {
        switch range {
        case .all: return true
        case .today: return calendar.isDate(date, inSameDayAs: referenceDate)
        case .thisWeek: return calendar.isDate(date, equalTo: referenceDate, toGranularity: .weekOfYear)
        case .thisMonth: return calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
        case .thisYear: return calendar.isDate(date, equalTo: referenceDate, toGranularity: .year)
        case let .custom(start, end):
            let start = calendar.startOfDay(for: start)
            let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            return date >= start && date < dayAfterEnd
        }
    }

    private func matchesAmount(_ transaction: LedgerTransaction, minimum: Decimal?, maximum: Decimal?) -> Bool {
        let amount = abs(primaryAmount(transaction))
        return (minimum == nil || amount >= minimum!) && (maximum == nil || amount <= maximum!)
    }

    private func sort(_ lhs: LedgerTransaction, _ rhs: LedgerTransaction, mode: BillSearchSortMode) -> Bool {
        switch mode {
        case .dateDescending:
            return lhs.date == rhs.date ? lhs.id.uuidString > rhs.id.uuidString : lhs.date > rhs.date
        case .dateAscending:
            return lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
        case .amountDescending:
            return abs(primaryAmount(lhs)) == abs(primaryAmount(rhs))
                ? sort(lhs, rhs, mode: .dateDescending)
                : abs(primaryAmount(lhs)) > abs(primaryAmount(rhs))
        case .amountAscending:
            return abs(primaryAmount(lhs)) == abs(primaryAmount(rhs))
                ? sort(lhs, rhs, mode: .dateDescending)
                : abs(primaryAmount(lhs)) < abs(primaryAmount(rhs))
        }
    }

    private func primaryAmount(_ transaction: LedgerTransaction) -> Decimal {
        transaction.sourceAmount ?? transaction.amount ?? .zero
    }

    private func transactionAccountIDs(_ transaction: LedgerTransaction) -> Set<UUID> {
        Set([transaction.sourceAccount?.id, transaction.destinationAccount?.id].compactMap { $0 })
    }

    private func dynamicContributions(
        transaction: LedgerTransaction,
        relationsForOriginal: [TransactionRelation],
        relatedIncome: TransactionRelation?,
        collectionAmount: Decimal?
    ) -> [(category: BillSearchDynamicCategory, amount: Decimal)] {
        var values: [(BillSearchDynamicCategory, Decimal)] = []
        let principal = abs(primaryAmount(transaction))
        if transaction.type == .transfer { values.append((.transfer, principal)) }
        if let discount = transaction.discountAmount, discount > 0 { values.append((.discount, discount)) }
        if transaction.type == .transfer, transaction.destinationAccount?.type == .eWallet {
            values.append((.recharge, principal))
        }
        if transaction.type == .expense, transaction.reimbursementStatus == .pending {
            values.append((.pendingReimbursement, principal))
        }
        let reimbursed = relationsForOriginal.filter { $0.kind == .reimbursement }.reduce(Decimal.zero) { $0 + $1.amount }
        if reimbursed > 0 { values.append((.reimbursed, reimbursed)) }
        let refunded = relationsForOriginal.filter { $0.kind == .refund }.reduce(Decimal.zero) { $0 + $1.amount }
        if refunded > 0 { values.append((.refund, refunded)) }
        if let relatedIncome, relatedIncome.kind == .reimbursement { values.append((.reimbursementIncome, relatedIncome.amount)) }
        if let relatedIncome, relatedIncome.kind == .refund { values.append((.refundIncome, relatedIncome.amount)) }
        if transaction.transferPurpose == .creditCardRepayment { values.append((.repayment, principal)) }
        if let collectionAmount, collectionAmount > 0 { values.append((.collection, collectionAmount)) }
        if let fee = transaction.feeAmount, fee > 0 { values.append((.fee, fee)) }
        return values
    }
}
