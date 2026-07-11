import Foundation
import SwiftData

enum PreviewDataService {
    @MainActor
    static func seedIfRequested(context: ModelContext) throws {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["HOME_SAMPLE_DATA"] == "1" else { return }
        guard try context.fetchCount(FetchDescriptor<Account>()) == 0 else { return }

        let categories = try context.fetch(FetchDescriptor<LedgerCategory>())
        let food = categories.first { $0.name == "餐饮" }
        let transit = categories.first { $0.name == "交通" }
        let shopping = categories.first { $0.name == "购物" }
        let salary = categories.first { $0.name == "工资" }
        let travel = categories.first { $0.name == "旅行" }
        let refund = categories.first { $0.name == "退款" }
        let book = try context.fetch(FetchDescriptor<LedgerBook>()).first
        let travelBook = LedgerBook(name: "旅行账本", sortOrder: 1)

        let daily = Account(name: "日常账户", type: .bankCard, book: book)
        let savings = Account(name: "储蓄账户", type: .savings, book: book)
        let recharge = Account(name: "交通卡", type: .eWallet, book: book)
        let credit = Account(name: "招商信用卡", type: .creditCard, book: book)
        let investment = Account(name: "指数基金", type: .investment, book: book)
        let receivable = Account(name: "朋友借款", type: .receivable, book: book)
        let payable = Account(name: "房租待付", type: .payable, book: book)
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
            amount: 3_259,
            wallet: cnyDaily,
            category: salary,
            date: .now.addingTimeInterval(-2_400),
            note: "工资到账"
        )
        _ = try ledger.createExpense(
            amount: 32,
            wallet: cnyDaily,
            category: food,
            date: .now.addingTimeInterval(-5_100),
            note: "星巴克"
        )
        _ = try ledger.createExpense(
            amount: 6,
            wallet: cnyDaily,
            category: transit,
            date: .now.addingTimeInterval(-9_200),
            note: "地铁出行"
        )
        _ = try ledger.createExpense(
            amount: 268,
            wallet: cnyDaily,
            category: shopping,
            date: .now.addingTimeInterval(-86_400),
            note: "超市采购"
        )
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        _ = try ledger.createExpense(
            amount: 600,
            wallet: cnyDaily,
            category: travel,
            date: previousMonth.addingTimeInterval(-172_800),
            note: "酒店预订"
        )
        _ = try ledger.createIncome(
            amount: 400,
            wallet: cnyDaily,
            category: refund,
            date: previousMonth.addingTimeInterval(-259_200),
            note: "差旅报销"
        )
        if let book {
            let previewState = ProcessInfo.processInfo.environment["HOME_PREVIEW_STATE"]
                ?? ProcessInfo.processInfo.environment["ENTRY_PREVIEW_STATE"]
            let previewBudget: Decimal = previewState == "over-budget"
                ? 200
                : 5_000
            _ = try MonthlyBudgetService(context: context).upsert(
                amount: previewBudget,
                bookID: book.id,
                month: .now,
                currencyCode: SupportedCurrency.CNY.rawValue
            )
        }
        #endif
    }
}
