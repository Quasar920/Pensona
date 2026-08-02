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
        ), bookID: book.id)

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

    func testUpdatingNoteRefreshesLedgerPresentation() throws {
        let book = LedgerBook(name: "日常")
        let transaction = LedgerTransaction(type: .expense, bookID: book.id)
        context.insert(book)
        context.insert(transaction)
        try context.save()

        var didPostRefresh = false
        let observer = NotificationCenter.default.addObserver(
            forName: .ledgerTransactionsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            didPostRefresh = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try TransactionNoteUpdater.update("  晚餐聚会  ", transaction: transaction, context: context)

        XCTAssertEqual(transaction.note, "晚餐聚会")
        XCTAssertEqual(transaction.displayNote, "晚餐聚会")
        XCTAssertTrue(didPostRefresh)
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
            bookID: book.id,
            from: TransactionDraft(type: .expense, amount: 10, sourceWallet: wallet)
        )

        XCTAssertThrowsError(try service.resolve(template, wallets: [], categories: [])) {
            XCTAssertEqual($0 as? TransactionTemplateError, .invalidReference)
        }
    }

    func testTemplateKeepsSavedBookWhileUsingAGlobalWallet() throws {
        let sourceBook = LedgerBook(name: "账户旧账本")
        let targetBook = LedgerBook(name: "旅行")
        let account = Account(name: "现金", type: .cash, book: sourceBook)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        context.insert(sourceBook)
        context.insert(targetBook)
        context.insert(account)
        context.insert(wallet)

        let service = TransactionTemplateService(context: context)
        let template = try service.create(
            name: "旅行早餐",
            bookID: targetBook.id,
            from: TransactionDraft(type: .expense, amount: 10, sourceWallet: wallet)
        )
        let draft = try service.resolve(template, wallets: [wallet], categories: [])
        let transaction = try LedgerService(context: context).create(draft, bookID: template.bookID)

        XCTAssertEqual(draft.bookID, targetBook.id)
        XCTAssertEqual(transaction.bookID, targetBook.id)
        XCTAssertEqual(transaction.sourceWallet?.id, wallet.id)
    }

    func testRefundAndReimbursementShareOneRecoveryLimit() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "卡", type: .bankCard, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 1_000, account: account)
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        let original = try LedgerService(context: context).createExpense(
            bookID: book.id, amount: 100, wallet: wallet, category: nil, date: .now, note: nil
        )
        let service = TransactionRelationService(context: context)
        let refund = try service.record(kind: .refund, original: original, amount: 60, wallet: wallet)
        let reimbursement = try service.record(
            kind: .reimbursement, original: original, amount: 40, wallet: wallet
        )

        XCTAssertEqual(refund.bookID, original.bookID)
        XCTAssertEqual(reimbursement.bookID, original.bookID)
        XCTAssertEqual(try service.summary(for: original).remaining, 0)
        XCTAssertThrowsError(try service.record(
            kind: .refund, original: original, amount: 1, wallet: wallet
        )) { XCTAssertEqual($0 as? TransactionRelationError, .exceedsOriginalAmount) }
    }

    func testAttachmentUsesTransactionBookInsteadOfAccountsLegacyBook() throws {
        let legacyBook = LedgerBook(name: "账户旧账本")
        let transactionBook = LedgerBook(name: "交易账本")
        let account = Account(name: "卡", type: .bankCard, book: legacyBook)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        context.insert(legacyBook)
        context.insert(transactionBook)
        context.insert(account)
        context.insert(wallet)
        let transaction = try LedgerService(context: context).createExpense(
            bookID: transactionBook.id,
            amount: 10,
            wallet: wallet,
            category: nil,
            date: .now,
            note: nil
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let attachment = try AttachmentService(
            context: context,
            store: AttachmentStore(rootURL: root)
        ).addImage(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            to: transaction
        )

        XCTAssertEqual(attachment.bookID, transactionBook.id)
        XCTAssertTrue(attachment.relativePath.hasPrefix(transactionBook.id.uuidString.lowercased()))
        XCTAssertFalse(attachment.relativePath.hasPrefix(legacyBook.id.uuidString.lowercased()))
    }
}
