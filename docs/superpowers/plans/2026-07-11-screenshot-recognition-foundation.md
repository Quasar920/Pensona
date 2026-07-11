# Screenshot Recognition Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a testable iOS recognition foundation that turns a screenshot into locally extracted OCR text, strictly decoded transaction candidates, and safe auto-entry or confirmation decisions without writing ledger data.

**Architecture:** A thin coordinator composes four isolated units: Apple Vision OCR, a candidate-context builder, an injected recognition API client, and a deterministic safety evaluator. The cloud boundary accepts OCR text and constrained account/category options, while all normalization, matching, validation, and the final eligibility decision remain local. This plan deliberately stops before persistence, `LedgerService` mutation, API gateway deployment, UI, App Intent, or the Shortcuts wrapper.

**Tech Stack:** Swift 5, iOS 17+, SwiftUI project, SwiftData domain models, Vision, UIKit/CoreGraphics, Foundation `Codable`, XCTest, `xcodebuild`.

## Global Constraints

- Keep `IPHONEOS_DEPLOYMENT_TARGET = 17.0` and `SWIFT_VERSION = 5.0`.
- Add no third-party package dependency.
- Do not persist or transmit the source screenshot; only OCR text may cross the injected API-client boundary.
- Do not add API URLs, provider selection, prompts, API keys, App Intent, Shortcuts actions, UI, notifications, or vibration in this phase.
- Do not create, edit, or delete `LedgerTransaction` or mutate any `CurrencyWallet.balance` in this phase.
- Treat `paidAmount` as the balance/statistics amount; `originalAmount`, `discountAmount`, and `feeAmount` remain separate.
- Only ordinary `expense` and explicitly allowed ordinary `income` candidates may become auto-entry eligible. Transfers, exchanges, refunds, repayments, recharges, investment movements, failures, pending transactions, and ambiguous multi-amount results require confirmation.
- Model-returned account and category names must match request candidates; never invent a local account, wallet, currency, or category.
- Use Chinese user-facing error copy consistent with the existing app.
- The current workspace is not a Git repository. Before executing this plan, restore the intended repository metadata or explicitly initialize Git. Do not attempt worktrees or the commit steps until that prerequisite is satisfied.

---

## File Structure

Create these focused production files:

- `MultiCurrencyLedger/Recognition/RecognitionTypes.swift` — API DTOs, normalized candidates, decisions, and shared errors.
- `MultiCurrencyLedger/Recognition/RecognitionResponseParser.swift` — Markdown-fence cleanup and strict response decoding.
- `MultiCurrencyLedger/Recognition/RecognitionContextBuilder.swift` — converts one `LedgerBook` plus categories into minimal API candidates.
- `MultiCurrencyLedger/Recognition/ScreenshotOCRService.swift` — screenshot region filtering and Apple Vision OCR.
- `MultiCurrencyLedger/Recognition/RecognitionAccountMatcher.swift` — deterministic wallet matching.
- `MultiCurrencyLedger/Recognition/RecognitionCandidateNormalizer.swift` — converts untrusted DTO strings into typed local values.
- `MultiCurrencyLedger/Recognition/RecognitionSafetyEvaluator.swift` — applies financial safety gates and produces decisions.
- `MultiCurrencyLedger/Recognition/ScreenshotRecognitionCoordinator.swift` — composes OCR, API response parsing, and local decisions.

Create these focused test files:

- `MultiCurrencyLedgerTests/RecognitionResponseParserTests.swift`
- `MultiCurrencyLedgerTests/RecognitionContextBuilderTests.swift`
- `MultiCurrencyLedgerTests/ScreenshotOCRServiceTests.swift`
- `MultiCurrencyLedgerTests/RecognitionAccountMatcherTests.swift`
- `MultiCurrencyLedgerTests/RecognitionSafetyEvaluatorTests.swift`
- `MultiCurrencyLedgerTests/ScreenshotRecognitionCoordinatorTests.swift`
- `MultiCurrencyLedgerTests/Fixtures/RecognitionFixtures.swift`
- `MultiCurrencyLedgerTests/RecognitionFixtureAcceptanceTests.swift`

Create fixture documentation:

- `docs/recognition-fixtures/README.md`

The Xcode project uses file-system-synchronized groups, so source and test files added under the existing target directories should be discovered without hand-editing `project.pbxproj`.

---

### Task 1: Recognition Contract and Strict Response Parser

**Files:**
- Create: `MultiCurrencyLedger/Recognition/RecognitionTypes.swift`
- Create: `MultiCurrencyLedger/Recognition/RecognitionResponseParser.swift`
- Create: `MultiCurrencyLedgerTests/RecognitionResponseParserTests.swift`

**Interfaces:**
- Consumes: raw response `Data` from the future `RecognitionAPIClient`.
- Produces: `RecognitionEnvelopeDTO`, `RecognitionCandidateDTO`, `RecognitionConfidenceDTO`, `RecognizedTransactionType`, `RecognitionError`, and `RecognitionResponseParser.parse(_:)`.

- [ ] **Step 1: Write parser tests for plain JSON, fenced JSON, empty results, and invalid JSON**

```swift
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
```

- [ ] **Step 2: Run the parser tests and verify they fail because the types do not exist**

Run:

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/RecognitionResponseParserTests
```

Expected: `FAIL` with unresolved identifiers such as `RecognitionResponseParser`.

- [ ] **Step 3: Add the complete DTO and decision vocabulary**

Create `MultiCurrencyLedger/Recognition/RecognitionTypes.swift`:

```swift
import Foundation

enum RecognizedTransactionType: String, Codable, Equatable {
    case expense, income, transfer, exchange, refund, unknown
}

struct RecognitionConfidenceDTO: Codable, Equatable {
    let type: Double
    let paidAmount: Double
    let currencyCode: Double
    let account: Double
    let category: Double
}

