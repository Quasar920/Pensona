import SwiftData

enum InitialDataService {
    private static let expenseCategories = [
        ("餐饮", "fork.knife"), ("交通", "bus"), ("购物", "bag"),
        ("居住", "house"), ("日用", "cart"), ("娱乐", "gamecontroller"),
        ("医疗", "cross.case"), ("学习", "book"), ("旅行", "airplane"),
        ("人情", "gift"), ("其他", "ellipsis.circle")
    ]

    private static let incomeCategories = [
        ("工资", "banknote"), ("奖金", "trophy"), ("兼职", "briefcase"),
        ("退款", "arrow.uturn.backward.circle"), ("利息", "percent"),
        ("投资收益", "chart.line.uptrend.xyaxis"), ("礼金", "gift"),
        ("其他", "ellipsis.circle")
    ]

    static func seedIfNeeded(context: ModelContext) throws {
        if try context.fetchCount(FetchDescriptor<LedgerCategory>()) == 0 {
            for (index, item) in expenseCategories.enumerated() {
                context.insert(LedgerCategory(
                    name: item.0,
                    type: .expense,
                    symbolName: item.1,
                    sortOrder: index,
                    isSystem: true
                ))
            }
            for (index, item) in incomeCategories.enumerated() {
                context.insert(LedgerCategory(
                    name: item.0,
                    type: .income,
                    symbolName: item.1,
                    sortOrder: index,
                    isSystem: true
                ))
            }
        }

        let books = try context.fetch(FetchDescriptor<LedgerBook>())
        let defaultBook: LedgerBook
        if let first = books.sorted(by: { $0.createdAt < $1.createdAt }).first {
            defaultBook = first
        } else {
            defaultBook = LedgerBook(name: "日常账本")
            context.insert(defaultBook)
        }

        let accounts = try context.fetch(FetchDescriptor<Account>())
        for account in accounts where account.book == nil {
            account.book = defaultBook
            account.updatedAt = .now
        }
        try context.save()
    }
}
