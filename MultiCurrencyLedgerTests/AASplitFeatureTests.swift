import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class AASplitFeatureTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionPaymentPart.self,
            TransactionRelation.self, TransactionAttachment.self,
            AASplit.self, AASettlement.self, ExchangeRate.self, MonthlyBudget.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testEqualAndCustomCalculationsKeepRemainderWithMe() throws {
        let calculator = AASplitCalculator()

        let equal = try calculator.amounts(
            totalAmount: 100,
            otherPeopleCount: 2,
            mode: .equal,
            customOthersOwedAmount: 0,
            currencyCode: "CNY"
        )
        XCTAssertEqual(equal.othersOwedAmount, Decimal(string: "66.66"))
        XCTAssertEqual(equal.myShareAmount, Decimal(string: "33.34"))

        let custom = try calculator.amounts(
            totalAmount: 300,
            otherPeopleCount: 2,
            mode: .custom,
            customOthersOwedAmount: 180,
            currencyCode: "CNY"
        )
        XCTAssertEqual(custom.othersOwedAmount, 180)
        XCTAssertEqual(custom.myShareAmount, 120)
    }

    func testExpenseSplitAndPartialSettlementKeepStatisticsAtMyShare() throws {
        let fixture = makeFixture(balance: 1_000)
        let date = date(2026, 7, 17)
        let splitDraft = AASplitDraft(
            otherPeopleCount: 2,
            calculationMode: .equal,
            othersOwedAmount: 0,
            note: "聚餐",
            basedOnAmount: 300
        )
        var createdSplit: AASplit?
        let expense = try LedgerService(context: context).create(TransactionDraft(
            type: .expense,
            amount: 300,
            sourceWallet: fixture.wallet,
            date: date,
            merchantOrCounterparty: "聚餐",
            category: fixture.category
        ), bookID: fixture.book.id) { transaction in
            createdSplit = try AASplitService(context: context).upsert(
                splitDraft,
                for: transaction,
                save: false
            )
        }
        let split = try XCTUnwrap(createdSplit)
        XCTAssertEqual(fixture.wallet.balance, 700)
        XCTAssertEqual(split.othersOwedAmount, 200)

        _ = try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 80,
            wallet: fixture.wallet,
            date: date,
            note: "部分收款"
        )
        XCTAssertEqual(fixture.wallet.balance, 780)

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let settlements = try context.fetch(FetchDescriptor<AASettlement>())
        let splits = try context.fetch(FetchDescriptor<AASplit>())
        let summary = MonthlySummaryService(baseCurrencyCode: "CNY", rates: []).summary(
            for: transactions,
            month: date,
            aaSplits: splits,
            aaSettlements: settlements
        )
        XCTAssertEqual(summary.expense, 100)
        XCTAssertEqual(summary.income, 0)

        let interval = Calendar.current.dateInterval(of: .month, for: date)!
        let reportService = ReportQueryService(baseCurrencyCode: "CNY", rates: [])
        let expenseReport = reportService.trend(
            transactions: transactions,
            relations: [],
            interval: interval,
            metric: .expense,
            granularity: .monthly,
            aaSplits: splits,
            aaSettlements: settlements
        )
        let incomeReport = reportService.trend(
            transactions: transactions,
            relations: [],
            interval: interval,
            metric: .income,
            granularity: .monthly,
            aaSplits: splits,
            aaSettlements: settlements
        )
        XCTAssertEqual(expenseReport.total, 100)
        XCTAssertEqual(incomeReport.total, 0)

        let budget = MonthlyBudget(
            scopeKey: "aa-test",
            bookID: fixture.book.id,
            monthStart: interval.start,
            currencyCode: "CNY",
            amount: 500
        )
        let budgetStatus = BudgetStatisticsService(baseCurrencyCode: "CNY", rates: []).status(
            for: budget,
            transactions: transactions,
            relations: [],
            aaSplits: splits
        )
        XCTAssertEqual(budgetStatus.spent, 100)

        let aaSummary = AAQueryService().summary(for: split, settlements: settlements)
        XCTAssertEqual(aaSummary.collectedAmount, 80)
        XCTAssertEqual(aaSummary.remainingAmount, 120)
        XCTAssertEqual(aaSummary.status, .partial)
    }

    func testSettlementDeletionRollsBackWalletAndOriginalDeletionIsGuarded() throws {
        let fixture = makeFixture(balance: 1_000)
        let expense = try LedgerService(context: context).createExpense(
            bookID: fixture.book.id,
            amount: 300,
            wallet: fixture.wallet,
            category: fixture.category,
            date: .now,
            note: nil
        )
        let split = try AASplitService(context: context).upsert(
            AASplitDraft(
                otherPeopleCount: 2,
                calculationMode: .equal,
                othersOwedAmount: 0,
                basedOnAmount: 300
            ),
            for: expense
        )
        _ = try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 80,
            wallet: fixture.wallet,
            date: .now,
            note: nil
        )

        XCTAssertThrowsError(try LedgerService(context: context).deleteTransaction(expense)) {
            XCTAssertEqual($0 as? LedgerError, .aaSettlementExists)
        }
        XCTAssertEqual(fixture.wallet.balance, 780)

        let settlement = try XCTUnwrap(context.fetch(FetchDescriptor<AASettlement>()).first)
        let recovery = try XCTUnwrap(
            context.fetch(FetchDescriptor<LedgerTransaction>()).first {
                $0.id == settlement.recoveryTransactionID
            }
        )
        XCTAssertEqual(recovery.bookID, expense.bookID)
        XCTAssertThrowsError(try LedgerService(context: context).deleteTransaction(recovery)) {
            XCTAssertEqual($0 as? LedgerError, .aaRecoveryManaged)
        }
        XCTAssertThrowsError(try BulkTransactionService(context: context).update(
            [recovery],
            changesCategory: false,
            category: nil,
            changesDate: true,
            date: .now
        )) {
            XCTAssertEqual($0 as? LedgerError, .aaRecoveryManaged)
        }
        try AASettlementService(context: context).delete(settlement)
        XCTAssertEqual(fixture.wallet.balance, 700)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AASettlement>()), 0)

        try LedgerService(context: context).deleteTransaction(expense)
        XCTAssertEqual(fixture.wallet.balance, 1_000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AASplit>()), 0)
    }

    func testOverpaymentCurrencyAndRecoveryConflictsAreRejectedWhileAccountsStayGlobal() throws {
        let fixture = makeFixture(balance: 1_000)
        let expense = try LedgerService(context: context).createExpense(
            bookID: fixture.book.id,
            amount: 300,
            wallet: fixture.wallet,
            category: fixture.category,
            date: .now,
            note: nil
        )
        let split = try AASplitService(context: context).upsert(
            AASplitDraft(
                otherPeopleCount: 2,
                calculationMode: .equal,
                othersOwedAmount: 0,
                basedOnAmount: 300
            ),
            for: expense
        )

        XCTAssertThrowsError(try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 201,
            wallet: fixture.wallet,
            date: .now,
            note: nil
        )) {
            XCTAssertEqual($0 as? AASplitError, .settlementExceedsRemaining)
        }

        let usdAccount = Account(name: "美元账户", type: .cash, book: fixture.book)
        let usdWallet = CurrencyWallet(currency: .USD, balance: 0, account: usdAccount)
        context.insert(usdAccount)
        context.insert(usdWallet)
        XCTAssertThrowsError(try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 10,
            wallet: usdWallet,
            date: .now,
            note: nil
        )) {
            XCTAssertEqual($0 as? AASplitError, .currencyMismatch)
        }

        let otherBook = LedgerBook(name: "旅行")
        let otherAccount = Account(name: "旅行现金", type: .cash, book: otherBook)
        let otherWallet = CurrencyWallet(currency: .CNY, balance: 0, account: otherAccount)
        context.insert(otherBook)
        context.insert(otherAccount)
        context.insert(otherWallet)
        _ = try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 10,
            wallet: otherWallet,
            date: .now,
            note: nil
        )
        XCTAssertEqual(otherWallet.balance, 10)
        let allTransactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let recovery = try XCTUnwrap(allTransactions.first { $0.id != expense.id })
        XCTAssertEqual(recovery.bookID, fixture.book.id)

        let splits = try context.fetch(FetchDescriptor<AASplit>())
        let settlements = try context.fetch(FetchDescriptor<AASettlement>())
        XCTAssertEqual(AAQueryService().items(
            splits: splits,
            settlements: settlements,
            transactions: allTransactions,
            bookID: nil
        ).count, 1)
        XCTAssertEqual(AAQueryService().items(
            splits: splits,
            settlements: settlements,
            transactions: allTransactions,
            bookID: fixture.book.id
        ).count, 1)
        XCTAssertTrue(AAQueryService().items(
            splits: splits,
            settlements: settlements,
            transactions: allTransactions,
            bookID: otherBook.id
        ).isEmpty)

        XCTAssertThrowsError(try TransactionRelationService(context: context).record(
            kind: .reimbursement,
            original: expense,
            amount: 10,
            wallet: fixture.wallet
        )) {
            XCTAssertEqual($0 as? TransactionRelationError, .aaConflict)
        }
    }

    func testCollectedAmountCapsLaterSplitEdits() throws {
        let fixture = makeFixture(balance: 1_000)
        let expense = try LedgerService(context: context).createExpense(
            bookID: fixture.book.id,
            amount: 300,
            wallet: fixture.wallet,
            category: fixture.category,
            date: .now,
            note: nil
        )
        let service = AASplitService(context: context)
        let split = try service.upsert(
            AASplitDraft(
                otherPeopleCount: 2,
                calculationMode: .equal,
                othersOwedAmount: 0,
                basedOnAmount: 300
            ),
            for: expense
        )
        _ = try AASettlementService(context: context).record(
            split: split,
            original: expense,
            amount: 80,
            wallet: fixture.wallet,
            date: .now,
            note: nil
        )

        XCTAssertThrowsError(try service.upsert(
            AASplitDraft(
                otherPeopleCount: 2,
                calculationMode: .custom,
                othersOwedAmount: 70,
                basedOnAmount: 300
            ),
            for: expense
        )) {
            XCTAssertEqual($0 as? AASplitError, .collectedAmountExceedsOwed)
        }

        let usdAccount = Account(name: "美元账户", type: .cash, book: fixture.book)
        let usdWallet = CurrencyWallet(currency: .USD, balance: 500, account: usdAccount)
        context.insert(usdAccount)
        context.insert(usdWallet)
        XCTAssertThrowsError(try LedgerService(context: context).replaceTransaction(
            expense,
            with: TransactionDraft(
                type: .expense,
                amount: 300,
                sourceWallet: usdWallet,
                date: expense.date,
                category: fixture.category
            )
        ) { updated in
            try service.upsert(
                AASplitDraft(
                    otherPeopleCount: 2,
                    calculationMode: .equal,
                    othersOwedAmount: 0,
                    basedOnAmount: 300
                ),
                for: updated,
                save: false
            )
        }) {
            XCTAssertEqual($0 as? AASplitError, .currencyMismatch)
        }
        XCTAssertEqual(expense.sourceWallet?.id, fixture.wallet.id)
        XCTAssertEqual(fixture.wallet.balance, 780)
        XCTAssertEqual(usdWallet.balance, 500)
    }

    private func makeFixture(balance: Decimal) -> (
        book: LedgerBook,
        wallet: CurrencyWallet,
        category: LedgerCategory
    ) {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: balance, account: account)
        let category = LedgerCategory(
            name: "餐饮",
            type: .expense,
            symbolName: "fork.knife",
            sortOrder: 0,
            bookID: book.id
        )
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)
        return (book, wallet, category)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }
}
