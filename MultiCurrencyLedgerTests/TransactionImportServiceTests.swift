import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class TransactionImportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([
            LedgerBook.self, Account.self, CurrencyWallet.self, LedgerCategory.self,
            LedgerTransaction.self, TransactionTag.self, TransactionPaymentPart.self,
            TransactionRelation.self, TransactionAttachment.self,
            TransactionImportBatch.self, TransactionImportFingerprint.self,
            AASplit.self, AASettlement.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func testCSVDecoderHandlesQuotedCommasAndNewlines() throws {
        let data = Data("日期,金额,备注\r\n2026-07-01,12.5,\"午餐,两人\"\r\n".utf8)
        let table = try SpreadsheetImportDecoder.decode(data: data, fileExtension: "csv")

        XCTAssertEqual(table.headers, ["日期", "金额", "备注"])
        XCTAssertEqual(table.rows, [["2026-07-01", "12.5", "午餐,两人"]])
    }

    func testPreviewCommitDeduplicateAndUndoImportBatch() throws {
        let book = LedgerBook(name: "日常")
        let account = Account(name: "支付宝", type: .eWallet, book: book)
        let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
        let category = LedgerCategory(
            name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0, bookID: book.id
        )
        context.insert(book)
        context.insert(account)
        context.insert(wallet)
        context.insert(category)

        let table = SpreadsheetTable(
            headers: ["交易时间", "收支类型", "金额（元）", "支付方式", "交易分类", "备注"],
            rows: [
                ["2026-07-12 12:30:00", "支出", "¥20.50", "支付宝", "餐饮", "午餐"],
                ["2026-07-12 12:30:00", "支出", "¥20.50", "支付宝", "餐饮", "午餐"]
            ]
        )
        let service = TransactionImportService(context: context)
        let preview = try service.preview(
            table: table,
            sourceName: "支付宝.csv",
            preset: .alipay,
            mapping: .suggested(headers: table.headers, preset: .alipay),
            bookID: book.id,
            defaultWallet: wallet,
            wallets: [wallet],
            categories: [category],
            existingFingerprints: []
        )

        XCTAssertEqual(preview.readyRows.count, 1)
        XCTAssertEqual(preview.duplicateCount, 1)
        let batch = try service.commit(preview)
        XCTAssertEqual(wallet.balance, Decimal(string: "79.5"))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 1)

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        let fingerprints = try context.fetch(FetchDescriptor<TransactionImportFingerprint>())
        try service.undo(batch, transactions: transactions, fingerprints: fingerprints)

        XCTAssertEqual(wallet.balance, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LedgerTransaction>()), 0)
        XCTAssertNotNil(batch.undoneAt)
    }

    func testAmountParserSupportsCommonBankFormats() {
        XCTAssertEqual(TransactionImportService.parseAmount("￥1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(TransactionImportService.parseAmount("(88.00)"), -88)
        XCTAssertEqual(TransactionImportService.parseAmount("1.234,500"), Decimal(string: "1234.500"))
    }
}