struct RecognitionCandidateDTO: Codable, Equatable {
    let type: RecognizedTransactionType
    let paidAmount: String
    let originalAmount: String?
    let discountAmount: String?
    let feeAmount: String?
    let currencyCode: String
    let date: String
    let time: String
    let merchantOrCounterparty: String?
    let sourceAccountHint: String?
    let destinationAccountHint: String?
    let categoryCandidate: String?
    let note: String?
    let confidence: RecognitionConfidenceDTO
}

struct RecognitionEnvelopeDTO: Codable, Equatable {
    let results: [RecognitionCandidateDTO]
}

struct NormalizedRecognitionCandidate: Equatable {
    let type: RecognizedTransactionType
    let paidAmount: Decimal
    let originalAmount: Decimal?
    let discountAmount: Decimal
    let feeAmount: Decimal
    let currency: SupportedCurrency
    let occurredAt: Date
    let merchantOrCounterparty: String?
    let sourceAccountHint: String?
    let destinationAccountHint: String?
    let categoryCandidate: String?
    let note: String?
    let confidence: RecognitionConfidenceDTO
}

enum RecognitionDecisionReason: String, Error, Equatable {
    case eligible
    case unsupportedType
    case invalidAmount
    case unsupportedCurrency
    case invalidDate
    case amountNotVisibleInOCR
    case amountRelationshipMismatch
    case riskyStatusText
    case accountUnmatched
    case accountAmbiguous
    case currencyWalletMismatch
    case categoryUnmatched
    case lowConfidence
}

enum RecognitionDecision: Equatable {
    case autoEligible(walletID: UUID, candidate: NormalizedRecognitionCandidate)
    case needsConfirmation(reason: RecognitionDecisionReason, candidate: NormalizedRecognitionCandidate?)
    case rejected(reason: RecognitionDecisionReason)
}

enum RecognitionError: LocalizedError, Equatable {
    case invalidResponse
    case emptyResults
    case noRecognizableText

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "识别服务返回了无效数据"
        case .emptyResults: "没有识别到交易记录"
        case .noRecognizableText: "无法读取截图中的交易信息"
        }
    }
}
```

- [ ] **Step 4: Implement fence cleanup and strict decode failure mapping**

Create `MultiCurrencyLedger/Recognition/RecognitionResponseParser.swift`:

```swift
import Foundation

struct RecognitionResponseParser {
    func parse(_ data: Data) throws -> RecognitionEnvelopeDTO {
        guard var text = String(data: data, encoding: .utf8) else {
            throw RecognitionError.invalidResponse
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            guard let firstNewline = text.firstIndex(of: "\n") else {
                throw RecognitionError.invalidResponse
            }
            text = String(text[text.index(after: firstNewline)...])
            if text.hasSuffix("```") { text.removeLast(3) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let cleaned = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RecognitionEnvelopeDTO.self, from: cleaned) else {
            throw RecognitionError.invalidResponse
        }
        guard !envelope.results.isEmpty else { throw RecognitionError.emptyResults }
        return envelope
    }
}
```

- [ ] **Step 5: Run parser tests and the existing suite**

Run the command from Step 2, then:

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B'
```

Expected: parser tests pass; all existing tests pass.

- [ ] **Step 6: Commit the contract and parser**

```bash
git add MultiCurrencyLedger/Recognition/RecognitionTypes.swift \
  MultiCurrencyLedger/Recognition/RecognitionResponseParser.swift \
  MultiCurrencyLedgerTests/RecognitionResponseParserTests.swift
git commit -m "feat: define screenshot recognition contract"
```

---

### Task 2: Minimal Recognition Context from Existing Books

**Files:**
- Create: `MultiCurrencyLedger/Recognition/RecognitionContextBuilder.swift`
- Create: `MultiCurrencyLedgerTests/RecognitionContextBuilderTests.swift`

**Interfaces:**
- Consumes: `LedgerBook`, its `Account.wallets`, and `[LedgerCategory]`.
- Produces: `RecognitionAccountOption`, `RecognitionCategoryOption`, `RecognitionRequestContext`, and `RecognitionContextBuilder.makeContext(book:categories:)`.

- [ ] **Step 1: Write the failing context test**

```swift
import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class RecognitionContextBuilderTests: XCTestCase {
    func testBuildsEnabledWalletAndExactCategoryOptions() throws {
        let book = LedgerBook(name: "日常账本")
        let account = Account(name: "招商银行 1234", type: .bankCard, note: "工资卡", book: book)
        let cny = CurrencyWallet(currency: .CNY, account: account)
        let disabledUSD = CurrencyWallet(currency: .USD, isEnabled: false, account: account)
        account.wallets = [cny, disabledUSD]
        book.accounts = [account]
        let categories = [
            LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0),
            LedgerCategory(name: "工资", type: .income, symbolName: "banknote", sortOrder: 0)
        ]

        let context = RecognitionContextBuilder().makeContext(book: book, categories: categories)

        XCTAssertEqual(context.bookID, book.id)
        XCTAssertEqual(context.accounts.map(\.walletID), [cny.id])
        XCTAssertEqual(context.accounts.first?.accountName, "招商银行 1234")
        XCTAssertEqual(context.categories.map(\.name), ["餐饮", "工资"])
    }
}
```

- [ ] **Step 2: Run the test and verify the context types are missing**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/RecognitionContextBuilderTests
```

Expected: `FAIL` for missing `RecognitionContextBuilder`.

- [ ] **Step 3: Implement the minimal context and deterministic ordering**

Create `MultiCurrencyLedger/Recognition/RecognitionContextBuilder.swift`:

```swift
import Foundation

struct RecognitionAccountOption: Codable, Equatable {
    let walletID: UUID
    let accountName: String
    let accountNote: String?
    let currencyCode: String
}

struct RecognitionCategoryOption: Codable, Equatable {
    let name: String
    let type: CategoryKind
}

struct RecognitionRequestContext: Codable, Equatable {
    let bookID: UUID
    let bookName: String
    let accounts: [RecognitionAccountOption]
    let categories: [RecognitionCategoryOption]
}

struct RecognitionContextBuilder {
    func makeContext(book: LedgerBook, categories: [LedgerCategory]) -> RecognitionRequestContext {
        let accounts = book.accounts
            .flatMap { account in
                account.enabledWallets.map { wallet in
                    RecognitionAccountOption(
                        walletID: wallet.id,
                        accountName: account.name,
                        accountNote: account.note,
                        currencyCode: wallet.currencyCode
                    )
                }
            }
            .sorted {
                ($0.accountName, $0.currencyCode) < ($1.accountName, $1.currencyCode)
            }
        let categoryOptions = categories
            .sorted { ($0.typeRawValue, $0.sortOrder, $0.name) < ($1.typeRawValue, $1.sortOrder, $1.name) }
            .map { RecognitionCategoryOption(name: $0.name, type: $0.type) }
        return RecognitionRequestContext(
            bookID: book.id,
            bookName: book.name,
            accounts: accounts,
            categories: categoryOptions
        )
    }
}
```

- [ ] **Step 4: Run the focused and full suites**

Run the command from Step 2 and then the full-suite command from Task 1 Step 5.

Expected: all tests pass and the disabled USD wallet is absent.

- [ ] **Step 5: Commit the context builder**

```bash
git add MultiCurrencyLedger/Recognition/RecognitionContextBuilder.swift \
  MultiCurrencyLedgerTests/RecognitionContextBuilderTests.swift
git commit -m "feat: build constrained recognition context"
```

---

### Task 3: Local Screenshot OCR with Apple Vision

**Files:**
- Create: `MultiCurrencyLedger/Recognition/ScreenshotOCRService.swift`
- Create: `MultiCurrencyLedgerTests/ScreenshotOCRServiceTests.swift`

**Interfaces:**
- Consumes: `CGImage` supplied by the future App Intent.
- Produces: `OCRDocument`, `ScreenshotOCRServicing.recognizeText(in:)`, and `VisionScreenshotOCRService`.

- [ ] **Step 1: Write a failing OCR integration test using a generated image**

```swift
import UIKit
import XCTest
@testable import MultiCurrencyLedger

final class ScreenshotOCRServiceTests: XCTestCase {
    func testRecognizesTransactionTextFromGeneratedScreenshot() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            "支付成功\n星巴克\nCNY 85.00".draw(
                in: CGRect(x: 80, y: 220, width: 740, height: 500),
                withAttributes: attributes
            )
        }
        let document = try await VisionScreenshotOCRService().recognizeText(in: image.cgImage!)
        XCTAssertTrue(document.fullText.contains("星巴克"))
        XCTAssertTrue(document.fullText.contains("85.00"))
    }
}
```

- [ ] **Step 2: Run the test and verify the OCR service is missing**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/ScreenshotOCRServiceTests
```

