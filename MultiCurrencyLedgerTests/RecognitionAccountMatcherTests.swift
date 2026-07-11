import XCTest
@testable import MultiCurrencyLedger

final class RecognitionAccountMatcherTests: XCTestCase {
    private let cnyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let usdID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    private var options: [RecognitionAccountOption] {
        [
            RecognitionAccountOption(
                walletID: cnyID,
                accountName: "招商银行 1234",
                accountNote: "工资卡",
                currencyCode: "CNY"
            ),
            RecognitionAccountOption(
                walletID: usdID,
                accountName: "招商银行 1234",
                accountNote: "工资卡",
                currencyCode: "USD"
            )
        ]
    }

    func testMatchesExactNameAndCurrency() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招商银行 1234", currency: .USD, options: options),
            .matched(walletID: usdID)
        )
    }

    func testMatchesLastFourAndBankAlias() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招行尾号1234", currency: .CNY, options: options),
            .matched(walletID: cnyID)
        )
    }

    func testRejectsMissingCurrencyWallet() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招行尾号1234", currency: .EUR, options: options),
            .currencyMismatch
        )
    }

    func testExactNameTakesPrecedenceOverAliasMatch() {
        let exactID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let aliasOnlyID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let candidates = [
            RecognitionAccountOption(
                walletID: aliasOnlyID,
                accountName: "招商银行 5678",
                accountNote: nil,
                currencyCode: "CNY"
            ),
            RecognitionAccountOption(
                walletID: exactID,
                accountName: "招商银行",
                accountNote: nil,
                currencyCode: "CNY"
            )
        ]

        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招行", currency: .CNY, options: candidates),
            .matched(walletID: exactID)
        )
    }

    func testLastFourTakesPrecedenceOverBankAlias() {
        let tailID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let aliasOnlyID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let candidates = [
            RecognitionAccountOption(
                walletID: aliasOnlyID,
                accountName: "招商银行 5678",
                accountNote: nil,
                currencyCode: "CNY"
            ),
            RecognitionAccountOption(
                walletID: tailID,
                accountName: "招商银行 1234",
                accountNote: nil,
                currencyCode: "CNY"
            )
        ]

        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招行尾号1234", currency: .CNY, options: candidates),
            .matched(walletID: tailID)
        )
    }

    func testReportsAmbiguousAliasInDeterministicWalletIDOrder() {
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let duplicate = RecognitionAccountOption(
            walletID: lowerID,
            accountName: "招商银行 5678",
            accountNote: nil,
            currencyCode: "CNY"
        )

        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "招商银行",
                currency: .CNY,
                options: options + [duplicate]
            ),
            .ambiguous(walletIDs: [lowerID, cnyID])
        )
        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "招商银行",
                currency: .CNY,
                options: [duplicate] + options.reversed()
            ),
            .ambiguous(walletIDs: [lowerID, cnyID])
        )
    }

    func testReturnsUnmatchedForBlankOrUnknownHint() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "  ", currency: .CNY, options: options),
            .unmatched
        )
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "未知银行", currency: .CNY, options: options),
            .unmatched
        )
    }

    func testMatchesFinalFourDigitsOfFullCardNumber() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "6225880000001234",
                currency: .CNY,
                options: options
            ),
            .matched(walletID: cnyID)
        )
    }

    func testDoesNotUsePhoneNumberInAccountNoteAsTailEvidence() {
        let phoneNote = RecognitionAccountOption(
            walletID: cnyID,
            accountName: "现金账户",
            accountNote: "预留手机 13800123456",
            currencyCode: "CNY"
        )

        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "1380",
                currency: .CNY,
                options: [phoneNote]
            ),
            .unmatched
        )
    }

    func testDoesNotTreatFourDigitsEmbeddedInLongerRunAsTail() {
        let embeddedPrefix = RecognitionAccountOption(
            walletID: cnyID,
            accountName: "备用账户 9912",
            accountNote: nil,
            currencyCode: "CNY"
        )

        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "99123488",
                currency: .CNY,
                options: [embeddedPrefix]
            ),
            .unmatched
        )
    }

    func testConflictingCandidateTailsDoNotSelectWallet() {
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let candidates = [
            RecognitionAccountOption(
                walletID: cnyID,
                accountName: "招商银行 1234",
                accountNote: nil,
                currencyCode: "CNY"
            ),
            RecognitionAccountOption(
                walletID: secondID,
                accountName: "招商银行 5678",
                accountNote: nil,
                currencyCode: "CNY"
            )
        ]

        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "招行 尾号1234 尾号5678",
                currency: .CNY,
                options: candidates
            ),
            .unmatched
        )
    }

    func testDoesNotTreatYearInChineseDateAsTail() {
        let yearAccount = RecognitionAccountOption(
            walletID: cnyID,
            accountName: "备用账户 2026",
            accountNote: nil,
            currencyCode: "CNY"
        )

        XCTAssertEqual(
            RecognitionAccountMatcher().match(
                hint: "2026年07月11日",
                currency: .CNY,
                options: [yearAccount]
            ),
            .unmatched
        )
    }
}
