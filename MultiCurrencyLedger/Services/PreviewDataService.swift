import Foundation
import SwiftData

enum PreviewDataService {
    @MainActor
    static func seedIfRequested(context: ModelContext) throws {
        #if DEBUG || PERFORMANCE_TESTING
        guard ProcessInfo.processInfo.environment["HOME_SAMPLE_DATA"] == "1" else { return }
        guard try context.fetchCount(FetchDescriptor<Account>()) == 0 else { return }

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let food = categories.first { $0.systemLocalizationKey == "category.expense.food" }
        let transit = categories.first { $0.systemLocalizationKey == "category.expense.transport" }
        let shopping = categories.first { $0.systemLocalizationKey == "category.expense.shopping" }
        let salary = categories.first { $0.systemLocalizationKey == "category.income.salary" }
        let travel = categories.first { $0.systemLocalizationKey == "category.expense.travel" }
        let refund = categories.first { $0.systemLocalizationKey == "category.income.refund" }
        guard let book = try context.fetch(FetchDescriptor<LedgerBook>()).first else {
            throw LedgerError.missingBook
        }
        let travelBook = LedgerBook(name: "旅行账本", sortOrder: 1)

        let daily = Account(name: "日常账户", type: .bankCard)
        let savings = Account(name: "储蓄账户", type: .savings)
        let recharge = Account(name: "交通卡", type: .eWallet)
        let credit = Account(name: "招商信用卡", type: .creditCard)
        let investment = Account(name: "指数基金", type: .investment)
        let receivable = Account(name: "朋友借款", type: .receivable)
        let payable = Account(name: "房租待付", type: .payable)
        let cnyDaily = CurrencyWallet(currency: .CNY, balance: 18_500, account: daily)
        let usdDaily = CurrencyWallet(currency: .USD, balance: 1_200, account: daily)
        let cnySavings = CurrencyWallet(currency: .CNY, balance: 2_000, account: savings)
        let cnyRecharge = CurrencyWallet(currency: .CNY, balance: 760, account: recharge)
        let cnyCredit = CurrencyWallet(currency: .CNY, balance: -1_280, account: credit)
        let cnyInvestment = CurrencyWallet(currency: .CNY, balance: 28_600, account: investment)
        let cnyReceivable = CurrencyWallet(currency: .CNY, balance: 2_300, account: receivable)
        let cnyPayable = CurrencyWallet(currency: .CNY, balance: -3_600, account: payable)
        let usdToCNY = ExchangeRate(
            currencyCode: SupportedCurrency.USD.rawValue,
            baseCurrencyCode: SupportedCurrency.CNY.rawValue,
            rate: Decimal(string: "7.20")!
        )
        context.insert(daily)
        context.insert(savings)
        context.insert(recharge)
        context.insert(credit)
        context.insert(investment)
        context.insert(receivable)
        context.insert(payable)
        context.insert(cnyDaily)
        context.insert(usdDaily)
        context.insert(cnySavings)
        context.insert(cnyRecharge)
        context.insert(cnyCredit)
        context.insert(cnyInvestment)
        context.insert(cnyReceivable)
        context.insert(cnyPayable)
        context.insert(usdToCNY)
        context.insert(travelBook)
        try context.save()

        let ledger = LedgerService(context: context)
        _ = try ledger.createIncome(
            bookID: book.id,
            amount: 3_259,
            wallet: cnyDaily,
            category: salary,
            date: .now.addingTimeInterval(-2_400),
            note: "工资到账"
        )
        _ = try ledger.createExpense(
            bookID: book.id,
            amount: 32,
            wallet: cnyDaily,
            category: food,
            date: .now.addingTimeInterval(-5_100),
            note: "星巴克"
        )
        _ = try ledger.createExpense(
            bookID: book.id,
            amount: 6,
            wallet: cnyDaily,
            category: transit,
            date: .now.addingTimeInterval(-9_200),
            note: "地铁出行"
        )
        _ = try ledger.createExpense(
            bookID: book.id,
            amount: 268,
            wallet: cnyDaily,
            category: shopping,
            date: .now.addingTimeInterval(-86_400),
            note: "超市采购"
        )
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        _ = try ledger.createExpense(
            bookID: book.id,
            amount: 600,
            wallet: cnyDaily,
            category: travel,
            date: previousMonth.addingTimeInterval(-172_800),
            note: "酒店预订"
        )
        _ = try ledger.createIncome(
            bookID: book.id,
            amount: 400,
            wallet: cnyDaily,
            category: refund,
            date: previousMonth.addingTimeInterval(-259_200),
            note: "差旅报销"
        )
        let previewState = ProcessInfo.processInfo.environment["HOME_PREVIEW_STATE"]
            ?? ProcessInfo.processInfo.environment["ENTRY_PREVIEW_STATE"]
        let previewBudget: Decimal = previewState == "over-budget" ? 200 : 5_000
        _ = try MonthlyBudgetService(context: context).upsert(
            amount: previewBudget,
            bookID: book.id,
            month: .now,
            currencyCode: SupportedCurrency.CNY.rawValue
        )
        let goalService = SavingsGoalService(context: context)
        let emergencyGoal = try goalService.create(
            bookID: book.id,
            name: "年度旅行",
            targetAmount: 20_000,
            currencyCode: SupportedCurrency.CNY.rawValue,
            targetDate: Calendar.current.date(byAdding: .month, value: 8, to: .now),
            symbolName: "airplane",
            colorHex: "3478F6"
        )
        _ = try goalService.allocate(6_800, to: emergencyGoal, sourceAccountID: daily.id, note: "当前进度")
        _ = try RepaymentReminderService(context: context).create(
            accountID: credit.id,
            currencyCode: SupportedCurrency.CNY.rawValue,
            outstandingAmount: 1_280,
            dueDate: Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now
        )
        #endif
    }
}
