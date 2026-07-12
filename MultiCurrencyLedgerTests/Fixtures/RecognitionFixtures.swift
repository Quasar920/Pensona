import Foundation
@testable import MultiCurrencyLedger

struct RecognitionFixture {
    let name: String
    let ocrText: String
    let responseJSON: String
    let expectedReason: RecognitionDecisionReason
    let expectsAutoEntry: Bool
}

enum RecognitionFixtures {
    static let all: [RecognitionFixture] = [
        fixture(
            "cny-expense", "支付成功 餐饮 CNY 28.00 招商银行1234",
            "expense", "28", "CNY", "餐饮", .eligible, true
        ),
        fixture(
            "usd-expense", "Completed Coffee USD 6.50 招商银行1234",
            "expense", "6.50", "USD", "餐饮", .eligible, true
        ),
        fixture(
            "income-opt-out", "工资到账 CNY 8000 招商银行1234",
            "income", "8000", "CNY", "工资", .unsupportedType, false
        ),
        fixture(
            "transfer", "转账成功 CNY 500 招商银行1234",
            "transfer", "500", "CNY", "其他", .unsupportedType, false
        ),
        fixture(
            "refund", "退款成功 CNY 85 招商银行1234",
            "refund", "85", "CNY", "退款", .unsupportedType, false
        ),
        fixture(
            "pending", "处理中 CNY 30 招商银行1234",
            "expense", "30", "CNY", "餐饮", .riskyStatusText, false
        ),
        fixture(
            "unknown-account", "支付成功 CNY 20 尾号9999",
            "expense", "20", "CNY", "餐饮", .accountUnmatched, false,
            accountHint: "尾号9999"
        ),
        fixture(
            "bad-discount", "原价100 优惠10 实付85 CNY 招商银行1234",
            "expense", "85", "CNY", "餐饮", .amountRelationshipMismatch, false,
            original: "100", discount: "10"
        )
    ]

    private static func fixture(
        _ name: String,
        _ ocr: String,
        _ type: String,
        _ amount: String,
        _ currency: String,
        _ category: String,
        _ reason: RecognitionDecisionReason,
        _ auto: Bool,
        original: String? = nil,
        discount: String? = "0",
        accountHint: String = "招商银行 1234"
    ) -> RecognitionFixture {
        let originalJSON = original.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"results":[{"type":"\(type)","paidAmount":"\(amount)","originalAmount":\(originalJSON),"discountAmount":"\(discount ?? "0")","feeAmount":"0","currencyCode":"\(currency)","date":"2026-07-11","time":"12:30","merchantOrCounterparty":"示例商户","sourceAccountHint":"\(accountHint)","destinationAccountHint":null,"categoryCandidate":"\(category)","note":"","confidence":{"type":0.99,"paidAmount":0.99,"currencyCode":0.99,"account":0.99,"category":0.99}}]}
        """
        return RecognitionFixture(
            name: name,
            ocrText: ocr,
            responseJSON: json,
            expectedReason: reason,
            expectsAutoEntry: auto
        )
    }
}
