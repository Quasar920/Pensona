import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class CategoryAndTagServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testBookScopedCategoryTreeIncludesGlobalSystemCategories() throws {
        let book = LedgerBook(name: "日常")
        let otherBook = LedgerBook(name: "旅行")
        let global = LedgerCategory(
            name: "餐饮",
            type: .expense,
            symbolName: "fork.knife",
            sortOrder: 0,
            isSystem: true
        )
        context.insert(book)
        context.insert(otherBook)
        context.insert(global)
        try context.save()

        let service = CategoryService(context: context)
        let child = try service.create(
            name: "早餐",
            type: .expense,
            symbolName: "sunrise",
            bookID: book.id,
            parent: global
        )
        _ = try service.create(
            name: "机票",
            type: .expense,
            symbolName: "airplane",
            bookID: otherBook.id
        )

        let scoped = try service.scoped(bookID: book.id, type: .expense)
        XCTAssertEqual(Set(scoped.map(\.name)), Set(["餐饮", "早餐"]))
        XCTAssertEqual(try service.children(of: global.id, bookID: book.id, type: .expense).first?.id, child.id)
    }

    func testDuplicateCategoryNameIsRejectedOnlyWithinSameLevel() throws {
        let book = LedgerBook(name: "日常")
        context.insert(book)
        let service = CategoryService(context: context)
        let parent = try service.create(
            name: "餐饮", type: .expense, symbolName: "fork.knife", bookID: book.id
        )
        _ = try service.create(
            name: "早餐", type: .expense, symbolName: "sunrise", bookID: book.id, parent: parent
        )
        XCTAssertThrowsError(try service.create(
            name: " 早餐 ", type: .expense, symbolName: "sunrise", bookID: book.id, parent: parent
        )) { XCTAssertEqual($0 as? CategoryError, .duplicateName) }
        XCTAssertNoThrow(try service.create(
            name: "早餐", type: .expense, symbolName: "sunrise", bookID: book.id
        ))
    }

    func testTagsAreBookScopedAndCanBeAttachedToTransaction() throws {
        let book = LedgerBook(name: "日常")
        let otherBook = LedgerBook(name: "旅行")
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let transaction = LedgerTransaction(
            type: .expense,
            amount: 10,
            sourceAccount: account,
            sourceWallet: wallet,
            sourceAmount: 10,
            sourceCurrencyCode: "CNY"
        )
        context.insert(book)
        context.insert(otherBook)
        context.insert(account)
        context.insert(wallet)
        context.insert(transaction)
        try context.save()

        let service = TagService(context: context)
        let meal = try service.create(name: "工作餐", colorHex: "#123456", bookID: book.id)
        let travel = try service.create(name: "出差", colorHex: "#654321", bookID: otherBook.id)
        try service.setTags([meal], on: transaction)

        XCTAssertEqual(transaction.tags.map(\.id), [meal.id])
        XCTAssertThrowsError(try service.setTags([travel], on: transaction)) {
            XCTAssertEqual($0 as? TagError, .wrongBook)
        }
    }
}
