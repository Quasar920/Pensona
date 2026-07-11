import XCTest
@testable import MultiCurrencyLedger

final class RecognitionResponseParserTests: XCTestCase {
    private let parser = RecognitionResponseParser()

    func testParsesPlainAndMarkdownFencedJSON() throws {
        let json = #"{"results":[{"type":"expense","paidAmount":"85.00","originalAmount":"100","discountAmount":"15","feeAmount":"0","currencyCode":"CNY","date":"2026-07-11","time":"12:30","merchantOrCounterparty":"星巴克","sourceAccountHint":"招商银行 1234","destinationAccountHint":null,"categoryCandidate":"餐饮","note":"咖啡","confidence":{"type":0.99,"paidAmount":0.99,"currencyCode":0.99,"account":0.98,"category":0.97}}]}"#

        XCTAssertEqual(try parser.parse(Data(json.utf8)).results.count, 1)
        XCTAssertEqual(
            try parser.parse(Data("```json\n\(json)\n```".utf8)).results.first?.paidAmount,
            "85.00"
        )
    }

    func testRejectsEmptyResultsAndInvalidJSON() {
        XCTAssertThrowsError(try parser.parse(Data(#"{"results":[]}"#.utf8))) {
            XCTAssertEqual($0 as? RecognitionError, .emptyResults)
        }
        XCTAssertThrowsError(try parser.parse(Data("not json".utf8))) {
            XCTAssertEqual($0 as? RecognitionError, .invalidResponse)
        }
    }
}
