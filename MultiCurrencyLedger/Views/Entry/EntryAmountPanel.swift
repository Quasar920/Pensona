import SwiftUI

enum EntryAmountTarget {
    case source
    case destination
    case settlement
}

struct EntryAmountPanel: View {
    @Binding var state: TransactionFormState
    @Binding var activeTarget: EntryAmountTarget
    let sourceWallet: CurrencyWallet?
    let destinationWallet: CurrencyWallet?
    let categoryPath: String?
    let validation: EntryValidationState
    @State private var synchronizingExchange = false

    private var sourceDigits: Int {
        SupportedCurrency.fractionDigits(for: sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue)
    }
    private var destinationDigits: Int {
        SupportedCurrency.fractionDigits(for: destinationWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue)
    }
    private var isCrossCurrencyCreditRepayment: Bool {
        state.kind == .transfer
            && destinationWallet?.account?.type == .creditCard
            && sourceWallet?.currencyCode != destinationWallet?.currencyCode
    }
    private var isInstantForeignExpense: Bool {
        guard state.kind == .expense,
              sourceWallet?.account?.type == .creditCard,
              state.foreignSettlementMode == .instant,
              let foreignCode = state.foreignOriginalCurrencyCode else { return false }
        return foreignCode != settlementCurrencyCode
    }
    private var settlementCurrencyCode: String {
        sourceWallet?.account?.defaultSettlementCurrencyCode
            ?? sourceWallet?.currencyCode
            ?? SupportedCurrency.CNY.rawValue
    }
    private var displayedSourceCurrencyCode: String {
        if state.kind == .expense,
           state.foreignSettlementMode != nil,
           let code = state.foreignOriginalCurrencyCode {
            return code
        }
        return sourceWallet?.currencyCode ?? "--"
    }

    var body: some View {
        VStack(spacing: 2) {
            if let categoryPath {
                Text(categoryPath)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button { activeTarget = .source } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayedSourceCurrencyCode)
                        .font(.headline.monospaced())
                        .foregroundStyle(.secondary)
                    Text(state.amountText.isEmpty ? "0" : state.amountText)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(activeTarget == .source ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            EntryInlineValidation(message: validation[.amount])

            if state.kind == .exchange {
                HStack(spacing: 8) {
                    Button { activeTarget = .destination } label: {
                        HStack(spacing: 6) {
                            Text("买入").foregroundStyle(.secondary)
                            Text(destinationWallet?.currencyCode ?? "--")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(state.destinationAmountText.isEmpty ? "0" : state.destinationAmountText)
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            activeTarget == .destination ? LedgerPalette.accent.opacity(0.10) : .clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    TextField("汇率", text: $state.exchangeRateText)
                        .keyboardType(.decimalPad)
                        .font(.subheadline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: 125, minHeight: 44)
                        .background(Color.primary.opacity(0.045), in: Capsule())
                        .accessibilityLabel("换汇汇率")
                }
                EntryInlineValidation(message: validation[.destinationAmount])
            } else if isCrossCurrencyCreditRepayment {
                HStack(spacing: 8) {
                    Button { activeTarget = .destination } label: {
                        HStack(spacing: 6) {
                            Text("偿还").foregroundStyle(.secondary)
                            Text(destinationWallet?.currencyCode ?? "--")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(state.destinationAmountText.isEmpty ? "0" : state.destinationAmountText)
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            activeTarget == .destination ? LedgerPalette.accent.opacity(0.10) : .clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    Text(actualRepaymentRateText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                EntryInlineValidation(message: validation[.destinationAmount])
            } else if isInstantForeignExpense {
                HStack(spacing: 8) {
                    Button { activeTarget = .settlement } label: {
                        HStack(spacing: 6) {
                            Text("结算").foregroundStyle(.secondary)
                            Text(settlementCurrencyCode)
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(state.settledAmountText.isEmpty ? "0" : state.settledAmountText)
                                .font(.title3.weight(.semibold).monospacedDigit())
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(
                            activeTarget == .settlement ? LedgerPalette.accent.opacity(0.10) : .clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 4)
                    Text(actualExpenseRateText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Divider().opacity(0.32)
            HStack(alignment: .center, spacing: 8) {
                Text("备注")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("可选，直接输入", text: $state.note)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .frame(height: 20)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .overlay(alignment: .top) { Divider().opacity(0.58) }
        .overlay(alignment: .bottom) { Divider().opacity(0.58) }
        .frame(maxWidth: .infinity)
        .onChange(of: state.amountText) { _, _ in updateExchange(driver: .sourceAmount) }
        .onChange(of: state.amountText) { _, _ in updateRepaymentRate() }
        .onChange(of: state.destinationAmountText) { _, _ in
            updateExchange(driver: .destinationAmount)
            updateRepaymentRate()
        }
        .onChange(of: state.exchangeRateText) { _, _ in updateExchange(driver: .rate) }
        .onChange(of: destinationWallet?.id) { _, _ in updateRepaymentRate() }
        .onAppear(perform: updateRepaymentRate)
    }

    private func updateExchange(driver: EntryExchangeDriver) {
        guard state.kind == .exchange, !synchronizingExchange else { return }
        synchronizingExchange = true
        let result = EntryExchangeCalculation.update(
            sourceText: state.amountText,
            destinationText: state.destinationAmountText,
            rateText: state.exchangeRateText,
            driver: driver,
            sourceFractionDigits: sourceDigits,
            destinationFractionDigits: destinationDigits
        )
        state.amountText = result.source
        state.destinationAmountText = result.destination
        state.exchangeRateText = result.rate
        Task { @MainActor in synchronizingExchange = false }
    }

    private var actualRepaymentRateText: String {
        guard let rate = DecimalParser.parse(state.exchangeRateText), rate > 0 else {
            return "实际汇率 --"
        }
        return "实际汇率 \(EntryCalculationState.string(rate))"
    }

    private var actualExpenseRateText: String {
        guard let foreignAmount = DecimalParser.parse(state.amountText), foreignAmount > 0,
              let settledAmount = DecimalParser.parse(state.settledAmountText), settledAmount > 0 else {
            return "实际汇率 --"
        }
        let rate = EntryCalculationState.round(settledAmount / foreignAmount, scale: 8)
        return "实际汇率 \(EntryCalculationState.string(rate))"
    }

    private func updateRepaymentRate() {
        guard isCrossCurrencyCreditRepayment,
              let sourceAmount = DecimalParser.parse(state.amountText), sourceAmount > 0,
              let foreignAmount = DecimalParser.parse(state.destinationAmountText), foreignAmount > 0 else {
            if state.kind == .transfer, destinationWallet?.account?.type == .creditCard {
                state.exchangeRateText = ""
            }
            return
        }
        let rate = EntryCalculationState.round(sourceAmount / foreignAmount, scale: 8)
        state.exchangeRateText = EntryCalculationState.string(rate)
    }
}