Expected: `FAIL` for missing `VisionScreenshotOCRService`.

- [ ] **Step 3: Implement Vision OCR and ignore the top 8% status-bar region**

Create `MultiCurrencyLedger/Recognition/ScreenshotOCRService.swift`:

```swift
import CoreGraphics
import Foundation
import Vision

struct OCRLine: Equatable {
    let text: String
    let boundingBox: CGRect
}

struct OCRDocument: Equatable {
    let lines: [OCRLine]
    var fullText: String { lines.map(\.text).joined(separator: "\n") }
}

protocol ScreenshotOCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRDocument
}

struct VisionScreenshotOCRService: ScreenshotOCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRDocument {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { observation -> OCRLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return OCRLine(text: candidate.string, boundingBox: observation.boundingBox)
                    }
                    .sorted {
                        if abs($0.boundingBox.maxY - $1.boundingBox.maxY) > 0.01 {
                            return $0.boundingBox.maxY > $1.boundingBox.maxY
                        }
                        return $0.boundingBox.minX < $1.boundingBox.minX
                    }
                guard !lines.isEmpty else {
                    continuation.resume(throwing: RecognitionError.noRecognizableText)
                    return
                }
                continuation.resume(returning: OCRDocument(lines: lines))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.92)
            do { try VNImageRequestHandler(cgImage: image).perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }
}
```

- [ ] **Step 4: Run the OCR test twice to detect immediate flakiness, then run the full suite**

Run the Step 2 command twice, followed by the full suite.

Expected: both focused runs and the full suite pass.

- [ ] **Step 5: Commit the OCR boundary**

```bash
git add MultiCurrencyLedger/Recognition/ScreenshotOCRService.swift \
  MultiCurrencyLedgerTests/ScreenshotOCRServiceTests.swift
git commit -m "feat: add local screenshot OCR"
```

---

### Task 4: Deterministic Account and Wallet Matcher

**Files:**
- Create: `MultiCurrencyLedger/Recognition/RecognitionAccountMatcher.swift`
- Create: `MultiCurrencyLedgerTests/RecognitionAccountMatcherTests.swift`

**Interfaces:**
- Consumes: account hint, recognized currency, and `RecognitionRequestContext.accounts`.
- Produces: `RecognitionAccountMatch` and `RecognitionAccountMatcher.match(hint:currency:options:)`.

- [ ] **Step 1: Write tests for exact name, last four digits, abbreviation, currency mismatch, and ambiguity**

```swift
import XCTest
@testable import MultiCurrencyLedger

final class RecognitionAccountMatcherTests: XCTestCase {
    private let cnyID = UUID()
    private let usdID = UUID()
    private lazy var options = [
        RecognitionAccountOption(walletID: cnyID, accountName: "招商银行 1234", accountNote: "工资卡", currencyCode: "CNY"),
        RecognitionAccountOption(walletID: usdID, accountName: "招商银行 1234", accountNote: "工资卡", currencyCode: "USD")
    ]

    func testMatchesExactNameAndCurrency() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招商银行 1234", currency: .USD, options: options),
            .matched(walletID: usdID)
        )
    }

    func testMatchesLastFourAndBankAliasButRejectsMissingCurrencyWallet() {
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招行尾号1234", currency: .CNY, options: options),
            .matched(walletID: cnyID)
        )
        XCTAssertEqual(
            RecognitionAccountMatcher().match(hint: "招行尾号1234", currency: .EUR, options: options),
            .currencyMismatch
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/RecognitionAccountMatcherTests
```

