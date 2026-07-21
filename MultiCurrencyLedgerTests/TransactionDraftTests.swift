import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class TransactionDraftTests: XCTestCase {
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

    func testCreateDraftPersistsMerchantAndCanonicalTransactionFields() throws {
        let wallet = makeWallet(name: "现金", currency: .CNY, balance: 500)
        let category = LedgerCategory(
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0
        )
        context.insert(category)
        var draft = TransactionDraft(type: .expense, amount: 68, sourceWallet: wallet)
        draft.category = category
        draft.merchantOrCounterparty = "面馆"
        draft.note = "午餐"

        let transaction = try service.create(draft, bookID: book.id)

        XCTAssertEqual(wallet.balance, 432)
        XCTAssertEqual(transaction.type, .expense)
        XCTAssertEqual(transaction.sourceAmount, 68)
        XCTAssertEqual(transaction.sourceCurrencyCode, "CNY")
        XCTAssertEqual(transaction.merchantOrCounterparty, "面馆")
        XCTAssertEqual(transaction.category?.id, category.id)
    }

    func testReplaceDraftPreservesTransactionIDAndCanChangeTypeWalletAndCategory() throws {
        let source = makeWallet(name: "现金", currency: .CNY, balance: 1_000)
        let destination = makeWallet(name: "银行卡", currency: .CNY, balance: 500)
        let expenseCategory = LedgerCategory(
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0
        )
        let incomeCategory = LedgerCategory(
            name: "工资", type: .income, symbolName: "banknote", sortOrder: 0
        )
        context.insert(expenseCategory)
        context.insert(incomeCategory)

        var originalDraft = TransactionDraft(type: .expense, amount: 100, sourceWallet: source)
        originalDraft.category = expenseCategory
        let original = try service.create(originalDraft, bookID: book.id)
        let originalID = original.id

        var replacement = TransactionDraft(type: .income, amount: 250, sourceWallet: destination)
        replacement.category = incomeCategory
        replacement.merchantOrCounterparty = "公司"
        try service.replaceTransaction(original, with: replacement)

        XCTAssertEqual(original.id, originalID)
        XCTAssertEqual(original.type, .income)
        XCTAssertEqual(original.sourceWallet?.id, destination.id)
        XCTAssertEqual(original.category?.id, incomeCategory.id)
        XCTAssertEqual(original.merchantOrCounterparty, "公司")
        XCTAssertEqual(source.balance, 1_000)
        XCTAssertEqual(destination.balance, 750)
    }

    private func makeWallet(
        name: String,
        currency: SupportedCurrency,
        balance: Decimal
    ) -> CurrencyWallet {
        let account = Account(name: name, type: .bankCard)
        let wallet = CurrencyWallet(currency: currency, balance: balance, account: account)
        context.insert(account)
        context.insert(wallet)
        return wallet
    }
}
