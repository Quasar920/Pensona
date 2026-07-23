import SwiftUI

enum EntryAmountTarget {
    case source
    case destination
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
                    Text(sourceWallet?.currencyCode ?? "--")
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
            }

            Divider().opacity(0.32)
            HStack(alignment: .center, spacing: 8) {
                Text("备注")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("可选，直接输入", text: $state.note)
                    .font(.caption2)
                    .textFieldStyle(.plain)
                    .frame(height: 16)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .ledgerSurface(.summary, cornerRadius: 20)
        .frame(maxWidth: .infinity)
        .onChange(of: state.amountText) { _, _ in updateExchange(driver: .sourceAmount) }
        .onChange(of: state.destinationAmountText) { _, _ in updateExchange(driver: .destinationAmount) }
        .onChange(of: state.exchangeRateText) { _, _ in updateExchange(driver: .rate) }
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
}