Expected: `FAIL` for missing matcher types.

- [ ] **Step 3: Implement exact, tail, alias, and currency-safe matching**

Create `MultiCurrencyLedger/Recognition/RecognitionAccountMatcher.swift`:

```swift
import Foundation

enum RecognitionAccountMatch: Equatable {
    case matched(walletID: UUID)
    case ambiguous(walletIDs: [UUID])
    case currencyMismatch
    case unmatched
}

struct RecognitionAccountMatcher {
    private let aliases = [
        "招行": "招商银行", "工行": "工商银行", "建行": "建设银行",
        "农行": "农业银行", "中行": "中国银行", "交行": "交通银行"
    ]

    func match(
        hint: String?,
        currency: SupportedCurrency,
        options: [RecognitionAccountOption]
    ) -> RecognitionAccountMatch {
        guard let rawHint = hint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHint.isEmpty else { return .unmatched }
        let expandedHint = aliases.reduce(rawHint) { value, pair in
            value.replacingOccurrences(of: pair.key, with: pair.value)
        }
        let sameCurrency = options.filter { $0.currencyCode == currency.rawValue }
        if sameCurrency.isEmpty, options.contains(where: { optionMatches($0, hint: expandedHint) }) {
            return .currencyMismatch
        }
        let matches = sameCurrency.filter { optionMatches($0, hint: expandedHint) }
        if matches.count == 1 { return .matched(walletID: matches[0].walletID) }
        if matches.count > 1 { return .ambiguous(walletIDs: matches.map(\.walletID)) }
        return .unmatched
    }

    private func optionMatches(_ option: RecognitionAccountOption, hint: String) -> Bool {
        if hint == option.accountName { return true }
        let searchable = [option.accountName, option.accountNote ?? ""].joined(separator: " ")
        let tail = hint.range(of: #"\d{4}"#, options: .regularExpression).map { String(hint[$0]) }
        if let tail, searchable.contains(tail) {
            return aliases.values.contains(where: { hint.contains($0) && searchable.contains($0) })
                || !aliases.values.contains(where: { hint.contains($0) })
        }
        return aliases.values.contains(where: { hint.contains($0) && searchable.contains($0) })
    }
}
```

- [ ] **Step 4: Add an ambiguity assertion and run focused plus full suites**

Append to the test file:

```swift
func testReportsAmbiguousAliasWithoutTail() {
    XCTAssertEqual(
        RecognitionAccountMatcher().match(hint: "招商银行", currency: .CNY, options: options),
        .matched(walletID: cnyID)
    )
    let duplicate = RecognitionAccountOption(
        walletID: UUID(), accountName: "招商银行 5678", accountNote: nil, currencyCode: "CNY"
    )
    guard case .ambiguous = RecognitionAccountMatcher().match(
        hint: "招商银行", currency: .CNY, options: options + [duplicate]
    ) else { return XCTFail("Expected ambiguous match") }
}
```

Run the focused test and then the full suite. Expected: all pass.

- [ ] **Step 5: Commit the matcher**

```bash
git add MultiCurrencyLedger/Recognition/RecognitionAccountMatcher.swift \
  MultiCurrencyLedgerTests/RecognitionAccountMatcherTests.swift
git commit -m "feat: match recognized accounts to currency wallets"
```

---

### Task 5: Candidate Normalization and Safety Decisions

**Files:**
- Create: `MultiCurrencyLedger/Recognition/RecognitionCandidateNormalizer.swift`
- Create: `MultiCurrencyLedger/Recognition/RecognitionSafetyEvaluator.swift`
- Create: `MultiCurrencyLedgerTests/RecognitionSafetyEvaluatorTests.swift`

**Interfaces:**
- Consumes: `RecognitionCandidateDTO`, OCR text, context, current time, and an account matcher.
- Produces: `RecognitionCandidateNormalizer.normalize(_:timeZone:)` and `RecognitionSafetyEvaluator.evaluate(_:ocrText:context:allowIncomeAutoEntry:)`.

- [ ] **Step 1: Write failing tests for an eligible expense and mandatory-confirmation paths**

```swift
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
        let decision = RecognitionSafetyEvaluator().evaluate(
            candidate(), ocrText: "支付成功 星巴克 招商银行1234 CNY 85.00",
            context: context, allowIncomeAutoEntry: false
        )
        guard case let .autoEligible(id, normalized) = decision else {
            return XCTFail("Expected auto eligible")
        }
        XCTAssertEqual(id, walletID)
        XCTAssertEqual(normalized.paidAmount, 85)
    }

    func testTransferRiskTextAndAmountMismatchRequireConfirmation() {
        XCTAssertEqual(
            reason(RecognitionSafetyEvaluator().evaluate(
                candidate(type: .transfer), ocrText: "转账 CNY 85.00",
                context: context, allowIncomeAutoEntry: false
            )),
            .unsupportedType
        )
        XCTAssertEqual(
            reason(RecognitionSafetyEvaluator().evaluate(
                candidate(original: "100", discount: "10"),
                ocrText: "支付成功 CNY 85.00", context: context, allowIncomeAutoEntry: false
            )),
            .amountRelationshipMismatch
        )
    }

    private func reason(_ decision: RecognitionDecision) -> RecognitionDecisionReason? {
        if case let .needsConfirmation(reason, _) = decision { return reason }
        if case let .rejected(reason) = decision { return reason }
        return nil
    }

    private func candidate(
        type: RecognizedTransactionType = .expense,
        original: String? = "100",
        discount: String? = "15",
        currency: String = "CNY",
        category: String? = "餐饮",
        accountHint: String? = "招商银行 1234",
        confidence: RecognitionConfidenceDTO = .init(
            type: 0.99, paidAmount: 0.99, currencyCode: 0.99,
            account: 0.99, category: 0.99
        )
    ) -> RecognitionCandidateDTO {
        .init(
            type: type, paidAmount: "85", originalAmount: original,
            discountAmount: discount, feeAmount: "0", currencyCode: currency,
            date: "2026-07-11", time: "12:30", merchantOrCounterparty: "星巴克",
            sourceAccountHint: accountHint, destinationAccountHint: nil,
            categoryCandidate: category, note: "咖啡", confidence: confidence
        )
    }
}
```

