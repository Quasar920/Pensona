import SwiftUI

struct EntryMovementPanel: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let destinationWallet: CurrencyWallet?
    let destinationError: String?
    let selectSource: () -> Void
    let selectDestination: () -> Void
    let selectDestinationCurrency: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                walletButton(
                    title: state.kind == .exchange ? AppLocalization.string("卖出") : AppLocalization.string("转出"),
                    wallet: sourceWallet,
                    action: selectSource,
                    currencyAction: selectSource
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
                    action: selectDestination,
                    currencyAction: destinationWallet?.account?.type == .creditCard
                        ? selectDestinationCurrency
                        : selectDestination
                )
            }
            EntryInlineValidation(message: destinationError)
        }
        .padding(14)
        .ledgerSurface(.functional, cornerRadius: 24)
    }

    private func walletButton(
        title: String,
        wallet: CurrencyWallet?,
        action: @escaping () -> Void,
        currencyAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Button(action: action) {
                Text(wallet?.account?.name ?? AppLocalization.string("请选择"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: currencyAction) {
                HStack(spacing: 4) {
                    Text(wallet?.currencyCode ?? "--")
                        .font(.caption.monospaced())
                    if wallet?.account?.type == .creditCard {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 10)
        .background(LedgerPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
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

struct EntryMovementContextTags: View {
    @Binding var state: TransactionFormState
    let editDiscount: () -> Void
    let editFee: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if state.kind == .transfer {
                contextTag(
                    kind: nil,
                    title: amountTitle(
                        prefix: "优惠",
                        amountText: state.discountAmountText,
                        walletID: state.discountWalletID
                    ),
                    isSelected: DecimalParser.parse(state.discountAmountText).map { $0 > 0 } == true,
                    action: editDiscount
                )
            }
            contextTag(
                kind: .fee,
                title: amountTitle(
                    prefix: "手续费",
                    amountText: state.feeText,
                    walletID: state.feeWalletID
                ),
                isSelected: state.includesFee,
                action: editFee
            )
            Spacer(minLength: 0)
        }
    }

    private func contextTag(
        kind: EntryContextOverlayKind?,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isSelected ? LedgerPalette.accent : .secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .overlay {
                Capsule().stroke(
                    isSelected ? LedgerPalette.accent.opacity(0.55) : Color.primary.opacity(0.10),
                    lineWidth: 0.8
                )
            }
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityIdentifier(
            kind.map { "entry-context-tag-\($0.rawValue)" }
                ?? "entry-context-tag-secondary"
        )
        .background {
            if let kind {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: EntryContextTagFramePreferenceKey.self,
                        value: [
                            kind: proxy.frame(in: .named(EntryContextCoordinateSpace.name))
                        ]
                    )
                }
            }
        }
    }

    private func amountTitle(prefix: String, amountText: String, walletID: UUID?) -> String {
        guard let amount = DecimalParser.parse(amountText), amount > 0 else { return prefix }
        let walletMarker = walletID == nil ? " · 选账户" : ""
        return "\(prefix) \(EntryCalculationState.string(amount))\(walletMarker)"
    }
}
