import XCTest
@testable import MultiCurrencyLedger

final class RecognitionFixtureAcceptanceTests: XCTestCase {
    func testSanitizedFixtureCorpusMatchesExpectedSafetyDecisions() throws {
        let cnyID = UUID(uuidString: "00000000-0000-0000-0000-000000001234")!
        let usdID = UUID(uuidString: "00000000-0000-0000-0000-000000005678")!
        let context = RecognitionRequestContext(
            bookID: UUID(), bookName: "日常账本",
            accounts: [
                .init(walletID: cnyID, accountName: "招商银行 1234", accountNote: nil, currencyCode: "CNY"),
                .init(walletID: usdID, accountName: "招商银行 1234", accountNote: nil, currencyCode: "USD")
            ],
            categories: [
                .init(name: "餐饮", type: .expense),
                .init(name: "其他", type: .expense),
                .init(name: "工资", type: .income),
                .init(name: "退款", type: .income)
            ]
        )
        let evaluator = RecognitionSafetyEvaluator(now: { Self.date("2026-07-11 23:59") })
        let expectedWalletIDs: [SupportedCurrency: UUID] = [.CNY: cnyID, .USD: usdID]

        XCTAssertEqual(RecognitionFixtures.all.count, 8)
        for fixture in RecognitionFixtures.all {
            let envelope = try RecognitionResponseParser().parse(Data(fixture.responseJSON.utf8))
            XCTAssertEqual(envelope.results.count, 1, fixture.name)
            guard envelope.results.count == 1, let candidate = envelope.results.first else {
                return XCTFail("\(fixture.name): expected exactly one parsed result")
            }
            let decision = evaluator.evaluate(
                candidate, ocrText: fixture.ocrText, context: context,
                allowIncomeAutoEntry: false
            )
            switch fixture.expectation {
            case let .autoEligible(walletCurrency):
                guard case let .autoEligible(walletID, normalized) = decision else {
                    return XCTFail("\(fixture.name): expected auto entry, got \(decision)")
                }
                XCTAssertEqual(walletID, expectedWalletIDs[walletCurrency], fixture.name)
                XCTAssertEqual(normalized.currency, walletCurrency, fixture.name)
            case let .notAutoEligible(expectedReason):
                let actual: RecognitionDecisionReason
                switch decision {
                case let .needsConfirmation(reason, _), let .rejected(reason):
                    actual = reason
                case .autoEligible:
                    return XCTFail("\(fixture.name): unsafe auto entry")
                }
                XCTAssertEqual(actual, expectedReason, fixture.name)
            }
        }
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
}
