import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class EntrySessionStateTests: XCTestCase {
    func testContinuousEntryPreservesKindAccountsAndOriginalTimeButClearsPerEntryFields() {
        let originalDate = Date(timeIntervalSince1970: 42)
        let sourceID = UUID()
        let destinationID = UUID()
        var form = TransactionFormState(kind: .exchange, date: originalDate)
        form.sourceWalletID = sourceID
        form.destinationWalletID = destinationID
        form.categoryID = UUID()
        form.amountText = "100"
        form.destinationAmountText = "13"
        form.exchangeRateText = "0.13"
        form.note = "note"
        form.reimbursementStatus = .pending
        form.aaSplitDraft = AASplitDraft(
            otherPeopleCount: 1,
            calculationMode: .equal,
            othersOwedAmount: 50,
            basedOnAmount: 100
        )

        form.resetForContinuousEntry(now: Date(timeIntervalSince1970: 999))

        XCTAssertEqual(form.kind, .exchange)
        XCTAssertEqual(form.sourceWalletID, sourceID)
        XCTAssertEqual(form.destinationWalletID, destinationID)
        XCTAssertEqual(form.date, originalDate)
        XCTAssertNil(form.categoryID)
        XCTAssertEqual(form.amountText, "")
        XCTAssertEqual(form.destinationAmountText, "")
        XCTAssertEqual(form.exchangeRateText, "")
        XCTAssertEqual(form.note, "")
        XCTAssertEqual(form.reimbursementStatus, .none)
        XCTAssertNil(form.aaSplitDraft)
    }

    func testValidationMapsMissingValuesToTheirInlineFields() {
        var session = EntrySessionState()
        let form = TransactionFormState(kind: .expense)

        XCTAssertFalse(session.validate(form: form, wallets: [], categories: []))
        XCTAssertNotNil(session.validation[.amount])
        XCTAssertNotNil(session.validation[.sourceWallet])
        XCTAssertNotNil(session.validation[.category])
        XCTAssertNil(session.validation.generalMessage)
    }

    func testSubmissionGateRejectsASecondTapUntilTheFirstFinishes() {
        var session = EntrySessionState()
        XCTAssertTrue(session.beginSubmission(intent: .complete))
        XCTAssertFalse(session.beginSubmission(intent: .complete))
        session.finishSubmission()
        XCTAssertTrue(session.beginSubmission(intent: .next))
        XCTAssertEqual(session.saveIntent, .next)
    }

    func testEditModeRetainsOriginalTransactionAndBookIdentity() {
        let transactionID = UUID()
        let bookID = UUID()
        let session = EntrySessionState(mode: .edit(transactionID: transactionID, bookID: bookID))
        XCTAssertEqual(session.mode, .edit(transactionID: transactionID, bookID: bookID))
    }

    func testAllFiveKindsBuildCanonicalDraftsFromTheSharedFormState() throws {
        let sourceAccount = Account(name: "来源", type: .bankCard)
        let targetAccount = Account(name: "目标", type: .bankCard)
        let foreignAccount = Account(name: "外币", type: .bankCard)
        let source = CurrencyWallet(currency: .CNY, balance: 1_000, account: sourceAccount)
        let target = CurrencyWallet(currency: .CNY, balance: 100, account: targetAccount)
        let foreign = CurrencyWallet(currency: .USD, balance: 10, account: foreignAccount)
        let expense = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        let income = LedgerCategory(name: "工资", type: .income, symbolName: "banknote", sortOrder: 0)
        let wallets = [source, target, foreign]
        let categories = [expense, income]

        var expenseForm = TransactionFormState(kind: .expense)
        expenseForm.amountText = "10"
        expenseForm.sourceWalletID = source.id
        expenseForm.categoryID = expense.id
        XCTAssertEqual(try expenseForm.makeDraft(wallets: wallets, categories: categories).type, .expense)

        var incomeForm = TransactionFormState(kind: .income)
        incomeForm.amountText = "20"
        incomeForm.sourceWalletID = source.id
        incomeForm.categoryID = income.id
        XCTAssertEqual(try incomeForm.makeDraft(wallets: wallets, categories: categories).type, .income)

        var transferForm = TransactionFormState(kind: .transfer)
        transferForm.amountText = "30"
        transferForm.sourceWalletID = source.id
        transferForm.destinationWalletID = target.id
        let transfer = try transferForm.makeDraft(wallets: wallets, categories: categories)
        XCTAssertEqual(transfer.destinationAmount, 30)

        var exchangeForm = TransactionFormState(kind: .exchange)
        exchangeForm.amountText = "70"
        exchangeForm.destinationAmountText = "10"
        exchangeForm.sourceWalletID = source.id
        exchangeForm.destinationWalletID = foreign.id
        XCTAssertEqual(try exchangeForm.makeDraft(wallets: wallets, categories: categories).destinationAmount, 10)

        var adjustmentForm = TransactionFormState(kind: .adjustment)
        adjustmentForm.amountText = "40"
        adjustmentForm.sourceWalletID = source.id
        adjustmentForm.adjustmentDirection = .decrease
        XCTAssertEqual(try adjustmentForm.makeDraft(wallets: wallets, categories: categories).adjustmentDirection, .decrease)
    }

    func testFailureKeepsFormInputAndPublishesSpecificReason() {
        var form = TransactionFormState(kind: .expense)
        form.amountText = "88"
        form.note = "必须保留"
        var session = EntrySessionState()
        XCTAssertTrue(session.beginSubmission(intent: .complete))

        session.finishSubmission(error: ValidationError("数据库暂时不可用"))

        XCTAssertEqual(form.amountText, "88")
        XCTAssertEqual(form.note, "必须保留")
        XCTAssertEqual(session.validation.generalMessage, "数据库暂时不可用")
        XCTAssertFalse(session.isSubmitting)
    }
}
