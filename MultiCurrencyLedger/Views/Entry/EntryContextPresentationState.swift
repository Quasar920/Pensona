import CoreGraphics
import Foundation

enum EntryContextOverlayKind: String, CaseIterable, Hashable {
    case account
    case aa
    case splitPayment
    case discount
    case fee
    case foreignExpense

    var usesGeniePresentation: Bool {
        switch self {
        case .account, .aa, .splitPayment, .discount, .fee:
            true
        case .foreignExpense:
            false
        }
    }
}

enum EntryContextPresentationPhase: Equatable {
    case closed
    case preparing
    case opening
    case presented
    case closing
}

enum EntryContextDismissalIntent: Equatable {
    case commit
    case cancel
}

enum EntryContextInputTarget: Equatable {
    case mainAmount
    case aaPeople
    case splitPayment(index: Int)
    case discount
    case fee
}

struct EntryContextDraft: Equatable {
    var transactionKind: TransactionKind
    var selectedWalletID: UUID?
    var discountWalletID: UUID?
    var feeWalletID: UUID?
    var aaPeople: Int
    var aaPeopleText: String
    var aaNote: String?
    var paymentParts: [PaymentPartFormState]
    var discountAmountText: String
    var feeInputMode: FeeInputMode
    var feeInputText: String
    var feeTemplateName: String?
    var feeCurrencyCode: String

    init(
        kind: EntryContextOverlayKind,
        state: TransactionFormState,
        wallets: [CurrencyWallet]
    ) {
        transactionKind = state.kind
        selectedWalletID = state.sourceWalletID
        discountWalletID = state.discountWalletID
            ?? (state.kind == .transfer ? state.destinationWalletID : nil)
        feeWalletID = state.feeWalletID
            ?? ((state.kind == .transfer || state.kind == .exchange) ? state.sourceWalletID : nil)
        aaPeople = max(2, (state.aaSplitDraft?.otherPeopleCount ?? 1) + 1)
        aaPeopleText = String(aaPeople)
        aaNote = state.aaSplitDraft?.note
        discountAmountText = state.discountAmountText
        feeInputMode = state.includesFee && state.feeRatePercentage == nil
            ? .fixedAmount
            : .percentage
        feeInputText = state.feeRatePercentage.map {
            NSDecimalNumber(decimal: $0).stringValue
        } ?? state.feeText
        feeTemplateName = state.feeTemplateName
        feeCurrencyCode = wallets.first(where: { $0.id == state.feeWalletID })?.currencyCode
            ?? wallets.first(where: { $0.id == state.sourceWalletID })?.currencyCode
            ?? SupportedCurrency.CNY.rawValue

        if kind == .splitPayment, (!state.usesSplitPayment || state.paymentParts.count < 2) {
            var stagedState = state
            stagedState.setSplitPaymentEnabled(true, wallets: wallets)
            paymentParts = stagedState.paymentParts
        } else {
            paymentParts = state.paymentParts
        }
    }

    var validatedAAPeople: Int? {
        guard let value = Int(aaPeopleText), value >= 2 else { return nil }
        return value
    }

    var hasValidAAPeople: Bool {
        validatedAAPeople != nil
    }

    var hasValidFeeInput: Bool {
        DecimalParser.parse(feeInputText).map { $0 > 0 } == true
    }

    var hasValidDiscountSelection: Bool {
        guard DecimalParser.parse(discountAmountText).map({ $0 > 0 }) == true else { return true }
        return transactionKind != .transfer || discountWalletID != nil
    }

    var hasValidFeeSelection: Bool {
        guard hasValidFeeInput else { return false }
        return transactionKind != .transfer && transactionKind != .exchange
            || feeWalletID != nil
    }

    mutating func setAAPeople(_ value: Int) {
        aaPeople = max(2, value)
        aaPeopleText = String(aaPeople)
    }

    mutating func synchronizeAAPeopleInput() -> Bool {
        guard let value = validatedAAPeople else { return false }
        aaPeople = value
        aaPeopleText = String(value)
        return true
    }

    func apply(
        kind: EntryContextOverlayKind,
        to state: inout TransactionFormState
    ) {
        switch kind {
        case .account:
            state.sourceWalletID = selectedWalletID
        case .aa:
            let total = DecimalParser.parse(state.amountText) ?? 0
            let owed = total * Decimal(aaPeople - 1) / Decimal(aaPeople)
            state.aaSplitDraft = AASplitDraft(
                otherPeopleCount: aaPeople - 1,
                calculationMode: .equal,
                othersOwedAmount: owed,
                note: aaNote,
                basedOnAmount: total
            )
        case .splitPayment:
            state.usesSplitPayment = true
            state.paymentParts = paymentParts
        case .discount:
            state.discountAmountText = discountAmountText
            state.discountWalletID = DecimalParser.parse(discountAmountText).map({ $0 > 0 }) == true
                && state.kind == .transfer
                ? discountWalletID
                : nil
        case .fee:
            let applied = state.applyFee(
                inputText: feeInputText,
                mode: feeInputMode,
                currencyCode: feeCurrencyCode,
                templateName: feeTemplateName
            )
            if applied, (state.kind == .transfer || state.kind == .exchange) {
                state.feeWalletID = feeWalletID ?? state.sourceWalletID
            }
        case .foreignExpense:
            break
        }
    }
}

