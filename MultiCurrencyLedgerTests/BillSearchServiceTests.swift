import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class BillSearchServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionRelation.self, AASplit.self, AASettlement.self
        ])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    func testKeywordUsesNormalizedANDAcrossDifferentSearchFields() throws {
        let book = LedgerBook(name: "旅行账本")
        let account = Account(name: "招商银行", type: .bankCard)
        let coffee = LedgerTransaction(
            type: .expense, bookID: book.id, amount: 38, currencyCode: "CNY",
            note: "购买咖啡", sourceAccount: account
        )
        let onlyCoffee = LedgerTransaction(type: .expense, bookID: book.id, amount: 20, note: "咖啡")
        context.insert(book)
        context.insert(account)
        context.insert(coffee)
        context.insert(onlyCoffee)
        try context.save()

        var query = BillSearchQuery()
        query.keyword = "  招商   COFFEE 咖啡 招商 "
        let result = BillSearchService().search(
            transactions: [coffee, onlyCoffee], books: [book], relations: [], settlements: [], query: query
        )

        XCTAssertEqual(query.normalizedTokens, ["招商", "coffee", "咖啡"])
        XCTAssertEqual(result.allTransactions.map(\.id), [coffee.id])
    }

    func testAmountIsAbsoluteAndMultiAccountUsesOR() throws {
        let book = LedgerBook(name: "日常")
        let cash = Account(name: "现金", type: .cash)
        let bank = Account(name: "银行卡", type: .bankCard)
        let matching = LedgerTransaction(type: .expense, bookID: book.id, amount: -120, sourceAccount: cash)
        let tooSmall = LedgerTransaction(type: .expense, bookID: book.id, amount: 80, sourceAccount: bank)
        context.insert(book)
        context.insert(cash)
        context.insert(bank)
        context.insert(matching)
        context.insert(tooSmall)
        try context.save()

        var query = BillSearchQuery()
        query.minimumAmount = 100
        query.maximumAmount = 150
        query.accountIDs = [cash.id, bank.id]
        let result = BillSearchService().search(
            transactions: [matching, tooSmall], books: [book], relations: [], settlements: [], query: query
        )

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.allTransactions.first?.id, matching.id)
    }

    func testNumericKeywordMatchesExactDecimalAmountInsteadOfText() throws {
        let book = LedgerBook(name: "日常")
        let twelvePointNine = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            amount: 12.9,
            note: "午餐"
        )
        let fivePointNine = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            amount: 5.9,
            note: "饮料"
        )
        let unrelatedTen = LedgerTransaction(
            type: .expense,
            bookID: book.id,
            amount: 10,
            note: "12号消费"
        )
        context.insert(book)
        context.insert(twelvePointNine)
        context.insert(fivePointNine)
        context.insert(unrelatedTen)
        try context.save()

        var query = BillSearchQuery()
        query.keyword = "12.9"
        var result = BillSearchService().search(
            transactions: [twelvePointNine, fivePointNine, unrelatedTen],
            books: [book],
            relations: [],
            settlements: [],
            query: query
        )
        XCTAssertEqual(result.allTransactions.map(\.id), [twelvePointNine.id])

        query.keyword = "5.9"
        result = BillSearchService().search(
            transactions: [twelvePointNine, fivePointNine, unrelatedTen],
            books: [book],
            relations: [],
            settlements: [],
            query: query
        )
        XCTAssertEqual(result.allTransactions.map(\.id), [fivePointNine.id])

        query.keyword = "12"
        result = BillSearchService().search(
            transactions: [twelvePointNine, fivePointNine, unrelatedTen],
            books: [book],
            relations: [],
            settlements: [],
            query: query
        )
        XCTAssertTrue(result.allTransactions.isEmpty)
    }

    func testDynamicSummaryUsesBusinessAmountInsteadOfPrimaryAmount() throws {
        let book = LedgerBook(name: "日常")
        let original = LedgerTransaction(type: .expense, bookID: book.id, amount: 100, feeAmount: 2)
        let refundIncome = LedgerTransaction(type: .income, bookID: book.id, amount: 30)
        let relation = TransactionRelation(
            kind: .refund, originalTransactionID: original.id, relatedTransactionID: refundIncome.id, amount: 30
        )
        context.insert(book)
        context.insert(original)
        context.insert(refundIncome)
        context.insert(relation)
        try context.save()

        let result = BillSearchService().search(
            transactions: [original, refundIncome], books: [book], relations: [relation], settlements: [], query: .init()
        )
        let summaries = Dictionary(uniqueKeysWithValues: result.dynamicSummaries.map { ($0.category, $0) })

        XCTAssertEqual(summaries[.refund]?.amount, 30)
        XCTAssertEqual(summaries[.refundIncome]?.amount, 30)
        XCTAssertEqual(summaries[.fee]?.amount, 2)
        XCTAssertEqual(result.expense.amount, 132)
    }

    func testAmountSortingUsesDateDescendingAsTieBreakerAndPagesResults() throws {
        let book = LedgerBook(name: "日常")
        let older = LedgerTransaction(type: .expense, bookID: book.id, amount: 100, date: .distantPast)
        let newer = LedgerTransaction(type: .expense, bookID: book.id, amount: -100, date: .now)
        context.insert(book)
        context.insert(older)
        context.insert(newer)
        try context.save()
        var query = BillSearchQuery()
        query.sortMode = .amountDescending
        let result = BillSearchService().search(
            transactions: [older, newer], books: [book], relations: [], settlements: [], query: query
        )

        XCTAssertEqual(result.allTransactions.map(\.id), [newer.id, older.id])
        XCTAssertEqual(result.page(offset: 0, size: 1).map(\.id), [newer.id])
        XCTAssertTrue(result.page(offset: 2, size: 50).isEmpty)
    }
}