- [ ] **Step 2: Run the test and verify normalizer/evaluator types are missing**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/RecognitionSafetyEvaluatorTests
```

Expected: `FAIL` for missing `RecognitionSafetyEvaluator`.

- [ ] **Step 3: Implement strict normalization**

Create `MultiCurrencyLedger/Recognition/RecognitionCandidateNormalizer.swift`:

```swift
import Foundation

struct RecognitionCandidateNormalizer {
    func normalize(
        _ dto: RecognitionCandidateDTO,
        timeZone: TimeZone = .current
    ) -> Result<NormalizedRecognitionCandidate, RecognitionDecisionReason> {
        guard let paid = DecimalParser.parse(dto.paidAmount), paid > 0 else {
            return .failure(.invalidAmount)
        }
        guard let currency = SupportedCurrency(rawValue: dto.currencyCode.uppercased()) else {
            return .failure(.unsupportedCurrency)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let occurredAt = formatter.date(from: "\(dto.date) \(dto.time)") else {
            return .failure(.invalidDate)
        }
        func optionalAmount(_ text: String?) -> Decimal? {
            guard let text, !text.isEmpty else { return nil }
            return DecimalParser.parse(text)
        }
        let original = optionalAmount(dto.originalAmount)
        let discount = optionalAmount(dto.discountAmount) ?? 0
        let fee = optionalAmount(dto.feeAmount) ?? 0
        guard discount >= 0, fee >= 0, original.map({ $0 > 0 }) ?? true else {
            return .failure(.invalidAmount)
        }
        return .success(.init(
            type: dto.type, paidAmount: paid, originalAmount: original,
            discountAmount: discount, feeAmount: fee, currency: currency,
            occurredAt: occurredAt, merchantOrCounterparty: dto.merchantOrCounterparty,
            sourceAccountHint: dto.sourceAccountHint,
            destinationAccountHint: dto.destinationAccountHint,
            categoryCandidate: dto.categoryCandidate, note: dto.note,
            confidence: dto.confidence
        ))
    }
}
```

- [ ] **Step 4: Implement the deterministic safety gates**

Create `MultiCurrencyLedger/Recognition/RecognitionSafetyEvaluator.swift`:

```swift
import Foundation

struct RecognitionSafetyEvaluator {
    var minimumConfidence = 0.95
    var matcher = RecognitionAccountMatcher()

