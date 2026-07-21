import SwiftUI

struct EntryAdjustmentPanel: View {
    @Binding var state: TransactionFormState
    let wallet: CurrencyWallet?
    private let reasons = ["银行利息", "投资收益", "投资亏损", "手动校准", "其他"]

    private var entered: Decimal { DecimalParser.parse(state.amountText) ?? 0 }
    private var before: Decimal { wallet?.balance ?? 0 }
    private var change: Decimal {
        if state.adjustmentInputMode == .finalBalance { return entered - before }
        return state.adjustmentDirection == .increase ? entered : -entered
    }
    private var after: Decimal {
        state.adjustmentInputMode == .finalBalance ? entered : before + change
    }
    private var currencyCode: String { wallet?.currencyCode ?? SupportedCurrency.CNY.rawValue }

    var body: some View {
        VStack(spacing: 12) {
            Picker("调整方式", selection: $state.adjustmentInputMode) {
                ForEach(AdjustmentInputMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if state.adjustmentInputMode == .delta {
                Picker("方向", selection: $state.adjustmentDirection) {
                    ForEach(AdjustmentDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                amountSummary("调整前", before)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                amountSummary("变化", change)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                amountSummary("调整后", after)
            }

            Picker("原因", selection: $state.adjustmentReason) {
                ForEach(reasons, id: \.self) { Text($0).tag($0) }
            }
        }
        .padding(14)
        .ledgerSurface(.functional, cornerRadius: 24)
    }

    private func amountSummary(_ title: String, _ amount: Decimal) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(MoneyFormatter.plain(amount, currencyCode: currencyCode))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}
