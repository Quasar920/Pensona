import SwiftUI

struct EntryContextControls: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let validation: EntryValidationState
    let selectAccount: () -> Void
    let editSplitPayment: () -> Void
    let editAA: () -> Void
    let editDiscount: () -> Void
    let selectNeutralAdjustment: (AdjustmentDirection) -> Void

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { proxy in
                let cardSide = min(64, max(56, (proxy.size.width - 32) / 5))
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        control(
                            title: sourceWallet?.account?.name ?? AppLocalization.string("账户"),
                            symbol: "creditcard",
                            side: cardSide,
                            action: selectAccount
                        )
                        if state.kind == .expense {
                            control(
                                title: state.reimbursementStatus == .pending ? "待报销" : "报销",
                                symbol: state.reimbursementStatus == .pending ? "checkmark.circle.fill" : "circle",
                                side: cardSide,
                                isSelected: state.reimbursementStatus == .pending
                            ) {
                                state.reimbursementStatus = state.reimbursementStatus == .pending ? .none : .pending
                            }
                        }
                        if state.kind == .expense {
                            control(
                                title: state.aaSplitDraft.map { "共 \($0.otherPeopleCount + 1) 人" } ?? "AA",
                                symbol: "person.2.fill",
                                side: cardSide,
                                action: editAA
                            )
                        }
                        if state.kind == .expense || state.kind == .income {
                            control(
                                title: "组合支付",
                                symbol: "square.grid.2x2",
                                side: cardSide,
                                isSelected: state.usesSplitPayment,
                                action: editSplitPayment
                            )
                            control(
                                title: "优惠",
                                symbol: "tag",
                                side: cardSide,
                                isSelected: DecimalParser.parse(state.discountAmountText).map { $0 > 0 } == true,
                                action: editDiscount
                            )
                        }
                        control(
                            title: "不计收",
                            symbol: "arrow.down.left.circle",
                            side: cardSide
                        ) {
                            selectNeutralAdjustment(.increase)
                        }
                        control(
                            title: "不计支",
                            symbol: "arrow.up.right.circle",
                            side: cardSide
                        ) {
                            selectNeutralAdjustment(.decrease)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            }
            .frame(height: 64)
            EntryInlineValidation(message: validation[.sourceWallet])
        }
    }

    private func control(
        title: String,
        symbol: String,
        side: CGFloat,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 20)
            }
            .foregroundStyle(isSelected ? LedgerPalette.accent : .primary)
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
        .ledgerSurface(.functional, cornerRadius: 16)
        .accessibilityLabel(title)
    }
}