    func evaluate(
        _ dto: RecognitionCandidateDTO,
        ocrText: String,
        context: RecognitionRequestContext,
        allowIncomeAutoEntry: Bool
    ) -> RecognitionDecision {
        let normalizedResult = RecognitionCandidateNormalizer().normalize(dto)
        guard case let .success(candidate) = normalizedResult else {
            if case let .failure(reason) = normalizedResult { return .rejected(reason: reason) }
            return .rejected(reason: .invalidAmount)
        }
        guard candidate.type == .expense || (candidate.type == .income && allowIncomeAutoEntry) else {
            return .needsConfirmation(reason: .unsupportedType, candidate: candidate)
        }
        let riskyTerms = ["退款", "撤销", "处理中", "失败", "还款", "充值", "换汇", "转账"]
        if riskyTerms.contains(where: ocrText.contains) {
            return .needsConfirmation(reason: .riskyStatusText, candidate: candidate)
        }
        let amountToken = NSDecimalNumber(decimal: candidate.paidAmount).stringValue
        let compactOCR = ocrText.replacingOccurrences(of: ",", with: "")
        guard compactOCR.contains(amountToken) else {
            return .needsConfirmation(reason: .amountNotVisibleInOCR, candidate: candidate)
        }
        if let original = candidate.originalAmount {
            let tolerance: Decimal = candidate.currency == .JPY ? 1 : 0.01
            let difference = abs(original - candidate.discountAmount - candidate.paidAmount)
            if difference > tolerance {
                return .needsConfirmation(reason: .amountRelationshipMismatch, candidate: candidate)
            }
        }
        let confidence = candidate.confidence
        guard [confidence.type, confidence.paidAmount, confidence.currencyCode,
               confidence.account, confidence.category].allSatisfy({ $0 >= minimumConfidence }) else {
            return .needsConfirmation(reason: .lowConfidence, candidate: candidate)
        }
        guard let category = candidate.categoryCandidate,
              context.categories.contains(where: { $0.name == category &&
                  ($0.type == .expense) == (candidate.type == .expense) }) else {
            return .needsConfirmation(reason: .categoryUnmatched, candidate: candidate)
        }
        switch matcher.match(
            hint: candidate.sourceAccountHint,
            currency: candidate.currency,
            options: context.accounts
        ) {
        case let .matched(walletID):
            return .autoEligible(walletID: walletID, candidate: candidate)
        case .ambiguous:
            return .needsConfirmation(reason: .accountAmbiguous, candidate: candidate)
        case .currencyMismatch:
            return .needsConfirmation(reason: .currencyWalletMismatch, candidate: candidate)
        case .unmatched:
            return .needsConfirmation(reason: .accountUnmatched, candidate: candidate)
        }
    }
}
```

- [ ] **Step 5: Add tests for income opt-in, low confidence, unknown category, and unsupported currency**

Add these methods to `RecognitionSafetyEvaluatorTests`:

```swift
func testIncomeRequiresOptIn() {
    XCTAssertEqual(
        reason(RecognitionSafetyEvaluator().evaluate(
            candidate(type: .income), ocrText: "工资 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )),
        .unsupportedType
    )
}

func testRejectsUnsupportedCurrency() {
    XCTAssertEqual(
        reason(RecognitionSafetyEvaluator().evaluate(
            candidate(currency: "BTC"), ocrText: "支付成功 BTC 85",
            context: context, allowIncomeAutoEntry: false
        )),
        .unsupportedCurrency
    )
}

func testRequiresConfirmationForUnknownCategory() {
    XCTAssertEqual(
        reason(RecognitionSafetyEvaluator().evaluate(
            candidate(category: "模型自造分类"), ocrText: "支付成功 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )),
        .categoryUnmatched
    )
}

func testRequiresConfirmationForLowConfidence() {
    let low = RecognitionConfidenceDTO(
        type: 0.99, paidAmount: 0.99, currencyCode: 0.99,
        account: 0.80, category: 0.99
    )
    XCTAssertEqual(
        reason(RecognitionSafetyEvaluator().evaluate(
            candidate(confidence: low), ocrText: "支付成功 CNY 85",
            context: context, allowIncomeAutoEntry: false
        )),
        .lowConfidence
    )
}
```

- [ ] **Step 6: Run focused and full suites**

Run the Step 2 command and then the full suite.

Expected: all safety paths pass; existing ledger tests remain unchanged.

- [ ] **Step 7: Commit normalization and safety logic**

```bash
git add MultiCurrencyLedger/Recognition/RecognitionCandidateNormalizer.swift \
  MultiCurrencyLedger/Recognition/RecognitionSafetyEvaluator.swift \
  MultiCurrencyLedgerTests/RecognitionSafetyEvaluatorTests.swift
git commit -m "feat: evaluate recognition safety locally"
```

---

### Task 6: Screenshot Recognition Coordinator with an Injected API Boundary

**Files:**
- Create: `MultiCurrencyLedger/Recognition/ScreenshotRecognitionCoordinator.swift`
- Create: `MultiCurrencyLedgerTests/ScreenshotRecognitionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `CGImage`, `LedgerBook`, `[LedgerCategory]`, `ScreenshotOCRServicing`, and `RecognitionAPIClient`.
- Produces: `RecognitionAPIRequest`, `RecognitionBatchAnalysis`, `RecognitionAPIClient.recognize(_:)`, and `ScreenshotRecognitionCoordinator.analyze(image:book:categories:allowIncomeAutoEntry:)`.

- [ ] **Step 1: Write a failing coordinator test with stub OCR and API client**

```swift
import CoreGraphics
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class ScreenshotRecognitionCoordinatorTests: XCTestCase {
    private let validResponse = Data(#"{"results":[{"type":"expense","paidAmount":"85.00","originalAmount":"100","discountAmount":"15","feeAmount":"0","currencyCode":"CNY","date":"2026-07-11","time":"12:30","merchantOrCounterparty":"星巴克","sourceAccountHint":"招商银行 1234","destinationAccountHint":null,"categoryCandidate":"餐饮","note":"咖啡","confidence":{"type":0.99,"paidAmount":0.99,"currencyCode":0.99,"account":0.99,"category":0.99}}]}"#.utf8)

    func testCoordinatesOCRContextParseAndSafetyWithoutWritingLedger() async throws {
        let wallet = CurrencyWallet(currency: .CNY)
        let account = Account(name: "招商银行 1234", type: .bankCard)
        wallet.account = account
        account.wallets = [wallet]
        let book = LedgerBook(name: "日常账本")
        account.book = book
        book.accounts = [account]
        let category = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        let api = StubRecognitionAPIClient(response: validResponse)
        let coordinator = ScreenshotRecognitionCoordinator(
            ocr: StubOCR(), apiClient: api
        )

        let analysis = try await coordinator.analyze(
            image: Self.onePixelImage(), book: book, categories: [category],
            allowIncomeAutoEntry: false
        )

        XCTAssertEqual(analysis.decisions.count, 1)
        guard case .autoEligible = analysis.decisions[0] else {
            return XCTFail("Expected eligible result")
        }
        XCTAssertTrue(api.lastRequest?.ocrText.contains("85") == true)
        XCTAssertEqual(wallet.balance, 0)
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

private struct StubOCR: ScreenshotOCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRDocument {
        OCRDocument(lines: [.init(
            text: "支付成功 星巴克 招商银行1234 CNY 85.00",
            boundingBox: .init(x: 0, y: 0, width: 1, height: 1)
        )])
    }
}

private final class StubRecognitionAPIClient: RecognitionAPIClient {
    let response: Data
    var lastRequest: RecognitionAPIRequest?
    init(response: Data) { self.response = response }
    func recognize(_ request: RecognitionAPIRequest) async throws -> Data {
        lastRequest = request
        return response
    }
}
```

- [ ] **Step 2: Run the coordinator test and verify the coordinator types are missing**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/ScreenshotRecognitionCoordinatorTests
```

Expected: `FAIL` for missing coordinator/API interfaces.

- [ ] **Step 3: Implement the request, client protocol, batch result, and coordinator**

Create `MultiCurrencyLedger/Recognition/ScreenshotRecognitionCoordinator.swift`:

```swift
import CoreGraphics
import Foundation

struct RecognitionAPIRequest: Codable, Equatable {
    let ocrText: String
    let context: RecognitionRequestContext
    let requestedAt: Date
}

protocol RecognitionAPIClient: AnyObject {
    func recognize(_ request: RecognitionAPIRequest) async throws -> Data
}

struct RecognitionBatchAnalysis: Equatable {
    let document: OCRDocument
    let decisions: [RecognitionDecision]
}

@MainActor
struct ScreenshotRecognitionCoordinator {
    let ocr: ScreenshotOCRServicing
    let apiClient: RecognitionAPIClient
    var parser = RecognitionResponseParser()
    var contextBuilder = RecognitionContextBuilder()
    var evaluator = RecognitionSafetyEvaluator()

    func analyze(
        image: CGImage,
        book: LedgerBook,
        categories: [LedgerCategory],
        allowIncomeAutoEntry: Bool,
        now: Date = .now
    ) async throws -> RecognitionBatchAnalysis {
        let document = try await ocr.recognizeText(in: image)
        let context = contextBuilder.makeContext(book: book, categories: categories)
        let data = try await apiClient.recognize(.init(
            ocrText: document.fullText, context: context, requestedAt: now
        ))
        let envelope = try parser.parse(data)
        let decisions = envelope.results.map {
            evaluator.evaluate(
                $0, ocrText: document.fullText, context: context,
                allowIncomeAutoEntry: allowIncomeAutoEntry
            )
        }
        return RecognitionBatchAnalysis(document: document, decisions: decisions)
    }
}
```

- [ ] **Step 4: Add failure propagation tests**

Add these test doubles below the existing doubles:

```swift
private struct ThrowingOCR: ScreenshotOCRServicing {
    let error: Error
    func recognizeText(in image: CGImage) async throws -> OCRDocument { throw error }
}

private final class ThrowingRecognitionAPIClient: RecognitionAPIClient {
    let error: Error
    init(error: Error) { self.error = error }
    func recognize(_ request: RecognitionAPIRequest) async throws -> Data { throw error }
}
```

Add this scope helper and the three failure tests inside `ScreenshotRecognitionCoordinatorTests`:

```swift
private static func makeScope() -> (LedgerBook, LedgerCategory, CurrencyWallet) {
    let wallet = CurrencyWallet(currency: .CNY)
    let account = Account(name: "招商银行 1234", type: .bankCard)
    wallet.account = account
    account.wallets = [wallet]
    let book = LedgerBook(name: "日常账本")
    account.book = book
    book.accounts = [account]
    let category = LedgerCategory(
        name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0
    )
    return (book, category, wallet)
}

func testOCRFailurePropagatesWithoutChangingBalance() async {
    let (book, category, wallet) = Self.makeScope()
    let coordinator = ScreenshotRecognitionCoordinator(
        ocr: ThrowingOCR(error: RecognitionError.noRecognizableText),
        apiClient: StubRecognitionAPIClient(response: validResponse)
    )
    do {
        _ = try await coordinator.analyze(
            image: Self.onePixelImage(), book: book, categories: [category],
            allowIncomeAutoEntry: false
        )
        XCTFail("Expected OCR failure")
    } catch {
        XCTAssertEqual(error as? RecognitionError, .noRecognizableText)
    }
    XCTAssertEqual(wallet.balance, 0)
}

func testAPITimeoutPropagatesWithoutChangingBalance() async {
    let (book, category, wallet) = Self.makeScope()
    let coordinator = ScreenshotRecognitionCoordinator(
        ocr: StubOCR(),
        apiClient: ThrowingRecognitionAPIClient(error: URLError(.timedOut))
    )
    do {
        _ = try await coordinator.analyze(
            image: Self.onePixelImage(), book: book, categories: [category],
            allowIncomeAutoEntry: false
        )
        XCTFail("Expected timeout")
    } catch {
        XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }
    XCTAssertEqual(wallet.balance, 0)
}

func testInvalidAPIJSONFailsWithoutChangingBalance() async {
    let (book, category, wallet) = Self.makeScope()
    let coordinator = ScreenshotRecognitionCoordinator(
        ocr: StubOCR(),
        apiClient: StubRecognitionAPIClient(response: Data("not json".utf8))
    )
    do {
        _ = try await coordinator.analyze(
            image: Self.onePixelImage(), book: book, categories: [category],
            allowIncomeAutoEntry: false
        )
        XCTFail("Expected invalid response")
    } catch {
        XCTAssertEqual(error as? RecognitionError, .invalidResponse)
    }
    XCTAssertEqual(wallet.balance, 0)
}
```

- [ ] **Step 5: Run coordinator and full suites**

Run the Step 2 command and then the full suite.

Expected: coordinator tests pass; no `LedgerTransaction` creation appears anywhere in the new production files.

- [ ] **Step 6: Audit the phase boundary**

Run:

```bash
rg -n "LedgerService|LedgerTransaction\(|balance\s*[+\-]?=" MultiCurrencyLedger/Recognition
```

Expected: no matches. `Recognition/` must remain read-only with respect to ledger state.

- [ ] **Step 7: Commit the coordinator**

```bash
git add MultiCurrencyLedger/Recognition/ScreenshotRecognitionCoordinator.swift \
  MultiCurrencyLedgerTests/ScreenshotRecognitionCoordinatorTests.swift
git commit -m "feat: coordinate screenshot recognition analysis"
```

---

### Task 7: Sanitized Recognition Fixture Corpus and Acceptance Gate

**Files:**
- Create: `MultiCurrencyLedgerTests/Fixtures/RecognitionFixtures.swift`
- Create: `MultiCurrencyLedgerTests/RecognitionFixtureAcceptanceTests.swift`
- Create: `docs/recognition-fixtures/README.md`

**Interfaces:**
- Consumes: production parser and safety evaluator from Tasks 1–5.
- Produces: `RecognitionFixture`, `RecognitionFixtures.all`, and a repeatable acceptance suite for representative OCR/model pairs.

- [ ] **Step 1: Define the fixture type and eight synthetic, non-personal scenarios**

Create `MultiCurrencyLedgerTests/Fixtures/RecognitionFixtures.swift`:

```swift
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
        fixture("cny-expense", "支付成功 餐饮 CNY 28.00 招商银行1234", "expense", "28", "CNY", "餐饮", .eligible, true),
        fixture("usd-expense", "Completed Coffee USD 6.50 招商银行1234", "expense", "6.50", "USD", "餐饮", .eligible, true),
        fixture("income-opt-out", "工资到账 CNY 8000 招商银行1234", "income", "8000", "CNY", "工资", .unsupportedType, false),
        fixture("transfer", "转账成功 CNY 500 招商银行1234", "transfer", "500", "CNY", "其他", .unsupportedType, false),
        fixture("refund", "退款成功 CNY 85 招商银行1234", "refund", "85", "CNY", "退款", .unsupportedType, false),
        fixture("pending", "处理中 CNY 30 招商银行1234", "expense", "30", "CNY", "餐饮", .riskyStatusText, false),
        fixture("unknown-account", "支付成功 CNY 20 尾号9999", "expense", "20", "CNY", "餐饮", .accountUnmatched, false, accountHint: "尾号9999"),
        fixture("bad-discount", "原价100 优惠10 实付85 CNY 招商银行1234", "expense", "85", "CNY", "餐饮", .amountRelationshipMismatch, false, original: "100", discount: "10")
    ]

    private static func fixture(
        _ name: String, _ ocr: String, _ type: String, _ amount: String,
        _ currency: String, _ category: String, _ reason: RecognitionDecisionReason,
        _ auto: Bool, original: String? = nil, discount: String? = "0",
        accountHint: String = "招商银行 1234"
    ) -> RecognitionFixture {
        let originalJSON = original.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"results":[{"type":"\(type)","paidAmount":"\(amount)","originalAmount":\(originalJSON),"discountAmount":"\(discount ?? "0")","feeAmount":"0","currencyCode":"\(currency)","date":"2026-07-11","time":"12:30","merchantOrCounterparty":"示例商户","sourceAccountHint":"\(accountHint)","destinationAccountHint":null,"categoryCandidate":"\(category)","note":"","confidence":{"type":0.99,"paidAmount":0.99,"currencyCode":0.99,"account":0.99,"category":0.99}}]}
        """
        return .init(name: name, ocrText: ocr, responseJSON: json, expectedReason: reason, expectsAutoEntry: auto)
    }
}
```

When evaluating the USD fixture, include a USD wallet for the same account. For the income fixture, keep `allowIncomeAutoEntry` false.

- [ ] **Step 2: Write the table-driven acceptance test**

Create `MultiCurrencyLedgerTests/RecognitionFixtureAcceptanceTests.swift`:

```swift
import XCTest
@testable import MultiCurrencyLedger

final class RecognitionFixtureAcceptanceTests: XCTestCase {
    func testSanitizedFixtureCorpusMatchesExpectedSafetyDecisions() throws {
        let cnyID = UUID()
        let usdID = UUID()
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
        for fixture in RecognitionFixtures.all {
            let candidate = try RecognitionResponseParser()
                .parse(Data(fixture.responseJSON.utf8)).results[0]
            let decision = RecognitionSafetyEvaluator().evaluate(
                candidate, ocrText: fixture.ocrText, context: context,
                allowIncomeAutoEntry: false
            )
            if fixture.expectsAutoEntry {
                guard case .autoEligible = decision else {
                    return XCTFail("\(fixture.name): expected auto entry, got \(decision)")
                }
            } else {
                let actual: RecognitionDecisionReason
                switch decision {
                case let .needsConfirmation(reason, _), let .rejected(reason): actual = reason
                case .autoEligible: return XCTFail("\(fixture.name): unsafe auto entry")
                }
                XCTAssertEqual(actual, fixture.expectedReason, fixture.name)
            }
        }
    }
}
```

- [ ] **Step 3: Document fixture privacy and contribution rules**

Create `docs/recognition-fixtures/README.md` with this exact policy:

```markdown
# Recognition Fixture Corpus

This corpus validates OCR-to-decision behavior without storing personal financial screenshots.

- Prefer synthetic OCR text and expected JSON.
- Never commit names, card numbers, transaction IDs, addresses, QR codes, or full screenshots.
- Replace account tails with `1234`, merchants with generic examples, and dates with fixed test dates.
- Every fixture must declare whether auto-entry is allowed and the exact fallback reason.
- A regression fixture is added only after the source screenshot has been discarded or irreversibly sanitized.
```

- [ ] **Step 4: Run the fixture gate and full suite**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' \
  -only-testing:MultiCurrencyLedgerTests/RecognitionFixtureAcceptanceTests

xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger \
  -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B'
```

Expected: eight fixtures pass and the complete suite passes.

- [ ] **Step 5: Run the final privacy and scope audit**

```bash
rg -n "api[_-]?key|Bearer |https?://|UIImageJPEGRepresentation|pngData\(|write\(to:|LedgerService|LedgerTransaction\(" \
  MultiCurrencyLedger/Recognition MultiCurrencyLedgerTests/Fixtures
```

Expected: no secrets, endpoints, screenshot persistence, or ledger mutations. The only acceptable URL-like text in this phase is none.

- [ ] **Step 6: Commit the fixture gate and plan completion**

```bash
git add MultiCurrencyLedgerTests/Fixtures/RecognitionFixtures.swift \
  MultiCurrencyLedgerTests/RecognitionFixtureAcceptanceTests.swift \
  docs/recognition-fixtures/README.md
git commit -m "test: add sanitized recognition acceptance corpus"
```

---

## Phase Completion Gate

Do not start the persistence/import-safety plan until all of the following are true:

- Every focused test and the full existing suite pass on the iPhone 16 simulator.
- `Recognition/` contains no ledger mutation, screenshot persistence, endpoint, API key, UI, or App Intent code.
- The coordinator can analyze one generated screenshot through real Vision OCR and a stub API response.
- The fixture corpus covers CNY, USD, income opt-out, transfer, refund, pending status, unknown account, and inconsistent discount math.
- The original app can still create, edit, delete, transfer, exchange, value, budget, and export transactions exactly as before.

After this gate, write separate implementation plans for:

1. Persistent `ImportRecord`, account mappings, duplicate detection, and atomic `LedgerService` import.
2. The controlled API gateway and production recognition client.
3. Confirmation/history/settings UI, App Intent, and the thin Shortcuts wrapper.
