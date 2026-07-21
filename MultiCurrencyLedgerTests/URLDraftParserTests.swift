import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class URLDraftParserTests: XCTestCase {
    func testParsesOnlyThisAppsEntrySchemeIntoConfirmationRequest() throws {
        let url = try XCTUnwrap(URL(string:
            "multiledger://entry?type=expense&amount=28.50&currency=CNY&wallet=%E7%8E%B0%E9%87%91&merchant=%E9%9D%A2%E9%A6%86"
        ))

        let request = try URLDraftParser().parse(url)

        XCTAssertEqual(request.type, .expense)
        XCTAssertEqual(request.amount, Decimal(string: "28.50"))
        XCTAssertEqual(request.currencyCode, "CNY")
        XCTAssertEqual(request.sourceWalletSelector, "现金")
        XCTAssertEqual(request.merchantOrCounterparty, "面馆")
    }

    func testRejectsICostSchemeAndUnknownParameters() throws {
        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "icost://entry?type=expense&amount=1&wallet=x"))
        )) { XCTAssertEqual($0 as? URLDraftError, .unsupportedRoute) }

        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "multiledger://entry?type=expense&amount=1&wallet=x&token=secret"))
        )) { XCTAssertEqual($0 as? URLDraftError, .unknownParameter("token")) }

        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "multiledger://entry?type=expense&amount=1&wallet=x&tags=legacy"))
        )) { XCTAssertEqual($0 as? URLDraftError, .unknownParameter("tags")) }
    }

    func testRejectsDuplicateAndInvalidAmountParameters() throws {
        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "multiledger://entry?type=expense&type=income&amount=1&wallet=x"))
        )) { XCTAssertEqual($0 as? URLDraftError, .duplicateParameter("type")) }

        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "multiledger://entry?type=expense&amount=-1&wallet=x"))
        )) { XCTAssertEqual($0 as? URLDraftError, .invalidAmount) }
    }

    func testResolverUsesPreferredBookWithWalletFromAnotherLegacyBook() throws {
        let legacyBook = LedgerBook(name: "账户旧账本")
        let selectedBook = LedgerBook(name: "当前账本")
        let account = Account(name: "现金", type: .cash, book: legacyBook)
        let wallet = CurrencyWallet(currency: .CNY, account: account)
        let request = try URLDraftParser().parse(XCTUnwrap(URL(string:
            "multiledger://entry?type=expense&amount=28.5&wallet=%E7%8E%B0%E9%87%91"
        )))

        let draft = try URLDraftResolver().resolve(
            request,
            books: [legacyBook, selectedBook],
            wallets: [wallet],
            categories: [],
            preferredBookID: selectedBook.id
        )

        XCTAssertEqual(draft.bookID, selectedBook.id)
        XCTAssertEqual(draft.sourceWallet?.id, wallet.id)
    }
}
