import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class LedgerServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: LedgerService!
    private var book: LedgerBook!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, AASplit.self, AASettlement.self,
            ExchangeRate.self, MonthlyBudget.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        book = LedgerBook(name: "测试账本")
        context.insert(book)
        service = LedgerService(context: context)
    }

    func testExpenseIncomeAndDeleteRollback() throws {
        let (_, wallet) = makeWallet(currency: .HKD, balance: 12_000)
        let expense = try service.createExpense(
            bookID: book.id, amount: 80, wallet: wallet, category: nil, date: .now, note: nil
        )
        XCTAssertEqual(wallet.balance, 11_920)

        _ = try service.createIncome(
            bookID: book.id, amount: 500, wallet: wallet, category: nil, date: .now, note: nil
        )
        XCTAssertEqual(wallet.balance, 12_420)

        try service.deleteTransaction(expense)
        XCTAssertEqual(wallet.balance, 12_500)
    }

    func testTransferAndExchangeWithFee() throws {
        let (_, hkd) = makeWallet(currency: .HKD, balance: 12_000)
        let (_, usd) = makeWallet(currency: .USD, balance: 2_000)

        let exchange = try service.createExchange(
            bookID: book.id,
            sourceAmount: 10_000,
            from: hkd,
            destinationAmount: 1_280,
            to: usd,
            feeAmount: 50,
            feeWallet: hkd,
            date: .now,
            note: nil
        )
        XCTAssertEqual(hkd.balance, 1_950)
        XCTAssertEqual(usd.balance, 3_280)
        XCTAssertEqual(exchange.exchangeRate, Decimal(string: "0.128"))

        try service.deleteTransaction(exchange)
        XCTAssertEqual(hkd.balance, 12_000)
        XCTAssertEqual(usd.balance, 2_000)
    }

    func testReplaceReversesOldTransactionBeforeApplyingNewOne() throws {
        let (_, wallet) = makeWallet(currency: .CNY, balance: 1_000)
        let old = try service.createExpense(
            bookID: book.id, amount: 100, wallet: wallet, category: nil, date: .now, note: nil
        )
        let replacement = LedgerTransaction(
            type: .expense,
            amount: 250,
            currencyCode: wallet.currencyCode,
            sourceAccount: wallet.account,
            sourceWallet: wallet,
            sourceAmount: 250,
            sourceCurrencyCode: wallet.currencyCode
        )

        try service.replaceTransaction(old, with: replacement)
        XCTAssertEqual(wallet.balance, 750)
    }

    private func makeWallet(
        currency: SupportedCurrency,
        balance: Decimal
    ) -> (Account, CurrencyWallet) {
        let account = Account(name: UUID().uuidString, type: .bankCard)
        let wallet = CurrencyWallet(currency: currency, balance: balance, account: account)
        context.insert(account)
        context.insert(wallet)
        try? context.save()
        return (account, wallet)
    }

    func testFailedReplacementRollsBackEveryBalanceChange() throws {
        let (_, source) = makeWallet(currency: .CNY, balance: 1_000)
        let (_, destination) = makeWallet(currency: .CNY, balance: 100)
        let old = try service.createTransfer(
            bookID: book.id, amount: 200, from: source, to: destination, date: .now, note: nil
        )
        XCTAssertEqual(source.balance, 800)
        XCTAssertEqual(destination.balance, 300)

        let invalid = LedgerTransaction(
            type: .transfer,
            sourceWallet: source,
            destinationWallet: nil,
            sourceAmount: 400,
            sourceCurrencyCode: "CNY",
            destinationAmount: 400,
            destinationCurrencyCode: "CNY"
        )
        XCTAssertThrowsError(try service.replaceTransaction(old, with: invalid))
        XCTAssertEqual(source.balance, 800)
        XCTAssertEqual(destination.balance, 300)
    }

    func testAccountServiceRejectsDuplicateCurrency() throws {
        let account = Account(name: "Bank", type: .bankCard)
        context.insert(account)
        let accountService = AccountService(context: context)
        _ = try accountService.addWallet(currency: .USD, initialBalance: 10, to: account, bookID: book.id)
        XCTAssertThrowsError(try accountService.addWallet(
            currency: .USD, initialBalance: 0, to: account, bookID: book.id
        )) {
            XCTAssertEqual($0 as? LedgerError, .duplicateCurrency)
        }
    }

    func testLiabilityInitialAmountCreatesNegativeBalanceAndTraceableAdjustment() throws {
        let account = Account(name: "信用账户", type: .creditCard)
        context.insert(account)

        let wallet = try AccountService(context: context).addWallet(
            currency: .CNY,
            initialBalance: 2_000,
            to: account,
            bookID: book.id
        )
        let adjustments = try context.fetch(FetchDescriptor<LedgerTransaction>())

        XCTAssertEqual(wallet.balance, -2_000)
        XCTAssertEqual(adjustments.count, 1)
        XCTAssertEqual(adjustments.first?.type, .adjustment)
        XCTAssertEqual(adjustments.first?.adjustmentDirection, .decrease)
        XCTAssertEqual(adjustments.first?.adjustmentReason, "初始欠款")
    }

    func testHomeValuationConvertsAllBookWalletsToBaseCurrency() throws {
        let book = LedgerBook(name: "Daily")
        let account = Account(name: "Mixed", type: .bankCard, book: book)
        let cny = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let usd = CurrencyWallet(currency: .USD, balance: 10, account: account)
        let rate = ExchangeRate(currencyCode: "USD", baseCurrencyCode: "CNY", rate: 7)
        context.insert(book)
        context.insert(account)
        context.insert(cny)
        context.insert(usd)
        context.insert(rate)
        try context.save()

        let result = ValuationService(baseCurrencyCode: "CNY", rates: [rate])
            .total(for: account.enabledWallets)
        XCTAssertEqual(result.value, 170)
        XCTAssertTrue(result.missingCodes.isEmpty)
    }

    func testEveryAccountTypeMapsIntoSixAssetGroupsWithCanonicalTypes() {
        let expectedMappings: [(AccountType, AssetGroup)] = [
            (.bankCard, .cash),
            (.cash, .cash),
            (.eWallet, .recharge),
            (.creditCard, .credit),
            (.savings, .cash),
            (.investment, .investment),
            (.other, .cash),
            (.receivable, .receivable),
            (.payable, .payable)
        ]

        XCTAssertEqual(expectedMappings.count, AccountType.allCases.count)
        for (accountType, expectedGroup) in expectedMappings {
            XCTAssertEqual(accountType.assetGroup, expectedGroup)
        }
        XCTAssertEqual(
            Set(AccountType.allCases.map { $0.assetGroup.rawValue }),
            Set(AssetGroup.allCases.map(\.rawValue))
        )

        let expectedCanonicalTypes: [(AssetGroup, AccountType)] = [
            (.cash, .cash),
            (.credit, .creditCard),
            (.recharge, .eWallet),
            (.investment, .investment),
            (.receivable, .receivable),
            (.payable, .payable)
        ]
        for (group, expectedType) in expectedCanonicalTypes {
            XCTAssertEqual(group.canonicalAccountType, expectedType)
            XCTAssertEqual(group.canonicalAccountType.assetGroup, group)
        }
    }

    func testAssetSummaryBalancesAssetsLiabilitiesAndOwnerEquity() throws {
        let cashAccount = Account(name: "现金资产", type: .bankCard)
        let creditAccount = Account(name: "信用负债", type: .creditCard)
        let cashWallet = CurrencyWallet(currency: .CNY, balance: 10_000, account: cashAccount)
        let creditWallet = CurrencyWallet(currency: .CNY, balance: -2_000, account: creditAccount)
        context.insert(cashAccount)
        context.insert(creditAccount)
        context.insert(cashWallet)
        context.insert(creditWallet)
        try context.save()

        let result = AssetSummaryService(baseCurrencyCode: "CNY", rates: [])
            .summary(for: [cashAccount, creditAccount])

        XCTAssertEqual(result.totalAssets, 10_000)
        XCTAssertEqual(result.totalLiabilities, 2_000)
        XCTAssertEqual(result.ownerEquity, 8_000)
        XCTAssertEqual(result.totalAssets, result.totalLiabilities + result.ownerEquity)
        XCTAssertTrue(result.missingCodes.isEmpty)
    }

    func testAccountAssetValueConvertsKnownCurrenciesAndReportsMissingRates() throws {
        let account = Account(name: "多币种资产", type: .investment)
        let cny = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let usd = CurrencyWallet(currency: .USD, balance: 10, account: account)
        let eur = CurrencyWallet(currency: .EUR, balance: 5, account: account)
        let usdRate = ExchangeRate(currencyCode: "USD", baseCurrencyCode: "CNY", rate: 7)
        context.insert(account)
        context.insert(cny)
        context.insert(usd)
        context.insert(eur)
        context.insert(usdRate)
        try context.save()

        let result = AssetSummaryService(baseCurrencyCode: "CNY", rates: [usdRate])
            .value(for: account)

        XCTAssertEqual(result.value, 170)
        XCTAssertEqual(result.missingCodes, Set(["EUR"]))
        XCTAssertTrue(result.hasEnabledWallets)
    }

    func testLedgerBookServiceRejectsDuplicateNames() throws {
        let bookService = LedgerBookService(context: context)
        let book = try bookService.createBook(name: "旅行账本")
        XCTAssertEqual(book.name, "旅行账本")
        XCTAssertThrowsError(try bookService.createBook(name: " 旅行账本 "))
    }

    func testDailyRecordCashFlowUsesBaseCurrencyAndExcludesTransfers() throws {
        let income = LedgerTransaction(
            type: .income,
            sourceAmount: 100,
            sourceCurrencyCode: "CNY"
        )
        let expense = LedgerTransaction(
            type: .expense,
            sourceAmount: 10,
            sourceCurrencyCode: "USD"
        )
        let transfer = LedgerTransaction(
            type: .transfer,
            sourceAmount: 500,
            sourceCurrencyCode: "CNY",
            feeAmount: 2,
            feeCurrencyCode: "USD"
        )
        let rate = ExchangeRate(currencyCode: "USD", baseCurrencyCode: "CNY", rate: 7)
        let group = TransactionDayGroup(date: .now, transactions: [income, expense, transfer])

        let result = group.cashFlow(baseCurrencyCode: "CNY", rates: [rate])
        XCTAssertEqual(result.income, 100)
        XCTAssertEqual(result.expense, 84)
    }

    func testMonthlySummaryUsesNaturalMonthBoundaries() {
        let calendar = makeUTCCalendar()
        let transactions = [
            LedgerTransaction(
                type: .income,
                date: isoDate("2026-01-31T23:59:59Z"),
                sourceAmount: 999,
                sourceCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .income,
                date: isoDate("2026-02-01T00:00:00Z"),
                sourceAmount: 100,
                sourceCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .expense,
                date: isoDate("2026-02-28T23:59:59Z"),
                sourceAmount: 30,
                sourceCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .expense,
                date: isoDate("2026-03-01T00:00:00Z"),
                sourceAmount: 888,
                sourceCurrencyCode: "CNY"
            )
        ]

        let result = MonthlySummaryService(
            baseCurrencyCode: "CNY",
            rates: [],
            calendar: calendar
        ).summary(
            for: transactions,
            month: isoDate("2026-02-15T12:00:00Z")
        )

        XCTAssertEqual(result.monthStart, isoDate("2026-02-01T00:00:00Z"))
        XCTAssertEqual(result.income, 100)
        XCTAssertEqual(result.expense, 30)
        XCTAssertTrue(result.hasCompleteConversion)
    }

    func testMonthlySummaryExcludesMovementPrincipalAndIncludesEveryFee() {
        let date = isoDate("2026-02-12T12:00:00Z")
        let rate = ExchangeRate(currencyCode: "USD", baseCurrencyCode: "CNY", rate: 7)
        let transactions = [
            LedgerTransaction(
                type: .income,
                date: date,
                sourceAmount: 100,
                sourceCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .expense,
                date: date,
                sourceAmount: 20,
                sourceCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .adjustment,
                date: date,
                sourceAmount: 900,
                sourceCurrencyCode: "CNY",
                feeAmount: 3,
                feeCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .transfer,
                date: date,
                sourceAmount: 500,
                sourceCurrencyCode: "CNY",
                feeAmount: 2,
                feeCurrencyCode: "USD"
            ),
            LedgerTransaction(
                type: .exchange,
                date: date,
                sourceAmount: 300,
                sourceCurrencyCode: "CNY",
                feeAmount: 4,
                feeCurrencyCode: "CNY"
            )
        ]

        let result = MonthlySummaryService(
            baseCurrencyCode: "CNY",
            rates: [rate],
            calendar: makeUTCCalendar()
        ).summary(for: transactions, month: date, budget: 25)

        XCTAssertEqual(result.income, 100)
        XCTAssertEqual(result.expense, 41)
        XCTAssertEqual(result.budget, 25)
        XCTAssertEqual(result.remainingBudget, -16)
        XCTAssertTrue(result.isOverBudget)
        XCTAssertEqual(result.incomeProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(result.expenseProgress, 0.41, accuracy: 0.0001)
        XCTAssertEqual(result.budgetProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(result.remainingBudgetProgress ?? -1, 0, accuracy: 0.0001)
    }

    func testMonthlySummaryReportsEveryMissingConversion() {
        let date = isoDate("2026-02-12T12:00:00Z")
        let transactions = [
            LedgerTransaction(
                type: .income,
                date: date,
                sourceAmount: 10,
                sourceCurrencyCode: "USD"
            ),
            LedgerTransaction(
                type: .expense,
                date: date,
                sourceAmount: 5,
                sourceCurrencyCode: "CNY"
            ),
            LedgerTransaction(
                type: .transfer,
                date: date,
                sourceAmount: 100,
                sourceCurrencyCode: "CNY",
                feeAmount: 2,
                feeCurrencyCode: "EUR"
            )
        ]

        let result = MonthlySummaryService(
            baseCurrencyCode: "CNY",
            rates: [],
            calendar: makeUTCCalendar()
        ).summary(for: transactions, month: date)

        XCTAssertEqual(result.income, 0)
        XCTAssertEqual(result.expense, 5)
        XCTAssertEqual(result.missingCodes, Set(["USD", "EUR"]))
        XCTAssertFalse(result.hasCompleteConversion)
    }

    func testEmptyMonthlySummaryHasSafeDefaultProgress() {
        let result = MonthlySummaryService(
            baseCurrencyCode: "CNY",
            rates: [],
            calendar: makeUTCCalendar()
        ).summary(
            for: [],
            month: isoDate("2026-02-12T12:00:00Z")
        )

        XCTAssertNil(result.budget)
        XCTAssertNil(result.remainingBudget)
        XCTAssertFalse(result.isOverBudget)
        XCTAssertEqual(result.incomeProgress, 0)
        XCTAssertEqual(result.expenseProgress, 0)
        XCTAssertEqual(result.budgetProgress, 0)
        XCTAssertNil(result.remainingBudgetProgress)
    }

    func testMonthlySummaryReportsClampedRemainingBudgetProgress() {
        let date = isoDate("2026-02-12T12:00:00Z")
        let transactions = [
            LedgerTransaction(
                type: .expense,
                date: date,
                sourceAmount: 1_800,
                sourceCurrencyCode: "CNY"
            )
        ]

        let result = MonthlySummaryService(
            baseCurrencyCode: "CNY",
            rates: [],
            calendar: makeUTCCalendar()
        ).summary(for: transactions, month: date, budget: 5_000)

        XCTAssertEqual(result.budgetProgress, 0.36, accuracy: 0.0001)
        XCTAssertEqual(result.remainingBudgetProgress ?? -1, 0.64, accuracy: 0.0001)
    }

    func testMonthlyBudgetUpsertsAndIsolatesBookMonthAndCurrency() throws {
        let calendar = makeUTCCalendar()
        let budgetService = MonthlyBudgetService(context: context, calendar: calendar)
        let firstBookID = UUID()
        let secondBookID = UUID()
        let february = isoDate("2026-02-07T12:00:00Z")
        let laterInFebruary = isoDate("2026-02-27T12:00:00Z")
        let march = isoDate("2026-03-07T12:00:00Z")

        let first = try budgetService.upsert(
            amount: 1_000,
            bookID: firstBookID,
            month: february,
            currencyCode: "CNY"
        )
        let updated = try budgetService.upsert(
            amount: 1_500,
            bookID: firstBookID,
            month: laterInFebruary,
            currencyCode: " cny "
        )
        _ = try budgetService.upsert(
            amount: 2_000,
            bookID: firstBookID,
            month: march,
            currencyCode: "CNY"
        )
        _ = try budgetService.upsert(
            amount: 3_000,
            bookID: secondBookID,
            month: february,
            currencyCode: "CNY"
        )
        _ = try budgetService.upsert(
            amount: 4_000,
            bookID: firstBookID,
            month: february,
            currencyCode: "USD"
        )

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(updated.amount, 1_500)
        XCTAssertEqual(updated.monthStart, isoDate("2026-02-01T00:00:00Z"))
        XCTAssertEqual(updated.currencyCode, "CNY")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyBudget>()), 4)
        XCTAssertEqual(
            try budgetService.budget(
                bookID: firstBookID,
                month: february,
                currencyCode: "CNY"
            )?.amount,
            1_500
        )
    }

    func testMonthlyBudgetRejectsNonPositiveAmount() throws {
        let budgetService = MonthlyBudgetService(context: context, calendar: makeUTCCalendar())
        let bookID = UUID()
        let month = isoDate("2026-02-07T12:00:00Z")

        XCTAssertThrowsError(try budgetService.upsert(
            amount: 0,
            bookID: bookID,
            month: month,
            currencyCode: "CNY"
        )) {
            XCTAssertEqual($0 as? MonthlyBudgetError, .invalidAmount)
        }
        XCTAssertThrowsError(try budgetService.upsert(
            amount: -1,
            bookID: bookID,
            month: month,
            currencyCode: "CNY"
        ))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MonthlyBudget>()), 0)
    }

    func testExportsProduceReadableFiles() throws {
        let (account, wallet) = makeWallet(currency: .USD, balance: 10)
        let transaction = try service.createExpense(
            bookID: book.id, amount: 2, wallet: wallet, category: nil, date: .now, note: "Lunch"
        )
        let budget = try MonthlyBudgetService(context: context, calendar: makeUTCCalendar()).upsert(
            amount: 2_500,
            bookID: UUID(),
            month: isoDate("2026-02-07T12:00:00Z"),
            currencyCode: "CNY"
        )
        let jsonURL = try ExportService.makeJSONBackup(
            accounts: [account], wallets: [wallet], transactions: [transaction],
            categories: [], rates: [], budgets: [budget], baseCurrencyCode: "CNY"
        )
        let json = try Data(contentsOf: jsonURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 4)
        XCTAssertEqual((root["monthlyBudgets"] as? [[String: Any]])?.count, 1)

        let csvURL = try ExportService.makeCSV(transactions: [transaction])
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("交易类型"))
        XCTAssertTrue(csv.contains("expense"))
        XCTAssertTrue(csv.contains("Lunch"))
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testAcceptanceLedgerSequenceForHSBCHongKong() throws {
        let account = Account(name: "汇丰香港", type: .bankCard)
        let hkd = CurrencyWallet(currency: .HKD, balance: 12_000, account: account)
        let usd = CurrencyWallet(currency: .USD, balance: 2_000, account: account)
        let cny = CurrencyWallet(currency: .CNY, balance: 8_000, account: account)
        context.insert(account); context.insert(hkd); context.insert(usd); context.insert(cny)
        try context.save()

        let expense = try service.createExpense(
            bookID: book.id, amount: 80, wallet: hkd, category: nil, date: .now, note: "餐饮"
        )
        XCTAssertEqual(hkd.balance, 11_920)
        let income = try service.createIncome(
            bookID: book.id, amount: 500, wallet: usd, category: nil, date: .now, note: "收入"
        )
        XCTAssertEqual(usd.balance, 2_500)
        _ = try service.createExchange(
            bookID: book.id,
            sourceAmount: 10_000, from: hkd,
            destinationAmount: 1_280, to: usd,
            feeAmount: 50, feeWallet: hkd,
            date: .now, note: "换汇"
        )
        XCTAssertEqual(hkd.balance, 1_870)
        XCTAssertEqual(usd.balance, 3_780)
        XCTAssertEqual(cny.balance, 8_000)

        let editedExpense = LedgerTransaction(
            type: .expense, amount: 100, currencyCode: "HKD",
            sourceAccount: account, sourceWallet: hkd,
            sourceAmount: 100, sourceCurrencyCode: "HKD"
        )
        try service.replaceTransaction(expense, with: editedExpense)
        XCTAssertEqual(hkd.balance, 1_850)
        try service.deleteTransaction(income)
        XCTAssertEqual(usd.balance, 3_280)
    }
}
