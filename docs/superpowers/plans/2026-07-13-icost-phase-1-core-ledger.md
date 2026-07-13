# iCost Phase 1 Core Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete book/month scoping, a single atomic transaction draft pipeline, full transaction editing/copying, recent entry defaults, and composable transaction search without changing the current visual language.

**Architecture:** `LedgerScope` and `TransactionQueryState` remain pure value types. Every create/edit/copy path builds a `TransactionDraft`; `TransactionValidator` and `WalletImpactEngine` validate it and calculate wallet deltas before `LedgerService` performs one atomic SwiftData save. SwiftUI owns form presentation only and never mutates balances directly.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, XCTest, iOS 17+, Xcode project with file-system-synchronized source groups.

## Global Constraints

- Preserve the current glass-card visual system; do not copy iCost layouts, assets, icons, or page structure.
- Preserve all existing books, accounts, wallets, transactions, budgets, rates, and recognition records.
- Keep the current working-tree changes and do not stage `docs/superpowers/specs/2026-07-12-assets-budget-savings-roadmap.md` unless the user separately requests it.
- All create, edit, copy, and recognition-confirmation writes must pass through `LedgerService` using `TransactionDraft`.
- New transactions may only use enabled wallets in the selected book; historical cross-book transfers remain readable.
- A transfer requires two different wallets in the same currency; an exchange requires two different wallets in different currencies.
- A failed create, update, delete, or recognition confirmation must restore every affected wallet balance and leave the original transaction unchanged.
- Do not launch the Simulator app for visual checking. `xcodebuild test` against one iPhone 16 simulator is allowed only when required to execute financial correctness tests; use generic-device builds for routine compilation.
- Phase 1 does not implement tags, second-level categories, attachments, refunds, reimbursements, split payments, schedules, installments, sync, or widgets.

---

## File Map

**Pure domain and query files**

- `MultiCurrencyLedger/Models/LedgerScope.swift`: common book/month/currency boundary.
- `MultiCurrencyLedger/Models/TransactionQueryState.swift`: all transaction filters and sorting.
- `MultiCurrencyLedger/Models/TransactionDraft.swift`: canonical create/update intent and legacy transaction conversion.
- `MultiCurrencyLedger/Services/TransactionValidator.swift`: domain validation without persistence.
- `MultiCurrencyLedger/Services/WalletImpactEngine.swift`: pure wallet-delta calculation.

**Persistence and preferences**

- `MultiCurrencyLedger/Services/LedgerService.swift`: only transaction commit boundary.
- `MultiCurrencyLedger/Services/RecognitionEntryService.swift`: recognition adapter into the draft boundary.
- `MultiCurrencyLedger/Services/RecentTransactionDefaultsStore.swift`: per-book recent legal selections.

**SwiftUI**

- `MultiCurrencyLedger/Views/Entry/TransactionFormState.swift`: parseable shared form state.
- `MultiCurrencyLedger/Views/Entry/TransactionFormSections.swift`: shared create/edit fields.
- `MultiCurrencyLedger/Views/Entry/EntryView.swift`: create/copy orchestration and continuous entry.
- `MultiCurrencyLedger/Views/Transactions/TransactionEditView.swift`: full edit orchestration.
- `MultiCurrencyLedger/Views/Transactions/TransactionDetailView.swift`: edit, copy, and delete actions.
- `MultiCurrencyLedger/Views/Transactions/TransactionListView.swift`: query application, grouping, summary, and search.
- `MultiCurrencyLedger/Views/Transactions/TransactionFilterView.swift`: complete filter editor.
- `MultiCurrencyLedger/Views/Home/HomeView.swift`: expose the transaction search entry.

**Tests**

- `MultiCurrencyLedgerTests/LedgerScopeTests.swift`
- `MultiCurrencyLedgerTests/TransactionQueryStateTests.swift`
- `MultiCurrencyLedgerTests/TransactionDraftTests.swift`
- `MultiCurrencyLedgerTests/WalletImpactEngineTests.swift`
- `MultiCurrencyLedgerTests/LedgerServiceTests.swift`
- `MultiCurrencyLedgerTests/TransactionFormStateTests.swift`
- `MultiCurrencyLedgerTests/RecentTransactionDefaultsStoreTests.swift`
- `MultiCurrencyLedgerTests/RecognitionEntryServiceTests.swift`

---

### Task 1: Finish Common Scope and Query Primitives

