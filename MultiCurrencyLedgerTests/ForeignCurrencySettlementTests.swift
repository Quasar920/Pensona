import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class ForeignCurrencySettlementTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var book: LedgerBook!
    private var bankWallet: CurrencyWallet!
    private var cardCNY: CurrencyWallet!
    private var cardUSD: CurrencyWallet!
    private var expenseCategory: LedgerCategory!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema(LedgerSchemaV3.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        book = LedgerBook(name: "外币测试")

        let bank = Account(name: "还款账户", type: .bankCard, book: book)
        let card = Account(
            name: "多币种信用卡",
            type: .creditCard,
            book: book,
            defaultForeignCurrencySettlementMode: .instant,
            defaultSettlementCurrencyCode: SupportedCurrency.CNY.rawValue
        )
        bankWallet = CurrencyWallet(currency: .CNY, balance: 5_000, account: bank)
        cardCNY = CurrencyWallet(currency: .CNY, balance: 0, account: card)
        cardUSD = CurrencyWallet(currency: .USD, balance: 0, account: card)
        expenseCategory = LedgerCategory(
            name: "购物",
            type: .expense,
            symbolName: "cart",
            sortOrder: 0,
            bookID: book.id
        )

        context.insert(book)
        context.insert(bank)
        context.insert(card)
        context.insert(bankWallet)
        context.insert(cardCNY)
        context.insert(cardUSD)
        context.insert(expenseCategory)
        try context.save()
    }

    func testInstantSettlementPostsOnlySettlementCurrencyLiability() throws {
        let transaction = try LedgerService(context: context).create(
            TransactionDraft(
                type: .expense,
                amount: 710,
                sourceWallet: cardCNY,
                category: expenseCategory,
                foreignSettlementMode: .instant,
                foreignOriginalAmount: 100,
                foreignOriginalCurrencyCode: "USD",
                settlementCurrencyCode: "CNY",
                settledAmount: 710
            ),
            bookID: book.id
        )

        XCTAssertEqual(cardCNY.balance, -710)
        XCTAssertEqual(cardUSD.balance, 0)
        XCTAssertEqual(transaction.foreignOriginalAmount, 100)
        XCTAssertEqual(transaction.settlementExchangeRate, Decimal(string: "7.1"))
    }

    func testRepaymentSettlementCreatesForeignLiabilityThenRepaysWithIndependentRate() throws {
        _ = try createRepaymentModeExpense(amount: 100)
        XCTAssertEqual(cardUSD.balance, -100)

        let transaction = try createRepayment(
            settlementAmount: 350,
            foreignAmount: 50,
            feeAmount: 10,
            feeWallet: bankWallet,
            discountAmount: 2,
            discountWallet: cardUSD
        )

        XCTAssertEqual(bankWallet.balance, 4_640)
        XCTAssertEqual(cardUSD.balance, -48)
        XCTAssertEqual(transaction.transferPurpose, .creditCardRepayment)
        XCTAssertEqual(transaction.settlementExchangeRate, 7)
        XCTAssertEqual(transaction.discountCurrencyCode, "USD")

        try LedgerService(context: context).deleteTransaction(transaction)
        XCTAssertEqual(bankWallet.balance, 5_000)
        XCTAssertEqual(cardUSD.balance, -100)

        XCTAssertThrowsError(
            try createRepayment(
                settlementAmount: 700,
                foreignAmount: 100,
                discountAmount: 1,
                discountWallet: cardUSD
            )
        ) { error in
            XCTAssertEqual(
                error as? ForeignCurrencySettlementError,
                .repaymentExceedsOutstanding
            )
        }
        XCTAssertEqual(bankWallet.balance, 5_000)
        XCTAssertEqual(cardUSD.balance, -100)
    }

    func testRepaymentCannotExceedOutstanding() throws {
        _ = try createRepaymentModeExpense(amount: 100)

        XCTAssertThrowsError(
            try createRepayment(settlementAmount: 707, foreignAmount: 101)
        ) { error in
            XCTAssertEqual(
                error as? ForeignCurrencySettlementError,
                .repaymentExceedsOutstanding
            )
        }
        XCTAssertEqual(bankWallet.balance, 5_000)
        XCTAssertEqual(cardUSD.balance, -100)
    }

    func testMultiplePartialRepaymentsKeepSeparateActualRates() throws {
        _ = try createRepaymentModeExpense(amount: 100)

        let first = try createRepayment(settlementAmount: 280, foreignAmount: 40)
        let second = try createRepayment(settlementAmount: 450, foreignAmount: 60)

        XCTAssertEqual(first.settlementExchangeRate, 7)
        XCTAssertEqual(second.settlementExchangeRate, Decimal(string: "7.5"))
        XCTAssertEqual(bankWallet.balance, 4_270)
        XCTAssertEqual(cardUSD.balance, 0)

        XCTAssertThrowsError(
            try createRepayment(settlementAmount: 7, foreignAmount: 1)
        ) { error in
            XCTAssertEqual(
                error as? ForeignCurrencySettlementError,
                .repaymentExceedsOutstanding
            )
        }
    }

    func testForeignInstallmentsRecordEachRateAndLatestDeletionRestoresProgress() throws {
        _ = try createRepaymentModeExpense(amount: 120)
        let service = InstallmentPlanService(context: context)
        let first = try service.createForeignRepaymentPlanAndRecordFirst(
            name: "美元三期",
            bookID: book.id,
            installmentCount: 3,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            settlementAmount: 280,
            sourceWallet: bankWallet,
            destinationWallet: cardUSD
        )

        XCTAssertEqual(first.plan.totalPrincipal, 120)
        XCTAssertEqual(first.plan.nextInstallmentIndex, 1)
        XCTAssertEqual(first.transaction.destinationAmount, 40)
        XCTAssertEqual(first.transaction.settlementExchangeRate, 7)
        XCTAssertEqual(bankWallet.balance, 4_720)
        XCTAssertEqual(cardUSD.balance, -80)

        let second = try service.recordForeignInstallment(
            for: first.plan,
            foreignPrincipal: 40,
            settlementAmount: 300,
            date: Date(timeIntervalSince1970: 1_702_592_000)
        )
        XCTAssertEqual(second.settlementExchangeRate, Decimal(string: "7.5"))
        XCTAssertEqual(first.plan.nextInstallmentIndex, 2)
        XCTAssertEqual(bankWallet.balance, 4_420)
        XCTAssertEqual(cardUSD.balance, -40)

        try LedgerService(context: context).deleteTransaction(second)
        XCTAssertEqual(first.plan.nextInstallmentIndex, 1)
        XCTAssertEqual(bankWallet.balance, 4_720)
        XCTAssertEqual(cardUSD.balance, -80)
    }

    func testBackupRoundTripKeepsSettlementAndDiscountRelationships() throws {
        _ = try createRepaymentModeExpense(amount: 100)
        let repayment = try createRepayment(
            settlementAmount: 280,
            foreignAmount: 40,
            feeAmount: 3,
            feeWallet: bankWallet,
            discountAmount: 2,
            discountWallet: bankWallet
        )

        let data = try BackupService.encode(BackupService.makeDocument(
            context: context,
            baseCurrencyCode: "CNY"
        ))
        let decoded = try BackupService.decode(data)
        let account = try XCTUnwrap(decoded.accounts.first {
            $0.name == "多币种信用卡"
        })
        let transaction = try XCTUnwrap(decoded.transactions.first {
            $0.id == repayment.id
        })

        XCTAssertEqual(account.defaultForeignCurrencySettlementMode, "instant")
        XCTAssertEqual(account.defaultSettlementCurrencyCode, "CNY")
        XCTAssertEqual(transaction.transferPurpose, "creditCardRepayment")
        XCTAssertEqual(transaction.settlementExchangeRate, 7)
        XCTAssertEqual(transaction.discountWalletID, bankWallet.id)
        XCTAssertEqual(transaction.discountCurrencyCode, "CNY")
    }

    private func createRepaymentModeExpense(amount: Decimal) throws -> LedgerTransaction {
        try LedgerService(context: context).create(
            TransactionDraft(
                type: .expense,
                amount: amount,
                sourceWallet: cardUSD,
                category: expenseCategory,
                foreignSettlementMode: .repayment,
                foreignOriginalAmount: amount,
                foreignOriginalCurrencyCode: "USD",
                settlementCurrencyCode: "CNY"
            ),
            bookID: book.id
        )
    }

    private func createRepayment(
        settlementAmount: Decimal,
        foreignAmount: Decimal,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        discountAmount: Decimal? = nil,
        discountWallet: CurrencyWallet? = nil
    ) throws -> LedgerTransaction {
        try LedgerService(context: context).create(
            TransactionDraft(
                type: .transfer,
                amount: settlementAmount,
                sourceWallet: bankWallet,
                destinationWallet: cardUSD,
                destinationAmount: foreignAmount,
                feeAmount: feeAmount,
                feeWallet: feeWallet,
                discountAmount: discountAmount,
                discountWallet: discountWallet,
                transferPurpose: .creditCardRepayment,
                settlementCurrencyCode: "CNY"
            ),
            bookID: book.id
        )
    }
}
