import CoreGraphics
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class ScreenshotRecognitionCoordinatorTests: XCTestCase {
    private let validResponse = Data(#"{"results":[{"type":"expense","paidAmount":"85.00","originalAmount":"100","discountAmount":"15","feeAmount":"0","currencyCode":"CNY","date":"2026-07-11","time":"12:30","merchantOrCounterparty":"星巴克","sourceAccountHint":"招商银行 1234","destinationAccountHint":null,"categoryCandidate":"餐饮","note":"咖啡","confidence":{"type":0.99,"paidAmount":0.99,"currencyCode":0.99,"account":0.99,"category":0.99}}]}"#.utf8)

    func testCoordinatesOneOCRAndAPIPassWithoutWritingLedger() async throws {
        let (book, category, wallet) = Self.makeScope()
        let ocr = CountingOCR()
        let api = StubRecognitionAPIClient(response: validResponse)
        let coordinator = ScreenshotRecognitionCoordinator(ocr: ocr, apiClient: api)

        let analysis = try await coordinator.analyze(
            image: Self.onePixelImage(), book: book, categories: [category],
            allowIncomeAutoEntry: false, now: Self.date("2026-07-11 23:59")
        )

        XCTAssertEqual(analysis.decisions.count, 1)
        guard case .autoEligible = analysis.decisions[0] else {
            return XCTFail("Expected eligible result")
        }
        XCTAssertEqual(ocr.callCount, 1)
        XCTAssertEqual(api.callCount, 1)
        XCTAssertTrue(api.lastRequest?.ocrText.contains("85") == true)
        XCTAssertEqual(wallet.balance, 0)
    }

    func testInjectedNowDrivesRequestAndFutureDateGate() async throws {
        let (book, category, _) = Self.makeScope()
        let injectedNow = Self.date("2026-07-10 23:59")
        let api = StubRecognitionAPIClient(response: validResponse)
        let analysis = try await ScreenshotRecognitionCoordinator(
            ocr: CountingOCR(), apiClient: api,
            evaluator: RecognitionSafetyEvaluator(now: { .distantFuture })
        ).analyze(
            image: Self.onePixelImage(), book: book, categories: [category],
            allowIncomeAutoEntry: false, now: injectedNow
        )

        XCTAssertEqual(api.lastRequest?.requestedAt, injectedNow)
        guard case let .needsConfirmation(reason, _) = analysis.decisions[0] else {
            return XCTFail("Expected future-date confirmation")
        }
        XCTAssertEqual(reason, .futureDate)
    }

    func testEncodedRequestContainsOnlyMinimalDeduplicatedOrderedRemoteContext() throws {
        let (book, category, _) = Self.makeScope(accountNote: "私密备注 NEVER_SEND")
        let duplicateAccount = Account(name: "招商银行 1234", type: .bankCard)
        let duplicateWallet = CurrencyWallet(currency: .CNY)
        duplicateWallet.account = duplicateAccount
        duplicateAccount.wallets = [duplicateWallet]
        duplicateAccount.book = book
        let cash = Account(name: "A现金", type: .cash)
        let usd = CurrencyWallet(currency: .USD)
        usd.account = cash
        cash.wallets = [usd]
        cash.book = book
        book.accounts += [duplicateAccount, cash]
        let duplicateCategory = LedgerCategory(
            name: category.name, type: category.type, symbolName: "xmark", sortOrder: 99
        )
        let income = LedgerCategory(name: "工资", type: .income, symbolName: "banknote", sortOrder: 0)
        let local = RecognitionContextBuilder().makeContext(
            book: book, categories: [income, duplicateCategory, category]
        )
        let request = RecognitionAPIRequest(
            ocrText: "CNY 85", context: .init(localContext: local),
            requestedAt: Self.date("2026-07-11 23:59")
        )

        XCTAssertEqual(request.context.accounts, [
            .init(accountName: "A现金", currencyCode: "USD"),
            .init(accountName: "招商银行 1234", currencyCode: "CNY")
        ])
        XCTAssertEqual(request.context.categories, [
            .init(name: "餐饮", type: .expense), .init(name: "工资", type: .income)
        ])
        let encoded = try JSONEncoder().encode(request)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains(book.id.uuidString))
        XCTAssertFalse(json.contains(duplicateWallet.id.uuidString))
        XCTAssertFalse(json.contains("日常账本"))
        XCTAssertFalse(json.contains("NEVER_SEND"))
        XCTAssertFalse(json.contains("bookID"))
        XCTAssertFalse(json.contains("walletID"))
        XCTAssertFalse(json.contains("accountNote"))
    }

    func testOCRFailurePropagatesWithoutCallingAPIOrChangingBalance() async {
        let (book, category, wallet) = Self.makeScope()
        let api = StubRecognitionAPIClient(response: validResponse)
        do {
            _ = try await ScreenshotRecognitionCoordinator(
                ocr: ThrowingOCR(error: RecognitionError.noRecognizableText), apiClient: api
            ).analyze(image: Self.onePixelImage(), book: book, categories: [category], allowIncomeAutoEntry: false)
            XCTFail("Expected OCR failure")
        } catch {
            XCTAssertEqual(error as? RecognitionError, .noRecognizableText)
        }
        XCTAssertEqual(api.callCount, 0)
        XCTAssertEqual(wallet.balance, 0)
    }

    func testAPITimeoutPropagatesWithoutChangingBalance() async {
        let (book, category, wallet) = Self.makeScope()
        do {
            _ = try await ScreenshotRecognitionCoordinator(
                ocr: CountingOCR(), apiClient: ThrowingRecognitionAPIClient(error: URLError(.timedOut))
            ).analyze(image: Self.onePixelImage(), book: book, categories: [category], allowIncomeAutoEntry: false)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(wallet.balance, 0)
    }

    func testInvalidAPIJSONFailsWithoutChangingBalance() async {
        let (book, category, wallet) = Self.makeScope()
        do {
            _ = try await ScreenshotRecognitionCoordinator(
                ocr: CountingOCR(), apiClient: StubRecognitionAPIClient(response: Data("not json".utf8))
            ).analyze(image: Self.onePixelImage(), book: book, categories: [category], allowIncomeAutoEntry: false)
            XCTFail("Expected invalid response")
        } catch {
            XCTAssertEqual(error as? RecognitionError, .invalidResponse)
        }
        XCTAssertEqual(wallet.balance, 0)
    }

    private static func makeScope(accountNote: String? = nil) -> (LedgerBook, LedgerCategory, CurrencyWallet) {
        let wallet = CurrencyWallet(currency: .CNY)
        let account = Account(name: "招商银行 1234", type: .bankCard, note: accountNote)
        wallet.account = account
        account.wallets = [wallet]
        let book = LedgerBook(name: "日常账本")
        account.book = book
        book.accounts = [account]
        let category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        return (book, category, wallet)
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private static func onePixelImage() -> CGImage {
        let data = Data([255, 255, 255, 255])
        return CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

private final class CountingOCR: ScreenshotOCRServicing {
    private(set) var callCount = 0
    func recognizeText(in image: CGImage) async throws -> OCRDocument {
        callCount += 1
        return OCRDocument(lines: [.init(
            text: "支付成功 星巴克 招商银行1234 CNY 85.00",
            boundingBox: .init(x: 0, y: 0, width: 1, height: 1)
        )])
    }
}

private struct ThrowingOCR: ScreenshotOCRServicing {
    let error: Error
    func recognizeText(in image: CGImage) async throws -> OCRDocument { throw error }
}

private final class StubRecognitionAPIClient: RecognitionAPIClient {
    let response: Data
    private(set) var callCount = 0
    private(set) var lastRequest: RecognitionAPIRequest?
    init(response: Data) { self.response = response }
    func recognize(_ request: RecognitionAPIRequest) async throws -> Data {
        callCount += 1
        lastRequest = request
        return response
    }
}

private final class ThrowingRecognitionAPIClient: RecognitionAPIClient {
    let error: Error
    init(error: Error) { self.error = error }
    func recognize(_ request: RecognitionAPIRequest) async throws -> Data { throw error }
}
