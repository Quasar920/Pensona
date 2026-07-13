import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class PlanningAndReportingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionPaymentPart.self,
            TransactionRelation.self, ExchangeRate.self, MonthlyBudget.self,
            SavingsGoal.self, SavingsAllocation.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testDisabledWalletStillCountsTowardAssets() {
        let account = Account(name: "银行卡", type: .bankCard)
        let wallet = CurrencyWallet(currency: .CNY, balance: 500, isEnabled: false, account: account)
        context.insert(account)
        context.insert(wallet)

        let result = AssetSummaryService(baseCurrencyCode: "CNY", rates: []).summary(for: [account])

        XCTAssertEqual(result.totalAssets, 500)
    }

    func testReconciliationFindsAndRepairsWalletDriftFromLedger() throws {
        let fixture = makeFixture(balance: 1_000)
        _ = try LedgerService(context: context).createExpense(
            amount: 100,
            wallet: fixture.wallet,
            category: fixture.category,
            date: .now,
            note: nil
        )
        fixture.wallet.balance = 850

        let service = BalanceReconciliationService(context: context)
        let result = try service.result(
            for: fixture.wallet,
            transactions: try context.fetch(FetchDescriptor<LedgerTransaction>())
        )
        XCTAssertEqual(result.expectedBalance, -100)
        XCTAssertEqual(result.difference, -950)

        try service.rebuild(fixture.wallet, transactions: try context.fetch(FetchDescriptor<LedgerTransaction>()))
        XCTAssertEqual(fixture.wallet.balance, -100)
    }

    func testCategoryBudgetCountsOnlyMatchingExpenseAndFee() throws {
        let fixture = makeFixture(balance: 1_000)
        let other = LedgerCategory(
            name: "交通", type: .expense, symbolName: "tram", sortOrder: 1, bookID: fixture.book.id
        )
        context.insert(other)
        _ = try LedgerService(context: context).createExpense(
            amount: 80,
            wallet: fixture.wallet,
            category: fixture.category,
            date: date(2026, 7, 10),
            note: nil
        )
        _ = try LedgerService(context: context).createExpense(
            amount: 20,
            wallet: fixture.wallet,
            category: other,
            date: date(2026, 7, 11),
            note: nil
        )
        let budget = try BudgetService(context: context).upsert(
            amount: 100,
            bookID: fixture.book.id,
            period: .monthly,
            containing: date(2026, 7, 1),
            currencyCode: "CNY",
            categoryID: fixture.category.id
        )

        let status = BudgetStatisticsService(baseCurrencyCode: "CNY", rates: []).status(
            for: budget,
            transactions: try context.fetch(FetchDescriptor<LedgerTransaction>()),
            relations: []
        )

        XCTAssertEqual(status.spent, 80)
        XCTAssertEqual(status.remaining, 20)
    }

    func testSavingsAllocationsNeverMutateWalletOrCreateTransactions() throws {
        let fixture = makeFixture(balance: 1_000)
        let service = SavingsGoalService(context: context)
        let goal = try service.create(
            bookID: fixture.book.id,
            name: "旅行",
            targetAmount: 5_000,
            currencyCode: "CNY",
            targetDate: date(2027, 1, 1)
        )
        _ = try service.allocate(
            600,
            to: goal,
            sourceAccountID: fixture.wallet.account?.id,
            note: "七月"
        )
        _ = try service.allocate(-100, to: goal, note: "临时取用")

        XCTAssertEqual(service.progress(for: goal, allocations: goal.allocations).allocated, 500)
        XCTAssertEqual(fixture.wallet.balance, 1_000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 0)
    }

    func testRefundOffsetsExpenseInsteadOfBecomingOrdinaryIncome() throws {
        let fixture = makeFixture(balance: 1_000)
        let original = try LedgerService(context: context).createExpense(
            amount: 100,
            wallet: fixture.wallet,
            category: fixture.category,
            date: date(2026, 7, 10),
            note: nil
        )
        let related = try LedgerService(context: context).createIncome(
            amount: 30,
            wallet: fixture.wallet,
            category: nil,
            date: date(2026, 7, 11),
            note: "退款"
        )
        let relation = TransactionRelation(
            kind: .refund,
            originalTransactionID: original.id,
            relatedTransactionID: related.id,
            amount: 30
        )
        context.insert(relation)

        let summary = MonthlySummaryService(baseCurrencyCode: "CNY", rates: []).summary(
            for: [original, related],
            month: date(2026, 7, 1),
            relations: [relation]
        )

        XCTAssertEqual(summary.income, 0)
        XCTAssertEqual(summary.expense, 70)
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
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, bookID: book.id
        )
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)
        return (book, wallet, category)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(
            year: year, month: month, day: day, hour: 12
        ))!
    }
}
