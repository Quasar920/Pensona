import SwiftUI

struct EntryMovementPanel: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let destinationWallet: CurrencyWallet?
    let destinationError: String?
    let selectSource: () -> Void
    let selectDestination: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                walletButton(
                    title: state.kind == .exchange ? AppLocalization.string("卖出") : AppLocalization.string("转出"),
                    wallet: sourceWallet,
                    action: selectSource
                )
                Button(action: swapDirection) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("交换方向")
                walletButton(
                    title: state.kind == .exchange ? AppLocalization.string("买入") : AppLocalization.string("转入"),
                    wallet: destinationWallet,
                    action: selectDestination
                )
            }
            EntryInlineValidation(message: destinationError)

            Toggle("包含手续费", isOn: $state.includesFee)
                .font(.subheadline.weight(.medium))
            if state.includesFee {
                HStack {
                    Text("手续费")
                    TextField("0", text: $state.feeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .padding(14)
        .ledgerSurface(.functional, cornerRadius: 24)
    }

    private func walletButton(
        title: String,
        wallet: CurrencyWallet?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(wallet?.account?.name ?? AppLocalization.string("请选择"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(wallet?.currencyCode ?? "--")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 10)
            .background(LedgerPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(LedgerGlassPressStyle())
    }

    private func swapDirection() {
        (state.sourceWalletID, state.destinationWalletID) = (state.destinationWalletID, state.sourceWalletID)
        (state.amountText, state.destinationAmountText) = (state.destinationAmountText, state.amountText)
        if let rate = DecimalParser.parse(state.exchangeRateText), rate > 0 {
            state.exchangeRateText = EntryCalculationState.string(
                EntryCalculationState.round(1 / rate, scale: 8)
            )
        }
    }
}