**Files:**
- Keep and finish: `MultiCurrencyLedger/Models/LedgerScope.swift`
- Keep and finish: `MultiCurrencyLedger/Models/TransactionQueryState.swift`
- Keep and finish: `MultiCurrencyLedgerTests/LedgerScopeTests.swift`
- Create: `MultiCurrencyLedgerTests/TransactionQueryStateTests.swift`
- Modify: `MultiCurrencyLedger/Views/Home/HomeView.swift`
- Keep: `MultiCurrencyLedger.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `LedgerScope.init(bookID:selectedMonth:baseCurrencyCode:calendar:)`
- Produces: `LedgerScope.contains(transaction:)`, `matches(budget:)`, and `transactionBelongsToBook(_:)`
- Produces: `TransactionQueryState.applying(to:referenceDate:calendar:) -> [LedgerTransaction]`

- [ ] **Step 1: Add failing query-composition tests**

Create `TransactionQueryStateTests.swift` with an in-memory SwiftData container and these assertions:

```swift
import SwiftData
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class TransactionQueryStateTests: XCTestCase {
    func testCombinesBookKeywordAmountAndCategoryThenSorts() {
        let daily = LedgerBook(name: "日常")
        let travel = LedgerBook(name: "旅行")
        let dailyAccount = Account(name: "工资卡", type: .bankCard, book: daily)
        let travelAccount = Account(name: "旅行卡", type: .bankCard, book: travel)
        let food = LedgerCategory(name: "餐饮", type: .expense, symbolName: "fork.knife", sortOrder: 0)
        let small = LedgerTransaction(type: .expense, amount: 20, date: date("2026-07-10T10:00:00Z"), note: "午餐", sourceAccount: dailyAccount, sourceAmount: 20, category: food, merchantOrCounterparty: "食堂")
        let large = LedgerTransaction(type: .expense, amount: 80, date: date("2026-07-11T10:00:00Z"), note: "晚餐", sourceAccount: dailyAccount, sourceAmount: 80, category: food, merchantOrCounterparty: "食堂")
        let otherBook = LedgerTransaction(type: .expense, amount: 90, date: date("2026-07-12T10:00:00Z"), sourceAccount: travelAccount, sourceAmount: 90, category: food, merchantOrCounterparty: "食堂")
        var query = TransactionQueryState(bookID: daily.id)
        query.keyword = "食堂"
        query.minimumAmount = 50
        query.categoryID = food.id
        query.sortOrder = .amountDescending

        XCTAssertEqual(query.applying(to: [small, otherBook, large]).map(\.id), [large.id])
    }

    func testCustomDateIncludesWholeEndDayAndClearKeepsCurrentBook() {
        let bookID = UUID()
        let otherBookID = UUID()
        let account = Account(name: "现金", type: .cash, book: LedgerBook(id: bookID, name: "日常"))
        let atEnd = LedgerTransaction(type: .expense, amount: 1, date: date("2026-07-11T23:59:59Z"), sourceAccount: account, sourceAmount: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var query = TransactionQueryState(bookID: bookID)
        query.dateFilter = .custom
        query.customStartDate = date("2026-07-11T00:00:00Z")
        query.customEndDate = date("2026-07-11T00:00:00Z")

        XCTAssertEqual(query.applying(to: [atEnd], calendar: calendar).map(\.id), [atEnd.id])
        query.bookID = otherBookID
        XCTAssertTrue(query.hasActiveFilters)
        query.clearFilters(keepingBookID: bookID)
        XCTAssertEqual(query.bookID, bookID)
        XCTAssertFalse(query.hasActiveFilters)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
```

- [ ] **Step 2: Execute the focused tests and observe the initial failure**

Run:

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MultiCurrencyLedgerTests/LedgerScopeTests -only-testing:MultiCurrencyLedgerTests/TransactionQueryStateTests
```

Expected: the new query test fails until `hasActiveFilters` treats the selected book as the baseline rather than an active filter, or compilation exposes an inconsistency in the existing working-copy implementation.

- [ ] **Step 3: Make the baseline-book rule explicit and finish Home integration**

Change `TransactionQueryState` to store the baseline book used by the page:

```swift
struct TransactionQueryState: Equatable, Sendable {
    let baselineBookID: UUID?
    var bookID: UUID?
    var dateFilter: TransactionDateFilter = .all
    var customStartDate: Date?
    var customEndDate: Date?
    var minimumAmount: Decimal?
    var maximumAmount: Decimal?
    var keyword = ""
    var accountID: UUID?
    var currencyCode: String?
    var kind: TransactionKind?
    var categoryID: UUID?
    var sortOrder: TransactionSortOrder = .dateDescending

    init(scope: LedgerScope) {
        baselineBookID = scope.bookID
        bookID = scope.bookID
    }

    init(bookID: UUID?) {
        baselineBookID = bookID
        self.bookID = bookID
    }

    var hasActiveFilters: Bool {
        bookID != baselineBookID
            || dateFilter != .all
            || customStartDate != nil
            || customEndDate != nil
            || minimumAmount != nil
            || maximumAmount != nil
            || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || accountID != nil
            || currencyCode != nil
            || kind != nil
            || categoryID != nil
    }

    mutating func clearFilters(keepingBookID bookID: UUID?) {
        self = TransactionQueryState(bookID: bookID)
    }
}
```

Keep the existing `HomeView` change so the selected month drives the budget and summary. Do not stage the unrelated assets/budget/savings roadmap.

- [ ] **Step 4: Run focused tests and a generic device build**

Run:

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MultiCurrencyLedgerTests/LedgerScopeTests -only-testing:MultiCurrencyLedgerTests/TransactionQueryStateTests
xcodebuild build -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO
```

Expected: focused tests pass; generic iOS build ends with `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the completed working-copy foundation**

```bash
git add MultiCurrencyLedger.xcodeproj/project.pbxproj MultiCurrencyLedger/Models/LedgerScope.swift MultiCurrencyLedger/Models/TransactionQueryState.swift MultiCurrencyLedger/Views/Home/HomeView.swift MultiCurrencyLedgerTests/LedgerScopeTests.swift MultiCurrencyLedgerTests/TransactionQueryStateTests.swift
git commit -m "fix: unify ledger scope and query state"
```

---

### Task 2: Add Canonical Draft Validation and Wallet Impacts

**Files:**
- Create: `MultiCurrencyLedger/Models/TransactionDraft.swift`
- Create: `MultiCurrencyLedger/Services/TransactionValidator.swift`
- Create: `MultiCurrencyLedger/Services/WalletImpactEngine.swift`
- Create: `MultiCurrencyLedgerTests/TransactionDraftTests.swift`
- Create: `MultiCurrencyLedgerTests/WalletImpactEngineTests.swift`

**Interfaces:**
- Produces: `TransactionDraft.init(bookID:type:amount:date:sourceWallet:destinationWallet:destinationAmount:feeAmount:feeWallet:adjustmentDirection:adjustmentReason:category:merchantOrCounterparty:note:originalAmount:discountAmount:)`
- Produces: `TransactionDraft.init(existing:) throws`
- Produces: `TransactionDraft.makeTransaction(id:createdAt:) -> LedgerTransaction`
- Produces: `TransactionValidator.validate(_:) throws`
- Produces: `WalletImpactEngine.deltas(for:) throws -> [WalletDelta]`

- [ ] **Step 1: Write failing validation and delta tests**

The tests must cover a same-currency transfer, a cross-currency exchange, a transfer fee on the source wallet, a category type mismatch, a disabled wallet, and a different-book wallet. Use this core expectation:

```swift
func testTransferAggregatesPrincipalAndFeeOnSourceWallet() throws {
    let book = LedgerBook(name: "日常")
    let sourceAccount = Account(name: "来源", type: .bankCard, book: book)
    let targetAccount = Account(name: "目标", type: .bankCard, book: book)
    let source = CurrencyWallet(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, currency: .CNY, balance: 1_000, account: sourceAccount)
    let target = CurrencyWallet(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, currency: .CNY, balance: 0, account: targetAccount)
    let draft = TransactionDraft(
        bookID: book.id,
        type: .transfer,
        amount: 200,
        sourceWallet: source,
        destinationWallet: target,
        destinationAmount: 200,
        feeAmount: 5,
        feeWallet: source
    )

    XCTAssertEqual(try WalletImpactEngine().deltas(for: draft), [
        WalletDelta(wallet: source, amount: -205),
        WalletDelta(wallet: target, amount: 200)
    ])
}
```

Also assert `TransactionDraft(existing:)` preserves the transaction ID-independent fields, merchant, category, original amount, discount, and creation date input used by `makeTransaction`.

- [ ] **Step 2: Run focused tests and verify missing-type failures**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MultiCurrencyLedgerTests/TransactionDraftTests -only-testing:MultiCurrencyLedgerTests/WalletImpactEngineTests
```

Expected: compilation fails because `TransactionDraft`, `TransactionValidator`, `WalletImpactEngine`, and `WalletDelta` do not exist.

- [ ] **Step 3: Implement the draft and validation contracts**

Use this draft shape; the explicit initializer supplies defaults for optional arguments:

```swift
struct TransactionDraft {
    let bookID: UUID
    var type: TransactionKind
    var amount: Decimal
    var date: Date
    var note: String?
    var merchantOrCounterparty: String?
    var sourceWallet: CurrencyWallet
    var destinationWallet: CurrencyWallet?
    var destinationAmount: Decimal?
    var feeAmount: Decimal?
    var feeWallet: CurrencyWallet?
    var adjustmentDirection: AdjustmentDirection?
    var adjustmentReason: String?
    var category: LedgerCategory?
    var originalAmount: Decimal?
    var discountAmount: Decimal?

    init(
        bookID: UUID,
        type: TransactionKind,
        amount: Decimal,
        date: Date = .now,
        sourceWallet: CurrencyWallet,
        destinationWallet: CurrencyWallet? = nil,
        destinationAmount: Decimal? = nil,
        feeAmount: Decimal? = nil,
        feeWallet: CurrencyWallet? = nil,
        adjustmentDirection: AdjustmentDirection? = nil,
        adjustmentReason: String? = nil,
        category: LedgerCategory? = nil,
        merchantOrCounterparty: String? = nil,
        note: String? = nil,
        originalAmount: Decimal? = nil,
        discountAmount: Decimal? = nil
    ) {
        self.bookID = bookID
        self.type = type
        self.amount = amount
        self.date = date
        self.sourceWallet = sourceWallet
        self.destinationWallet = destinationWallet
        self.destinationAmount = destinationAmount
        self.feeAmount = feeAmount
        self.feeWallet = feeWallet
        self.adjustmentDirection = adjustmentDirection
        self.adjustmentReason = adjustmentReason
        self.category = category
        self.merchantOrCounterparty = merchantOrCounterparty
        self.note = note
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
    }
}

enum TransactionValidationError: LocalizedError, Equatable {
    case invalidAmount
    case unavailableSourceWallet
    case walletOutsideBook
    case missingDestinationWallet
    case sameWallet
    case transferCurrencyMismatch
    case exchangeRequiresDifferentCurrencies
    case invalidDestinationAmount
    case invalidFee
    case invalidFeeWallet
    case categoryTypeMismatch
    case missingAdjustmentDetails

    var errorDescription: String? {
        switch self {
        case .invalidAmount: "金额必须大于 0"
        case .unavailableSourceWallet: "来源钱包已停用或账户已隐藏"
        case .walletOutsideBook: "所选钱包不属于当前账本"
        case .missingDestinationWallet: "请选择目标钱包"
        case .sameWallet: "来源和目标钱包不能相同"
        case .transferCurrencyMismatch: "转账仅支持相同币种"
        case .exchangeRequiresDifferentCurrencies: "换汇必须选择不同币种"
        case .invalidDestinationAmount: "请输入大于 0 的目标金额"
        case .invalidFee: "手续费必须大于 0"
        case .invalidFeeWallet: "手续费钱包必须可用且与来源币种一致"
        case .categoryTypeMismatch: "分类与交易类型不一致"
        case .missingAdjustmentDetails: "请选择调整方向并填写调整原因"
        }
    }
}
```

Implement validation with the complete branch structure below. Text trimming occurs when the draft creates or updates a model.

```swift
struct TransactionValidator {
    func validate(_ draft: TransactionDraft) throws {
        guard draft.amount > 0 else { throw TransactionValidationError.invalidAmount }
        guard draft.sourceWallet.isEnabled,
              draft.sourceWallet.account?.isHidden == false else {
            throw TransactionValidationError.unavailableSourceWallet
        }
        guard draft.sourceWallet.account?.book?.id == draft.bookID else {
            throw TransactionValidationError.walletOutsideBook
        }

        switch draft.type {
        case .expense, .income:
            if let category = draft.category {
                let expected: CategoryKind = draft.type == .income ? .income : .expense
                guard category.type == expected else {
                    throw TransactionValidationError.categoryTypeMismatch
                }
            }
        case .transfer, .exchange:
            guard let destination = draft.destinationWallet else {
                throw TransactionValidationError.missingDestinationWallet
            }
            guard destination.id != draft.sourceWallet.id else {
                throw TransactionValidationError.sameWallet
            }
            guard destination.isEnabled,
                  destination.account?.isHidden == false,
                  destination.account?.book?.id == draft.bookID else {
                throw TransactionValidationError.walletOutsideBook
            }
            if draft.type == .transfer {
                guard destination.currencyCode == draft.sourceWallet.currencyCode else {
                    throw TransactionValidationError.transferCurrencyMismatch
                }
            } else {
                guard destination.currencyCode != draft.sourceWallet.currencyCode else {
                    throw TransactionValidationError.exchangeRequiresDifferentCurrencies
                }
                guard let destinationAmount = draft.destinationAmount, destinationAmount > 0 else {
                    throw TransactionValidationError.invalidDestinationAmount
                }
            }
        case .adjustment:
            guard draft.adjustmentDirection != nil,
                  !(draft.adjustmentReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TransactionValidationError.missingAdjustmentDetails
            }
        }

        if let feeAmount = draft.feeAmount {
            guard feeAmount > 0 else { throw TransactionValidationError.invalidFee }
            guard draft.type == .transfer || draft.type == .exchange,
                  let feeWallet = draft.feeWallet,
                  feeWallet.isEnabled,
                  feeWallet.account?.isHidden == false,
                  feeWallet.account?.book?.id == draft.bookID,
                  feeWallet.currencyCode == draft.sourceWallet.currencyCode else {
                throw TransactionValidationError.invalidFeeWallet
            }
        } else if draft.feeWallet != nil {
            throw TransactionValidationError.invalidFee
        }
    }
}
```

- [ ] **Step 4: Implement deterministic aggregated deltas and rerun tests**

`WalletDelta` equality is based on wallet ID and amount. Aggregate repeated wallet effects before returning, and sort by `wallet.id.uuidString` for deterministic tests:

```swift
struct WalletDelta: Equatable {
    let wallet: CurrencyWallet
    let amount: Decimal

    static func == (lhs: WalletDelta, rhs: WalletDelta) -> Bool {
        lhs.wallet.id == rhs.wallet.id && lhs.amount == rhs.amount
    }
}

struct WalletImpactEngine {
    func deltas(for draft: TransactionDraft) throws -> [WalletDelta] {
        try TransactionValidator().validate(draft)
        var totals: [UUID: (wallet: CurrencyWallet, amount: Decimal)] = [:]

        func add(_ amount: Decimal, to wallet: CurrencyWallet) {
            let current = totals[wallet.id]?.amount ?? 0
            totals[wallet.id] = (wallet, current + amount)
        }

        switch draft.type {
        case .expense:
            add(-draft.amount, to: draft.sourceWallet)
        case .income:
            add(draft.amount, to: draft.sourceWallet)
        case .transfer:
            add(-draft.amount, to: draft.sourceWallet)
            add(draft.amount, to: draft.destinationWallet!)
        case .exchange:
            add(-draft.amount, to: draft.sourceWallet)
            add(draft.destinationAmount!, to: draft.destinationWallet!)
        case .adjustment:
            let sign: Decimal = draft.adjustmentDirection == .decrease ? -1 : 1
            add(sign * draft.amount, to: draft.sourceWallet)
        }

        if let feeAmount = draft.feeAmount, let feeWallet = draft.feeWallet {
            add(-feeAmount, to: feeWallet)
        }

        return totals.values
            .filter { $0.amount != 0 }
            .sorted { $0.wallet.id.uuidString < $1.wallet.id.uuidString }
            .map { WalletDelta(wallet: $0.wallet, amount: $0.amount) }
    }
}
```

Run the focused tests. Expected: all draft and impact tests pass.

- [ ] **Step 5: Commit the pure domain layer**

```bash
git add MultiCurrencyLedger/Models/TransactionDraft.swift MultiCurrencyLedger/Services/TransactionValidator.swift MultiCurrencyLedger/Services/WalletImpactEngine.swift MultiCurrencyLedgerTests/TransactionDraftTests.swift MultiCurrencyLedgerTests/WalletImpactEngineTests.swift
git commit -m "feat: add canonical transaction drafts"
```

---

### Task 3: Make LedgerService the Atomic Draft Commit Boundary

**Files:**
- Modify: `MultiCurrencyLedger/Services/LedgerService.swift`
- Modify: `MultiCurrencyLedgerTests/LedgerServiceTests.swift`

**Interfaces:**
- Consumes: `TransactionDraft`, `TransactionValidator`, `WalletImpactEngine`
- Produces: `LedgerService.create(_:) throws -> LedgerTransaction`
- Produces: `LedgerService.update(_:with:) throws`
- Preserves: legacy convenience creation methods and `persistRecognized(_:importRecord:)`

- [ ] **Step 1: Add atomic update and rollback tests**

Add tests proving that a transaction keeps its UUID and creation date after a full update, that moving an expense between wallets reverses the old wallet and applies the new wallet, and that an invalid replacement leaves the old fields and both balances untouched:

```swift
func testDraftUpdateKeepsIdentityAndMovesExpenseBetweenWallets() throws {
    let book = LedgerBook(name: "日常")
    let first = makeWallet(currency: .CNY, balance: 1_000, book: book).1
    let second = makeWallet(currency: .CNY, balance: 500, book: book).1
    let original = try service.create(TransactionDraft(bookID: book.id, type: .expense, amount: 100, sourceWallet: first))
    let id = original.id
    let createdAt = original.createdAt

    try service.update(original, with: TransactionDraft(bookID: book.id, type: .expense, amount: 250, sourceWallet: second, merchantOrCounterparty: "超市"))

    XCTAssertEqual(original.id, id)
    XCTAssertEqual(original.createdAt, createdAt)
    XCTAssertEqual(first.balance, 1_000)
    XCTAssertEqual(second.balance, 250)
    XCTAssertEqual(original.merchantOrCounterparty, "超市")
}
```

- [ ] **Step 2: Run the focused service tests and verify API failure**

```bash
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MultiCurrencyLedgerTests/LedgerServiceTests
```

Expected: compilation fails because the draft create/update methods do not exist.

- [ ] **Step 3: Route create, update, delete, and recognized persistence through wallet deltas**

Add these methods to `LedgerService`:

```swift
@discardableResult
func create(_ draft: TransactionDraft) throws -> LedgerTransaction

func update(_ transaction: LedgerTransaction, with draft: TransactionDraft) throws

private func apply(_ deltas: [WalletDelta], multiplier: Decimal = 1)

private func capture(_ wallets: [CurrencyWallet]) -> [WalletSnapshot]
```

For update: derive old deltas from `TransactionDraft(existing:)`, capture the union of old/new wallets, reverse old deltas, assign every editable field from the new draft onto the existing model, apply new deltas, and call `context.save()`. On failure call `context.rollback()`, restore wallet snapshots, and rethrow. Preserve `id`, `createdAt`, `recognitionImportID`, `originalAmount`, and `discountAmount` unless the draft explicitly supplies replacement values.

Keep existing convenience methods by constructing a draft with `wallet.account?.book?.id`; throw `.walletOutsideBook` when no book exists. This prevents call-site churn while establishing one write path.

- [ ] **Step 4: Run the complete LedgerService test class**

Expected: existing balance, exchange, account, budget, and export tests still pass, plus the new atomic draft tests.

- [ ] **Step 5: Commit the persistence boundary**

```bash
git add MultiCurrencyLedger/Services/LedgerService.swift MultiCurrencyLedgerTests/LedgerServiceTests.swift
git commit -m "refactor: commit transactions through drafts"
```

---

### Task 4: Build Shared Parseable Transaction Form State

**Files:**
- Create: `MultiCurrencyLedger/Views/Entry/TransactionFormState.swift`
- Create: `MultiCurrencyLedger/Views/Entry/TransactionFormSections.swift`
- Create: `MultiCurrencyLedgerTests/TransactionFormStateTests.swift`

**Interfaces:**
- Consumes: `[CurrencyWallet]`, `[LedgerCategory]`
- Produces: `TransactionFormState.init()` and `init(transaction:)`
- Produces: `TransactionFormState.makeDraft(bookID:wallets:categories:) throws -> TransactionDraft`
- Produces: `TransactionFormState.resetTransientFields()`
- Produces: reusable `TransactionFormSections`

- [ ] **Step 1: Add failing form parsing tests**

Cover expense merchant/note parsing, full exchange fields, invalid fee text, adjustment details, and initialization from every transaction type:

```swift
func testExpenseFormBuildsDraftWithMerchantAndTrimmedText() throws {
    let book = LedgerBook(name: "日常")
    let account = Account(name: "现金", type: .cash, book: book)
    let wallet = CurrencyWallet(currency: .CNY, balance: 100, account: account)
    var state = TransactionFormState()
    state.kind = .expense
    state.amountText = "12.50"
    state.sourceWalletID = wallet.id
    state.merchant = "  咖啡店  "
    state.note = "  早餐  "

    let draft = try state.makeDraft(bookID: book.id, wallets: [wallet], categories: [])

    XCTAssertEqual(draft.amount, Decimal(string: "12.50"))
    XCTAssertEqual(draft.merchantOrCounterparty, "咖啡店")
    XCTAssertEqual(draft.note, "早餐")
}
```

- [ ] **Step 2: Run the focused tests and verify the missing state type**

Use `xcodebuild test` with `-only-testing:MultiCurrencyLedgerTests/TransactionFormStateTests`. Expected: compilation fails because `TransactionFormState` is missing.

- [ ] **Step 3: Implement form state as a UI-only value type**

Include exactly these editable properties:

```swift
struct TransactionFormState: Equatable {
    var kind: TransactionKind = .expense
    var amountText = ""
    var destinationAmountText = ""
    var sourceWalletID: UUID?
    var destinationWalletID: UUID?
    var categoryID: UUID?
    var date = Date.now
    var merchant = ""
    var note = ""
    var adjustmentDirection: AdjustmentDirection = .increase
    var adjustmentReason = "手动校准"
    var includesFee = false
    var feeText = ""
}
```

`makeDraft` resolves UUIDs from the provided arrays and uses `DecimalParser`. It rejects blank/invalid principal, destination, and fee values with `TransactionFormError`. `resetTransientFields` clears amount, destination amount, fee, merchant, note, and type-specific state while retaining legal wallet/category selections.

- [ ] **Step 4: Implement shared form sections and rerun tests**

`TransactionFormSections` accepts `@Binding var state`, legal wallets/categories, and computed destination options. It renders the existing amount, wallet, category, adjustment, fee, date, merchant, and note controls using the current `Form` styling. Merchant appears only for expense and income. No save button or persistence call belongs in this component.

Expected: form state tests pass and a generic device build succeeds.

- [ ] **Step 5: Commit the shared form layer**

```bash
git add MultiCurrencyLedger/Views/Entry/TransactionFormState.swift MultiCurrencyLedger/Views/Entry/TransactionFormSections.swift MultiCurrencyLedgerTests/TransactionFormStateTests.swift
git commit -m "feat: share transaction form state"
```

---

### Task 5: Migrate Create, Full Edit, and Copy to the Shared Draft

**Files:**
- Modify: `MultiCurrencyLedger/Views/Entry/EntryView.swift`
- Modify: `MultiCurrencyLedger/Views/Transactions/TransactionEditView.swift`
- Modify: `MultiCurrencyLedger/Views/Transactions/TransactionDetailView.swift`

**Interfaces:**
- Consumes: `TransactionFormState`, `TransactionFormSections`, `LedgerService.create`, `LedgerService.update`
- Produces: `EntryView.init(copying:)`

- [ ] **Step 1: Add copy-state behavior to form-state tests**

Add an explicit factory and test:

```swift
static func copying(_ transaction: LedgerTransaction) -> TransactionFormState
```

The copy must preserve kind, wallets, category, merchant, note, adjustment fields, and fee selection; it must set `date = .now` and clear `amountText`, `destinationAmountText`, and `feeText` so a copied transaction cannot be saved without amount confirmation.

- [ ] **Step 2: Run the focused test and verify it fails**

Expected: failure because `copying(_:)` does not exist or retains monetary values.

- [ ] **Step 3: Replace EntryView persistence branches with one draft create call**

Use one `@State private var formState` and render `TransactionFormSections`. Saving becomes:

```swift
private func performSave() {
    guard let bookID = selectedBook?.id else {
        errorMessage = "请选择账本"
        return
    }
    do {
        let draft = try formState.makeDraft(bookID: bookID, wallets: allWallets, categories: categories)
        try LedgerService(context: context).create(draft)
        formState.resetTransientFields()
        successMessage = "已保存"
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

Negative-balance warning uses the draft's negative deltas against current wallet balances. Remove the five type-specific `LedgerService.create…` branches.

- [ ] **Step 4: Replace partial edit and add copy action**

`TransactionEditView` initializes `TransactionFormState(transaction:)`, shows the same shared sections, and calls `LedgerService.update(transaction, with: draft)`. All type, wallet, category, merchant, amount, destination amount, fee, date, adjustment, and note fields become editable.

`TransactionDetailView` adds `Button("复制为新交易")` and presents `EntryView(copying: transaction)` in a sheet. The copy factory clears monetary fields and uses the current date.

Run the form-state tests, LedgerService tests, and a generic iOS build. Expected: tests pass and `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the complete create/edit/copy loop**

```bash
git add MultiCurrencyLedger/Views/Entry/EntryView.swift MultiCurrencyLedger/Views/Transactions/TransactionEditView.swift MultiCurrencyLedger/Views/Transactions/TransactionDetailView.swift MultiCurrencyLedger/Views/Entry/TransactionFormState.swift MultiCurrencyLedgerTests/TransactionFormStateTests.swift
git commit -m "feat: complete transaction create edit and copy"
```

---

### Task 6: Add Per-Book Recent Defaults and Continuous Entry

**Files:**
- Create: `MultiCurrencyLedger/Services/RecentTransactionDefaultsStore.swift`
- Create: `MultiCurrencyLedgerTests/RecentTransactionDefaultsStoreTests.swift`
- Modify: `MultiCurrencyLedger/Views/Entry/EntryView.swift`

**Interfaces:**
- Produces: `RecentTransactionDefaultsStore.load(bookID:) -> RecentTransactionDefaults?`
- Produces: `save(_:bookID:)`
- Produces: `applyValidDefaults(to:bookID:wallets:categories:)`

- [ ] **Step 1: Write failing persistence and stale-reference tests**

Use an isolated `UserDefaults(suiteName:)` and cover per-book isolation, deleted wallet fallback, hidden account rejection, category type mismatch, and separate recent expense/income categories:

```swift
func testInvalidSavedWalletFallsBackToFirstLegalWallet() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = RecentTransactionDefaultsStore(defaults: defaults)
    let book = LedgerBook(name: "日常")
    let account = Account(name: "现金", type: .cash, book: book)
    let legal = CurrencyWallet(currency: .CNY, account: account)
    store.save(RecentTransactionDefaults(kind: .expense, sourceWalletID: UUID(), expenseCategoryID: nil, incomeCategoryID: nil), bookID: book.id)
    var form = TransactionFormState()

    store.applyValidDefaults(to: &form, bookID: book.id, wallets: [legal], categories: [])

    XCTAssertEqual(form.sourceWalletID, legal.id)
}
```

- [ ] **Step 2: Run the focused tests and verify missing-store failure**

Expected: compilation fails because the defaults store does not exist.

- [ ] **Step 3: Implement Codable IDs only**

Persist this value under `recent-transaction.<lowercased-book-uuid>`:

```swift
struct RecentTransactionDefaults: Codable, Equatable {
    var kind: TransactionKind
    var sourceWalletID: UUID?
    var expenseCategoryID: UUID?
    var incomeCategoryID: UUID?
}
```

Do not persist amounts, notes, merchants, balances, screenshots, or transaction bodies. `applyValidDefaults` accepts only enabled wallets on visible accounts in the requested book and categories matching the selected kind; otherwise it selects the first legal candidate.

- [ ] **Step 4: Integrate with successful saves and rerun tests**

On `EntryView.onAppear`, apply defaults after wallets are loaded. After a successful create, save the legal selections, clear transient fields, retain source/category selections, and keep the sheet open for continuous entry. Changing books reapplies that book's defaults.

Expected: store tests pass and a generic device build succeeds.

- [ ] **Step 5: Commit recent defaults**

```bash
git add MultiCurrencyLedger/Services/RecentTransactionDefaultsStore.swift MultiCurrencyLedger/Views/Entry/EntryView.swift MultiCurrencyLedgerTests/RecentTransactionDefaultsStoreTests.swift
git commit -m "feat: remember recent entry selections"
```

---

### Task 7: Complete Search, Filters, Sorting, and Entry Point

**Files:**
- Modify: `MultiCurrencyLedger/Views/Transactions/TransactionListView.swift`
- Modify: `MultiCurrencyLedger/Views/Transactions/TransactionFilterView.swift`
- Modify: `MultiCurrencyLedger/Views/Home/HomeView.swift`
- Modify: `MultiCurrencyLedger/Models/TransactionQueryState.swift`
- Modify: `MultiCurrencyLedgerTests/TransactionQueryStateTests.swift`

**Interfaces:**
- Consumes: `TransactionQueryState.applying`
- Produces: `TransactionFilterView(query:baselineBookID:books:accounts:categories:)`
- Produces: visible search route from `HomeView`

- [ ] **Step 1: Extend failing query tests for every filter and stable sorting**

Add independent assertions for all-books selection, predefined date ranges, min/max amount, source or destination account, any transaction currency field, kind, category, case/diacritic-insensitive keyword, and deterministic ties for all four sort orders. Include a reversed custom date range and assert a validation error rather than silently returning an empty list.

- [ ] **Step 2: Run the query tests and verify the reversed-range failure**

Expected: the new reversed-range test fails because query application has no validation result.

- [ ] **Step 3: Add explicit query validation**

Add:

```swift
enum TransactionQueryError: LocalizedError, Equatable {
    case reversedDateRange
    case invalidAmountRange
}

func validated() throws -> TransactionQueryState
```

`validated()` rejects a start after end, negative minimum/maximum, and minimum greater than maximum. `TransactionListView` validates before applying and presents the localized error in the filter sheet.

- [ ] **Step 4: Replace local filter variables with TransactionQueryState**

`TransactionListView` owns one query initialized to the current selected book, uses `.searchable(text: $query.keyword)`, and derives rows with `try query.validated().applying(to: transactions)`. The filter sheet provides:

- book picker with current book as default and explicit “全部账本”;
- time preset plus custom start/end dates;
- minimum and maximum amount fields;
- account, currency, type, category, and sort pickers;
- a filter summary and “保留当前账本并清除筛选”.

Accounts shown in the filter follow the selected query book; all-books mode shows all visible accounts. Add a search button to the existing `HomeHeader` and present `TransactionListView` without changing the bottom bar.

Run query tests and a generic device build. Expected: all pass.

- [ ] **Step 5: Commit search completion**

```bash
git add MultiCurrencyLedger/Models/TransactionQueryState.swift MultiCurrencyLedger/Views/Transactions/TransactionListView.swift MultiCurrencyLedger/Views/Transactions/TransactionFilterView.swift MultiCurrencyLedger/Views/Home/HomeView.swift MultiCurrencyLedgerTests/TransactionQueryStateTests.swift
git commit -m "feat: complete transaction search and filters"
```

---

### Task 8: Route Recognition Confirmation Through TransactionDraft

**Files:**
- Modify: `MultiCurrencyLedger/Services/RecognitionEntryService.swift`
- Modify: `MultiCurrencyLedger/Services/LedgerService.swift`
- Modify: `MultiCurrencyLedgerTests/RecognitionEntryServiceTests.swift`
- Modify: `MultiCurrencyLedgerTests/LedgerServiceTests.swift`

**Interfaces:**
- Consumes: `TransactionDraft`, atomic LedgerService commit boundary
- Produces: `LedgerService.create(_:importRecord:importStatus:)`

- [ ] **Step 1: Add recognition atomicity tests**

Add tests that confirmed merchant/original/discount values survive the draft adapter, that invalid category type leaves the wallet unchanged, and that a simulated save failure leaves both the import record and transaction uncommitted.

Use this success assertion:

```swift
XCTAssertEqual(transaction.merchantOrCounterparty, confirmed.merchantForPersistence)
XCTAssertEqual(transaction.originalAmount, confirmed.originalAmount)
XCTAssertEqual(transaction.discountAmount, confirmed.discountAmount)
XCTAssertEqual(record.transactionID, transaction.id)
```

- [ ] **Step 2: Run focused recognition tests and observe the old direct-model path**

Run `RecognitionEntryServiceTests` and the recognition-related `LedgerServiceTests`. Expected: the new draft API test fails because recognition still constructs `LedgerTransaction` directly.

- [ ] **Step 3: Add an atomic draft-plus-audit overload**

Implement:

```swift
@discardableResult
func create(
    _ draft: TransactionDraft,
    importRecord: RecognitionImportRecord,
    importStatus: RecognitionImportStatus
) throws -> LedgerTransaction
```

It validates the draft, applies wallet deltas, inserts the transaction and record, assigns both linkage IDs/status fields, and saves once. Rollback restores all wallet snapshots.

- [ ] **Step 4: Simplify RecognitionEntryService to an adapter**

Keep recognition-specific confidence/type/fee checks, then create a `TransactionDraft` with paid amount, occurred date, note, merchant, category, original amount, and discount. Call the new LedgerService overload. Run focused tests and a generic device build. Expected: all pass.

- [ ] **Step 5: Commit recognition integration**

```bash
git add MultiCurrencyLedger/Services/RecognitionEntryService.swift MultiCurrencyLedger/Services/LedgerService.swift MultiCurrencyLedgerTests/RecognitionEntryServiceTests.swift MultiCurrencyLedgerTests/LedgerServiceTests.swift
git commit -m "refactor: confirm recognition through transaction drafts"
```

---

### Task 9: Phase 1 Regression and Handoff

**Files:**
- Modify only if verification exposes a defect: files already changed in Tasks 1–8
- Create: `docs/superpowers/verification/2026-07-13-icost-phase-1-core-ledger.md`

**Interfaces:**
- Verifies all Phase 1 acceptance criteria; produces no new product API.

- [ ] **Step 1: Audit source boundaries**

Run:

```bash
rg -n 'wallet\.balance\s*[+\-]?=' MultiCurrencyLedger --glob '*.swift'
rg -n 'LedgerTransaction\(' MultiCurrencyLedger/Views --glob '*.swift'
rg -n 'createExpense|createIncome|createTransfer|createExchange|createAdjustment' MultiCurrencyLedger/Views --glob '*.swift'
```

Expected: wallet balance writes exist only in account initialization and `LedgerService`; transaction construction and type-specific creation calls do not remain in SwiftUI views.

- [ ] **Step 2: Build app and tests without visual Simulator use**

```bash
xcodebuild build-for-testing -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData
xcodebuild build -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST BUILD SUCCEEDED` and `BUILD SUCCEEDED`.

- [ ] **Step 3: Execute the complete unit suite once**

```bash
xcodebuild test-without-building -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath .build/DerivedData
```

Expected: every test passes. This is the single Phase 1 full-suite simulator-backed execution; do not open the Simulator UI for manual exploration.

- [ ] **Step 4: Record evidence**

The verification document must list the exact commands, pass counts, generic build result, source-audit result, and any intentionally deferred visual/system check. It must explicitly state that tags, refunds, reimbursements, split payments, schedules, installments, sync, widgets, and locations remain in later phases.

- [ ] **Step 5: Commit verification evidence**

```bash
git add docs/superpowers/verification/2026-07-13-icost-phase-1-core-ledger.md
git commit -m "test: verify core ledger phase"
```

---

## Phase 1 Acceptance Checklist

- [ ] Home summary, budget, and records use the same selected book and selected month.
- [ ] Transaction list defaults to the current book and can explicitly search all books.
- [ ] Create/edit/copy/recognition all build `TransactionDraft` and commit through `LedgerService`.
- [ ] Full edit changes type, wallets, category, merchant, amount, destination amount, fee, date, adjustment details, and note.
- [ ] Failed updates leave the original transaction and every wallet balance unchanged.
- [ ] Copy requires a new amount confirmation and defaults its date to now.
- [ ] Recent selections are isolated per book and safely ignore stale IDs.
- [ ] Search combines keyword, book, date, amount, account, currency, kind, category, and sort.
- [ ] No unrelated working-tree file is staged or overwritten.
- [ ] Routine compilation uses generic destinations; Simulator-backed execution is limited to required tests.
