import XCTest
@testable import MultiCurrencyLedger

final class RecognitionSafetyEvaluatorTests: XCTestCase {
    private let walletID = UUID()
    private lazy var context = RecognitionRequestContext(
        bookID: UUID(), bookName: "日常账本",
        accounts: [.init(walletID: walletID, accountName: "招商银行 1234", accountNote: nil, currencyCode: "CNY")],
        categories: [.init(name: "餐饮", type: .expense), .init(name: "工资", type: .income)]
    )

    func testHighConfidenceExpenseIsEligible() {
        let decision = evaluator().evaluate(
            candidate(), ocrText: "支付成功 星巴克 招商银行1234 CNY 85.00",
            context: context, allowIncomeAutoEntry: false
        )
        guard case let .autoEligible(id, normalized) = decision else {
            return XCTFail("Expected auto eligible")
        }
        XCTAssertEqual(id, walletID)
        XCTAssertEqual(normalized.paidAmount, 85)
    }

    func testTransferAndAmountMismatchRequireConfirmation() {
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(type: .transfer), ocrText: "转账 CNY 85.00",
            context: context, allowIncomeAutoEntry: false
        )), .unsupportedType)
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(original: "100", discount: "10"),
            ocrText: "支付成功 CNY 85.00", context: context, allowIncomeAutoEntry: false
        )), .amountRelationshipMismatch)
    }

    func testPresentMalformedOptionalAmountsAreRejected() {
        for malformed in ["abc", "--", "85x"] {
            XCTAssertEqual(reason(evaluator().evaluate(
                candidate(original: malformed), ocrText: "支付成功 CNY 85",
                context: context, allowIncomeAutoEntry: false
            )), .invalidAmount)
            XCTAssertEqual(reason(evaluator().evaluate(
                candidate(discount: malformed), ocrText: "支付成功 CNY 85",
                context: context, allowIncomeAutoEntry: false
            )), .invalidAmount)
            XCTAssertEqual(reason(evaluator().evaluate(
                candidate(fee: malformed), ocrText: "支付成功 CNY 85",
                context: context, allowIncomeAutoEntry: false
            )), .invalidAmount)
        }
    }

    func testAmountEvidenceUsesNumericBoundariesAndDecimalEquivalence() {
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(original: nil, discount: nil), ocrText: "支付成功 CNY 185 850 .85 85.00.1",
            context: context, allowIncomeAutoEntry: false
        )), .amountNotVisibleInOCR)
        guard case .autoEligible = evaluator().evaluate(
            candidate(original: nil, discount: nil), ocrText: "支付成功 CNY 85.00",
            context: context, allowIncomeAutoEntry: false
        ) else { return XCTFail("Equivalent decimal token should be visible") }
    }

    func testFutureDateRequiresConfirmation() {
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(date: "2026-07-12"), ocrText: "支付成功 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )), .futureDate)
    }

    func testIncomeRequiresOptInAndExactIncomeCategory() {
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(type: .income), ocrText: "工资 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )), .unsupportedType)
        guard case .autoEligible = evaluator().evaluate(
            candidate(type: .income, original: nil, discount: nil, category: "工资"),
            ocrText: "工资 CNY 85", context: context, allowIncomeAutoEntry: true
        ) else { return XCTFail("Opted-in ordinary income should be eligible") }
    }

    func testRejectsUnsupportedCurrency() {
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(currency: "BTC"), ocrText: "支付成功 BTC 85",
            context: context, allowIncomeAutoEntry: false
        )), .unsupportedCurrency)
    }

    func testRequiresConfirmationForUnknownCategoryAndLowConfidence() {
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(category: "模型自造分类"), ocrText: "支付成功 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )), .categoryUnmatched)
        let low = RecognitionConfidenceDTO(type: 0.99, paidAmount: 0.99, currencyCode: 0.99, account: 0.80, category: 0.99)
        XCTAssertEqual(reason(evaluator().evaluate(
            candidate(confidence: low), ocrText: "支付成功 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )), .lowConfidence)
    }

    func testRiskStatusesNeverAutoEnter() {
        for term in ["退款", "撤销", "处理中", "失败", "还款", "充值", "换汇", "转账"] {
            XCTAssertEqual(reason(evaluator().evaluate(
                candidate(original: nil, discount: nil), ocrText: "\(term) CNY 85",
                context: context, allowIncomeAutoEntry: false
            )), .riskyStatusText)
        }
    }

    func testJPYRelationshipUsesOneYenTolerance() {
        let jpyContext = RecognitionRequestContext(
            bookID: context.bookID, bookName: context.bookName,
            accounts: [.init(walletID: walletID, accountName: "现金", accountNote: nil, currencyCode: "JPY")],
            categories: context.categories
        )
        guard case .autoEligible = evaluator().evaluate(
            candidate(original: "101", discount: "15", currency: "JPY", accountHint: "现金"),
            ocrText: "支付成功 JPY 85", context: jpyContext, allowIncomeAutoEntry: false
        ) else { return XCTFail("One-yen rounding difference should be tolerated") }
    }

    private func evaluator() -> RecognitionSafetyEvaluator {
        RecognitionSafetyEvaluator(now: { self.date("2026-07-11 23:59") })
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func reason(_ decision: RecognitionDecision) -> RecognitionDecisionReason? {
        if case let .needsConfirmation(reason, _) = decision { return reason }
        if case let .rejected(reason) = decision { return reason }
        return nil
    }

    private func candidate(
        type: RecognizedTransactionType = .expense,
        original: String? = "100", discount: String? = "15", fee: String? = "0",
        currency: String = "CNY", category: String? = "餐饮",
        accountHint: String? = "招商银行 1234",
        date: String = "2026-07-11",
        confidence: RecognitionConfidenceDTO = .init(type: 0.99, paidAmount: 0.99, currencyCode: 0.99, account: 0.99, category: 0.99)
    ) -> RecognitionCandidateDTO {
        .init(type: type, paidAmount: "85", originalAmount: original,
              discountAmount: discount, feeAmount: fee, currencyCode: currency,
              date: date, time: "12:30", merchantOrCounterparty: "星巴克",
              sourceAccountHint: accountHint, destinationAccountHint: nil,
              categoryCandidate: category, note: "咖啡", confidence: confidence)
    }
}