struct EntryContextPresentationState: Equatable {
    private(set) var kind: EntryContextOverlayKind?
    private(set) var phase: EntryContextPresentationPhase = .closed
    var draft: EntryContextDraft?
    var activePaymentPart = 0
    private(set) var isEditingAAPeople = false
    private(set) var sourceTagVisual: EntryContextTagVisual?
    var sourceFrame: CGRect = .zero
    var targetFrame: CGRect = .zero
    /// Genie collapse progress: 0 is the fully expanded panel and 1 is the
    /// panel completely gathered into the source tag.
    var progress: Double = 1
    private(set) var dismissalIntent: EntryContextDismissalIntent?

    var isActive: Bool {
        phase != .closed
    }

    var isTransitioning: Bool {
        phase == .preparing || phase == .opening || phase == .closing
    }

    var usesKeypad: Bool {
        true
    }

    var hiddenTagKind: EntryContextOverlayKind? {
        isActive ? kind : nil
    }

    var backdropProgress: Double {
        switch phase {
        case .closed, .preparing:
            0
        case .opening, .closing:
            1 - progress
        case .presented:
            1
        }
    }

    var inputTarget: EntryContextInputTarget {
        switch kind {
        case .aa where isEditingAAPeople:
            .aaPeople
        case .splitPayment:
            .splitPayment(index: activePaymentPart)
        case .discount:
            .discount
        case .fee:
            .fee
        default:
            .mainAmount
        }
    }

    mutating func prepare(
        kind: EntryContextOverlayKind,
        sourceFrame: CGRect,
        sourceTagVisual: EntryContextTagVisual,
        state: TransactionFormState,
        wallets: [CurrencyWallet]
    ) {
        guard phase == .closed, kind.usesGeniePresentation else { return }
        self.kind = kind
        self.sourceFrame = sourceFrame
        self.sourceTagVisual = sourceTagVisual
        targetFrame = .zero
        draft = EntryContextDraft(kind: kind, state: state, wallets: wallets)
        activePaymentPart = 0
        isEditingAAPeople = kind == .aa
        progress = 1
        dismissalIntent = nil
        phase = .preparing
    }

    mutating func beginOpening(targetFrame: CGRect) {
        guard phase == .preparing else { return }
        self.targetFrame = targetFrame
        phase = .opening
    }

    mutating func finishOpening() {
        guard phase == .opening else { return }
        progress = 0
        phase = .presented
    }

    mutating func beginClosing(intent: EntryContextDismissalIntent) {
        guard phase == .presented else { return }
        progress = 0
        dismissalIntent = intent
        phase = .closing
    }

    mutating func finishClosing(state: inout TransactionFormState) {
        guard phase == .closing else { return }
        if dismissalIntent == .commit, let kind, let draft {
            draft.apply(kind: kind, to: &state)
        }
        reset()
    }

    mutating func settleInterruptedTransition(state: inout TransactionFormState) {
        switch phase {
        case .opening, .preparing:
            progress = 0
            phase = .presented
        case .closing:
            finishClosing(state: &state)
        case .closed, .presented:
            break
        }
    }

    mutating func updateTargetFrame(_ frame: CGRect) {
        guard !frame.isNull, !frame.isEmpty else { return }
        targetFrame = frame
    }

    mutating func selectPaymentPart(_ index: Int) {
        guard let parts = draft?.paymentParts, parts.indices.contains(index) else { return }
        activePaymentPart = index
    }

    mutating func selectAAPeopleInput() {
        guard kind == .aa else { return }
        isEditingAAPeople = true
    }

    mutating func synchronizePendingInput() -> Bool {
        if kind == .aa {
            return draft?.synchronizeAAPeopleInput() == true
        }
        if kind == .fee {
            return draft?.hasValidFeeSelection == true
        }
        if kind == .discount {
            return draft?.hasValidDiscountSelection == true
        }
        return true
    }

    private mutating func reset() {
        kind = nil
        phase = .closed
        draft = nil
        activePaymentPart = 0
        isEditingAAPeople = false
        sourceTagVisual = nil
        sourceFrame = .zero
        targetFrame = .zero
        progress = 1
        dismissalIntent = nil
    }
}
