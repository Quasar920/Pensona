import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class AssetDashboardServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionRelation.self, ExchangeRate.self,
            AASplit.self, AASettlement.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testMapsApprovedSixGroupsAndKeepsLegacyOtherOnlyWhenPresent() throws {
        let types: [AccountType] = [
            .bankCard, .savings, .creditCard, .cash, .investment,
            .eWallet, .receivable, .payable, .other
        ]
        for (index, type) in types.enumerated() {
            let account = Account(name: type.title, type: type, sortOrder: index)
            context.insert(account)
            context.insert(CurrencyWallet(currency: .CNY, balance: Decimal(index + 1) * 100, account: account))
        }
        try context.save()

        let snapshot = try service.snapshot(baseCurrencyCode: "CNY")

        XCTAssertEqual(snapshot.groups.map(\.group), AssetDashboardGroup.allCases)
        XCTAssertEqual(snapshot.groups.first { $0.group == .bankCards }?.rows.count, 2)
        XCTAssertEqual(snapshot.groups.first { $0.group == .lending }?.rows.count, 2)
        XCTAssertEqual(snapshot.groups.first { $0.group == .legacyOther }?.rows.count, 1)
    }

    func testFourModulesAreGlobalAndCanBeScopedToCurrentBook() throws {
        let firstBook = LedgerBook(name: "日常")
        let secondBook = LedgerBook(name: "旅行")
        let receivable = Account(name: "借出", type: .receivable, book: firstBook)
        let payable = Account(name: "借入", type: .payable, book: secondBook)
        let wallet = CurrencyWallet(currency: .CNY, balance: 1_000, account: receivable)
        context.insert(firstBook)
        context.insert(secondBook)
        context.insert(receivable)
        context.insert(payable)
        context.insert(wallet)
        context.insert(CurrencyWallet(currency: .CNY, balance: -300, account: payable))

        let aaExpense = LedgerTransaction(
            type: .expense, bookID: firstBook.id, amount: 120,
            currencyCode: "CNY", date: .now
        )
        let pending = LedgerTransaction(
            type: .expense, bookID: secondBook.id, reimbursementStatus: .pending,
            amount: 240, currencyCode: "CNY", date: .now
        )
        context.insert(aaExpense)
        context.insert(pending)
        context.insert(AASplit(
            originalTransactionID: aaExpense.id,
            otherPeopleCount: 1,
            calculationMode: .equal,
            othersOwedAmount: 60
        ))
        context.insert(TransactionRelation(
            kind: .reimbursement,
            originalTransactionID: pending.id,
            relatedTransactionID: UUID(),
            amount: 40
        ))
        try context.save()

        let global = try service.snapshot(baseCurrencyCode: "CNY")
        XCTAssertEqual(module(.aa, in: global).amount, 60)
        XCTAssertEqual(module(.reimbursement, in: global).amount, 200)
        XCTAssertEqual(module(.borrowed, in: global).amount, 300)
        XCTAssertEqual(module(.lent, in: global).amount, 1_000)

        let scoped = try service.snapshot(baseCurrencyCode: "CNY", moduleBookID: firstBook.id)
        XCTAssertEqual(module(.aa, in: scoped).amount, 60)
        XCTAssertEqual(module(.reimbursement, in: scoped).amount, 0)
        XCTAssertEqual(module(.borrowed, in: scoped).amount, 0)
        XCTAssertEqual(module(.lent, in: scoped).amount, 1_000)
    }

    func testAccountDetailQueryFetchesOnlyReferencedAccountAndOptionalBook() throws {
        let firstBook = LedgerBook(name: "日常")
        let secondBook = LedgerBook(name: "旅行")
        let account = Account(name: "账户", type: .cash)
        let other = Account(name: "其他", type: .cash)
        context.insert(firstBook)
        context.insert(secondBook)
        context.insert(account)
        context.insert(other)
        let included = LedgerTransaction(type: .expense, bookID: firstBook.id, date: .now, sourceAccount: account)
        let otherBook = LedgerTransaction(type: .expense, bookID: secondBook.id, date: .now, sourceAccount: account)
        let otherAccount = LedgerTransaction(type: .expense, bookID: firstBook.id, date: .now, sourceAccount: other)
        [included, otherBook, otherAccount].forEach(context.insert)
        try context.save()

        XCTAssertEqual(try service.transactions(accountID: account.id).count, 2)
        XCTAssertEqual(
            try service.transactions(accountID: account.id, bookID: firstBook.id).map(\.id),
            [included.id]
        )
    }

    private var service: AssetDashboardService { AssetDashboardService(context: context) }

    private func module(_ kind: AssetModuleKind, in snapshot: AssetDashboardSnapshot) -> AssetModuleSnapshot {
        snapshot.modules.first { $0.kind == kind }!
    }
}
