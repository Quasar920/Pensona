import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RichTransactionFeatureTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionPaymentPart.self,
            TransactionTemplate.self, TransactionRelation.self, TransactionAttachment.self,
            AASplit.self, AASettlement.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testSplitExpenseUpdatesEachWalletAndPreservesTotal() throws {
        let book = LedgerBook(name: "日常")
        let firstAccount = Account(name: "现金", type: .cash, book: book)
        let secondAccount = Account(name: "银行卡", type: .bankCard, book: book)
        let first = CurrencyWallet(currency: .CNY, balance: 100, account: firstAccount)
        let second = CurrencyWallet(currency: .CNY, balance: 100, account: secondAccount)
        context.insert(book)
        context.insert(firstAccount)
        context.insert(secondAccount)
        context.insert(first)
        context.insert(second)

        let transaction = try LedgerService(context: context).create(TransactionDraft(
            type: .expense,
            amount: 70,
            sourceWallet: first,
            paymentParts: [
                TransactionPaymentPartDraft(wallet: first, amount: 20),
                TransactionPaymentPartDraft(wallet: second, amount: 50)
            ]
        ))

        XCTAssertEqual(first.balance, 80)
        XCTAssertEqual(second.balance, 50)
        XCTAssertEqual(transaction.paymentParts.count, 2)
    }

    func testSplitPaymentRejectsNonConservingParts() throws {
        let account = Account(name: "现金", type: .cash)
        let other = Account(name: "卡", type: .bankCard)
        let first = CurrencyWallet(currency: .CNY, account: account)
        let second = CurrencyWallet(currency: .CNY, account: other)
        let draft = TransactionDraft(
            type: .expense,
            amount: 70,
            sourceWallet: first,
            paymentParts: [
                TransactionPaymentPartDraft(wallet: first, amount: 20),
                TransactionPaymentPartDraft(wallet: second, amount: 40)
            ]
        )
        XCTAssertThrowsError(try TransactionImpactCalculator().deltas(for: draft)) {
            XCTAssertEqual($0 as? LedgerError, .paymentPartsMismatch)
        }
    }

    func testTemplateResolutionFailsAfterReferencedWalletDisappears() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "现金", type: .cash, book: book)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        let service = TransactionTemplateService(context: context)
        let template = try service.create(
            name: "早餐",
            from: TransactionDraft(type: .expense, amount: 10, sourceWallet: wallet)
        )

        XCTAssertThrowsError(try service.resolve(template, wallets: [], categories: [])) {
            XCTAssertEqual($0 as? TransactionTemplateError, .invalidReference)
        }
    }

    func testRefundAndReimbursementShareOneRecoveryLimit() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "卡", type: .bankCard, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 1_000, account: account)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        let original = try LedgerService(context: context).createExpense(
            amount: 100, wallet: wallet, category: nil, date: .now, note: nil
        )
        let service = TransactionRelationService(context: context)
        _ = try service.record(kind: .refund, original: original, amount: 60, wallet: wallet)
        _ = try service.record(kind: .reimbursement, original: original, amount: 40, wallet: wallet)

        XCTAssertEqual(try service.summary(for: original).remaining, 0)
        XCTAssertThrowsError(try service.record(
            kind: .refund, original: original, amount: 1, wallet: wallet
        )) { XCTAssertEqual($0 as? TransactionRelationError, .exceedsOriginalAmount) }
    }
}
