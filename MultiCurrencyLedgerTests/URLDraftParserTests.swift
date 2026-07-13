import XCTest
@testable import MultiCurrencyLedger

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
    }

    func testRejectsDuplicateAndInvalidAmountParameters() throws {
        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "multiledger://entry?type=expense&type=income&amount=1&wallet=x"))
        )) { XCTAssertEqual($0 as? URLDraftError, .duplicateParameter("type")) }

        XCTAssertThrowsError(try URLDraftParser().parse(
            XCTUnwrap(URL(string: "multiledger://entry?type=expense&amount=-1&wallet=x"))
        )) { XCTAssertEqual($0 as? URLDraftError, .invalidAmount) }
    }
}
