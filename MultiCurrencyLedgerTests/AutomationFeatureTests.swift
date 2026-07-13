import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class AutomationFeatureTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionPaymentPart.self,
            RecurringSchedule.self, RecurringOccurrence.self,
            InstallmentPlan.self, InstallmentOccurrence.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testMonthlyRecurrenceClampsToMonthEndWithoutLosingAnchorDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january31 = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2024, month: 1, day: 31, hour: 9
        )))

        let february = try XCTUnwrap(RecurrenceDateCalculator.next(
            after: january31,
            frequency: .monthly,
            interval: 1,
            anchorDate: january31,
            calendar: calendar
        ))
        let march = try XCTUnwrap(RecurrenceDateCalculator.next(
            after: february,
            frequency: .monthly,
            interval: 1,
            anchorDate: january31,
            calendar: calendar
        ))

        XCTAssertEqual(calendar.component(.day, from: february), 29)
        XCTAssertEqual(calendar.component(.day, from: march), 31)
    }

    func testRecurringGenerationIsIdempotent() throws {
        let fixture = makeFixture(sourceBalance: 1_000)
        let start = date(2024, 1, 31)
        let service = RecurringScheduleService(context: context)
        let schedule = try service.create(
            name: "会员费",
            draft: TransactionDraft(
                type: .expense,
                amount: 10,
                sourceWallet: fixture.source,
                category: fixture.expenseCategory
            ),
            frequency: .monthly,
            interval: 1,
            startDate: start,
            timeZoneIdentifier: "UTC"
        )

        let firstRun = try service.generateDue(for: schedule, through: date(2024, 3, 31, hour: 23))
        let secondRun = try service.generateDue(for: schedule, through: date(2024, 3, 31, hour: 23))

        XCTAssertEqual(firstRun.count, 3)
        XCTAssertTrue(secondRun.isEmpty)
        XCTAssertEqual(fixture.source.balance, 970)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RecurringOccurrence>()).count, 3)
    }

    func testInstallmentAllocationLeavesOnlyFinalPeriodResidual() throws {
        XCTAssertEqual(
            try InstallmentAllocator.allocations(total: 100, count: 3, fractionDigits: 2),
            [Decimal(string: "33.33")!, Decimal(string: "33.33")!, Decimal(string: "33.34")!]
        )
        XCTAssertEqual(
            try InstallmentAllocator.allocations(total: 1_000, count: 3, fractionDigits: 0),
            [333, 333, 334]
        )
    }

    func testBillInstallmentRepaysPrincipalAsTransferAndChargesFeeOnce() throws {
        let fixture = makeFixture(sourceBalance: 1_000, destinationBalance: -1_000)
        let service = InstallmentPlanService(context: context)
        let plan = try service.create(
            name: "信用卡账单分期",
            kind: .bill,
            totalPrincipal: 300,
            totalFee: 30,
            installmentCount: 3,
            startDate: date(2024, 1, 15),
            sourceWallet: fixture.source,
            destinationWallet: fixture.destination
        )

        let generated = try service.generateDue(
            for: plan,
            through: date(2024, 1, 31, hour: 23)
        )

        XCTAssertEqual(generated.count, 1)
        XCTAssertEqual(generated.first?.type, .transfer)
        XCTAssertEqual(generated.first?.sourceAmount, 100)
        XCTAssertEqual(generated.first?.feeAmount, 10)
        XCTAssertEqual(fixture.source.balance, 890)
        XCTAssertEqual(fixture.destination.balance, -900)
    }

    private func makeFixture(
        sourceBalance: Decimal,
        destinationBalance: Decimal = 0
    ) -> (source: CurrencyWallet, destination: CurrencyWallet, expenseCategory: LedgerCategory) {
        let book = LedgerBook(name: "日常")
        let sourceAccount = Account(name: "储蓄卡", type: .bankCard, book: book)
        let destinationAccount = Account(name: "信用卡", type: .creditCard, book: book)
        let source = CurrencyWallet(currency: .CNY, balance: sourceBalance, account: sourceAccount)
        let destination = CurrencyWallet(
            currency: .CNY,
            balance: destinationBalance,
            account: destinationAccount
        )
        let category = LedgerCategory(
            name: "其他", type: .expense, symbolName: "cart", sortOrder: 0, bookID: book.id
        )
        context.insert(book)
        context.insert(sourceAccount)
        context.insert(destinationAccount)
        context.insert(source)
        context.insert(destination)
        context.insert(category)
        return (source, destination, category)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }
}
