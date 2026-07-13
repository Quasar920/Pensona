import XCTest
@testable import MultiCurrencyLedger

final class CurrencySupportTests: XCTestCase {
    func testCurrencyCatalogContainsMoreThanFiftyISO4217Currencies() {
        XCTAssertGreaterThan(SupportedCurrency.allCases.count, 50)
        XCTAssertEqual(SupportedCurrency(rawValue: "CNY"), .CNY)
        XCTAssertEqual(SupportedCurrency(rawValue: "USD"), .USD)
    }

    func testZeroTwoAndThreeFractionDigitCurrencies() {
        XCTAssertEqual(SupportedCurrency.JPY.fractionDigits, 0)
        XCTAssertEqual(SupportedCurrency.CNY.fractionDigits, 2)
        XCTAssertEqual(SupportedCurrency.KWD.fractionDigits, 3)
        XCTAssertEqual(SupportedCurrency.fractionDigits(for: "unknown"), 2)
    }
}
