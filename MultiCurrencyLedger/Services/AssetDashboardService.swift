import Foundation
import SwiftData

@MainActor
struct AssetDashboardService {
    let context: ModelContext

    func snapshot(
        baseCurrencyCode: String,
        moduleBookID: UUID? = nil
    ) throws -> AssetDashboardSnapshot {
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [
            SortDescriptor(\Account.sortOrder),
            SortDescriptor(\Account.createdAt)
        ])).filter { !$0.isArchived && !$0.isHidden }
        let rates = try context.fetch(FetchDescriptor<ExchangeRate>())
        let summaryService = AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        let summary = summaryService.summary(for: accounts)
        let rows = accounts.map { account -> AssetAccountRowSnapshot in
            let result = summaryService.value(for: account)
            return AssetAccountRowSnapshot(
                account: account,
                amount: result.value,
                missingCodes: result.missingCodes
            )
        }
        let grouped = Dictionary(grouping: rows) { AssetDashboardGroup.group(for: $0.account.type) }
        let groups = AssetDashboardGroup.allCases.compactMap { group -> AssetAccountGroupSnapshot? in
            guard let rows = grouped[group], !rows.isEmpty else { return nil }
            return AssetAccountGroupSnapshot(
                group: group,
                subtotal: rows.reduce(Decimal.zero) { $0 + $1.amount },
                rows: rows
            )
        }

        return AssetDashboardSnapshot(
            totalAssets: summary.totalAssets,
            modules: try modules(
                accounts: accounts,
                rates: rates,
                baseCurrencyCode: baseCurrencyCode,
                bookID: moduleBookID
            ),
            groups: groups,
            missingCodes: summary.missingCodes
        )
    }

    func transactions(accountID: UUID, bookID: UUID? = nil) throws -> [LedgerTransaction] {
        let descriptor: FetchDescriptor<LedgerTransaction>
        if let bookID {
            descriptor = FetchDescriptor(
                predicate: #Predicate { transaction in
                    (transaction.sourceAccount?.id == accountID
                        || transaction.destinationAccount?.id == accountID
                        || transaction.feeWallet?.account?.id == accountID
                        || transaction.discountWallet?.account?.id == accountID)
                        && transaction.bookID == bookID
                },
                sortBy: [SortDescriptor(\LedgerTransaction.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { transaction in
                    transaction.sourceAccount?.id == accountID
                        || transaction.destinationAccount?.id == accountID
                        || transaction.feeWallet?.account?.id == accountID
                        || transaction.discountWallet?.account?.id == accountID
                },
                sortBy: [SortDescriptor(\LedgerTransaction.date, order: .reverse)]
            )
        }
        return try context.fetch(descriptor)
    }

    private func modules(
        accounts: [Account],
        rates: [ExchangeRate],
        baseCurrencyCode: String,
        bookID: UUID?
    ) throws -> [AssetModuleSnapshot] {
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        let accountService = AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)

        let splits = try context.fetch(FetchDescriptor<AASplit>())
        let settlements = try context.fetch(FetchDescriptor<AASettlement>())
        var aaAmount = Decimal.zero
        var aaCount = 0
        var aaMissing = Set<String>()
        for split in splits {
            let transactionID = split.originalTransactionID
            let transaction = try context.fetch(FetchDescriptor<LedgerTransaction>(
                predicate: #Predicate { $0.id == transactionID }
            )).first
            guard let transaction, bookID == nil || transaction.bookID == bookID else { continue }
            let collected = settlements.lazy
                .filter { $0.splitID == split.id }
                .reduce(Decimal.zero) { $0 + $1.amount }
            let remaining = max(0, split.othersOwedAmount - collected)
            guard remaining > 0 else { continue }
            let code = transaction.sourceCurrencyCode ?? transaction.currencyCode ?? baseCurrencyCode
            if let converted = valuation.value(remaining, currencyCode: code) {
                aaAmount += converted
                aaCount += 1
            } else {
                aaMissing.insert(code)
            }
        }

        let pendingRaw = ReimbursementStatus.pending.rawValue
        let pending = try context.fetch(FetchDescriptor<LedgerTransaction>(
            predicate: #Predicate { transaction in
                transaction.reimbursementStatusRawValue == pendingRaw
            }
        )).filter { bookID == nil || $0.bookID == bookID }
        let relations = try context.fetch(FetchDescriptor<TransactionRelation>())
        var reimbursementAmount = Decimal.zero
        var reimbursementMissing = Set<String>()
        var reimbursementCount = 0
        for transaction in pending {
            let recovered = relations.lazy.filter {
                $0.originalTransactionID == transaction.id && $0.kind == .reimbursement
            }.reduce(Decimal.zero) { $0 + $1.amount }
            let remaining = max(0, (transaction.sourceAmount ?? transaction.amount ?? 0) - recovered)
            guard remaining > 0 else { continue }
            let code = transaction.sourceCurrencyCode ?? transaction.currencyCode ?? baseCurrencyCode
            if let converted = valuation.value(remaining, currencyCode: code) {
                reimbursementAmount += converted
                reimbursementCount += 1
            } else {
                reimbursementMissing.insert(code)
            }
        }

        let scopedAccounts = accounts.filter { account in
            guard let bookID else { return true }
            return account.book?.id == bookID
        }
        let borrowedRows = scopedAccounts.filter { $0.type == .payable }
        let lentRows = scopedAccounts.filter { $0.type == .receivable }
        let borrowed = borrowedRows.reduce(Decimal.zero) {
            $0 + abs(accountService.value(for: $1).value)
        }
        let lent = lentRows.reduce(Decimal.zero) {
            $0 + abs(accountService.value(for: $1).value)
        }

        return [
            AssetModuleSnapshot(kind: .aa, amount: aaAmount, count: aaCount, missingCodes: aaMissing),
            AssetModuleSnapshot(kind: .reimbursement, amount: reimbursementAmount, count: reimbursementCount, missingCodes: reimbursementMissing),
            AssetModuleSnapshot(kind: .borrowed, amount: borrowed, count: borrowedRows.count, missingCodes: []),
            AssetModuleSnapshot(kind: .lent, amount: lent, count: lentRows.count, missingCodes: [])
        ]
    }
}
