import Foundation

enum EntrySaveIntent: Equatable {
    case next
    case complete
}

enum EntryField: Hashable {
    case amount
    case sourceWallet
    case destinationWallet
    case destinationAmount
    case category
}

struct EntryValidationState: Equatable {
    private(set) var messages: [EntryField: String] = [:]
    var generalMessage: String?

    var isEmpty: Bool { messages.isEmpty && generalMessage == nil }

    subscript(field: EntryField) -> String? {
        messages[field]
    }

    mutating func set(_ message: String?, for field: EntryField) {
        messages[field] = message
    }

    mutating func clear() {
        messages.removeAll()
        generalMessage = nil
    }
}

/// Submission and validation state shared by create and edit entry modes.
struct EntrySessionState {
    enum Mode: Equatable {
        case create
        case edit(transactionID: UUID, bookID: UUID)
    }

    let mode: Mode
    var validation = EntryValidationState()
    private(set) var isSubmitting = false
    private(set) var saveIntent: EntrySaveIntent = .complete

    init(mode: Mode = .create) {
        self.mode = mode
    }

    mutating func validate(
        form: TransactionFormState,
        wallets: [CurrencyWallet],
        categories: [LedgerCategory]
    ) -> Bool {
        validation.clear()
        let sourceWallet = wallets.first(where: { $0.id == form.sourceWalletID })
        let amountIsValid: Bool
        if form.kind == .adjustment, form.adjustmentInputMode == .finalBalance {
            if let targetBalance = DecimalParser.parse(form.amountText), let sourceWallet {
                amountIsValid = targetBalance >= 0 && sourceWallet.balance != targetBalance
            } else {
                amountIsValid = false
            }
        } else {
            amountIsValid = DecimalParser.parse(form.amountText).map({ $0 > 0 }) == true
        }
        if !amountIsValid {
            validation.set("请输入大于 0 的有效金额", for: .amount)
        }
        if sourceWallet == nil {
            validation.set("请选择账户", for: .sourceWallet)
        }
        if form.kind == .expense || form.kind == .income {
            if !categories.contains(where: { $0.id == form.categoryID && $0.type == (form.kind == .income ? .income : .expense) }) {
                validation.set("请选择分类", for: .category)
            }
        }
        if form.kind == .transfer || form.kind == .exchange {
            if !wallets.contains(where: { $0.id == form.destinationWalletID }) {
                validation.set("请选择转入账户", for: .destinationWallet)
            }
        }
        if form.kind == .exchange,
           DecimalParser.parse(form.destinationAmountText).map({ $0 > 0 }) != true {
            validation.set("请输入大于 0 的换入金额", for: .destinationAmount)
        }
        return validation.isEmpty
    }

    mutating func beginSubmission(intent: EntrySaveIntent) -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        saveIntent = intent
        return true
    }

    mutating func finishSubmission(error: Error? = nil) {
        isSubmitting = false
        validation.generalMessage = error?.localizedDescription
    }
}

enum EntryCalculationOperator: String, Equatable {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"
}

struct EntryCalculationState: Equatable {
    private(set) var leftValue: Decimal?
    private(set) var pendingOperator: EntryCalculationOperator?
    private(set) var operandText = ""

    var expression: String? {
        guard let leftValue, let pendingOperator else { return nil }
        return "\(Self.string(leftValue)) \(pendingOperator.rawValue) \(operandText)"
    }

    mutating func begin(_ operation: EntryCalculationOperator, displayText: String) {
        guard let value = DecimalParser.parse(displayText) else { return }
        leftValue = value
        pendingOperator = operation
        operandText = ""
    }

    mutating func append(_ token: String, displayText: inout String, fractionDigits: Int) {
        if pendingOperator != nil {
            operandText = Self.appending(token, to: operandText, fractionDigits: fractionDigits)
            recalculate(displayText: &displayText, fractionDigits: fractionDigits)
        } else {
            displayText = Self.appending(token, to: displayText, fractionDigits: fractionDigits)
        }
    }

    mutating func delete(displayText: inout String, fractionDigits: Int) {
        if pendingOperator != nil {
            guard !operandText.isEmpty else {
                reset()
                return
            }
            operandText.removeLast()
            if operandText.isEmpty {
                displayText = leftValue.map(Self.string) ?? ""
            } else {
                recalculate(displayText: &displayText, fractionDigits: fractionDigits)
            }
        } else if !displayText.isEmpty {
            displayText.removeLast()
        }
    }

    mutating func clear(displayText: inout String) {
        displayText = ""
        reset()
    }

    mutating func reset() {
        leftValue = nil
        pendingOperator = nil
        operandText = ""
    }

    private mutating func recalculate(displayText: inout String, fractionDigits: Int) {
        guard let leftValue, let pendingOperator,
              let rightValue = DecimalParser.parse(operandText) else { return }
        let result: Decimal
        switch pendingOperator {
        case .add: result = leftValue + rightValue
        case .subtract: result = leftValue - rightValue
        case .multiply: result = leftValue * rightValue
        case .divide:
            guard rightValue != 0 else { return }
            result = leftValue / rightValue
        }
        displayText = Self.string(Self.round(max(result, 0), scale: fractionDigits))
    }

    private static func appending(_ token: String, to current: String, fractionDigits: Int) -> String {
        if token == "." {
            guard fractionDigits > 0, !current.contains(".") else { return current }
            return current.isEmpty ? "0." : current + "."
        }
        if current == "0" && token != "00" { return token }
        let candidate = current + token
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.first?.count ?? 0 <= 12,
              parts.count < 2 || parts[1].count <= fractionDigits else { return current }
        return candidate
    }

    static func round(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return result
    }

    static func string(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

enum EntryExchangeDriver {
    case sourceAmount
    case destinationAmount
    case rate
}

enum EntryExchangeCalculation {
    static func update(
        sourceText: String,
        destinationText: String,
        rateText: String,
        driver: EntryExchangeDriver,
        sourceFractionDigits: Int,
        destinationFractionDigits: Int
    ) -> (source: String, destination: String, rate: String) {
        let source = DecimalParser.parse(sourceText)
        let destination = DecimalParser.parse(destinationText)
        let rate = DecimalParser.parse(rateText)
        switch driver {
        case .sourceAmount:
            guard let source, source > 0, let rate, rate > 0 else {
                return (sourceText, destinationText, rateText)
            }
            let value = EntryCalculationState.round(source * rate, scale: destinationFractionDigits)
            return (sourceText, EntryCalculationState.string(value), rateText)
        case .destinationAmount:
            guard let source, source > 0, let destination, destination > 0 else {
                return (sourceText, destinationText, rateText)
            }
            let value = EntryCalculationState.round(destination / source, scale: 8)
            return (sourceText, destinationText, EntryCalculationState.string(value))
        case .rate:
            guard let rate, rate > 0 else {
                return (sourceText, destinationText, rateText)
            }
            if let source, source > 0 {
                let value = EntryCalculationState.round(source * rate, scale: destinationFractionDigits)
                return (sourceText, EntryCalculationState.string(value), rateText)
            }
            guard let destination, destination > 0 else {
                return (sourceText, destinationText, rateText)
            }
            let value = EntryCalculationState.round(destination / rate, scale: sourceFractionDigits)
            return (EntryCalculationState.string(value), destinationText, rateText)
        }
    }
}

enum AdjustmentInputMode: String, CaseIterable, Identifiable {
    case finalBalance
    case delta

    var id: String { rawValue }
    var title: String {
        self == .finalBalance ? AppLocalization.string( "最终余额") : AppLocalization.string( "增减金额")
    }
}
