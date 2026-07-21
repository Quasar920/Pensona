import SwiftUI

struct EntryContextControls: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let validation: EntryValidationState
    let selectAccount: () -> Void
    let selectDate: () -> Void
    let editAA: () -> Void
    let showSupplementary: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                control(
                    title: sourceWallet?.account?.name ?? AppLocalization.string("账户"),
                    symbol: "creditcard",
                    action: selectAccount
                )
                if state.kind == .expense {
                    control(
                        title: state.reimbursementStatus == .pending ? "待报销" : "报销",
                        symbol: state.reimbursementStatus == .pending ? "checkmark.circle.fill" : "circle",
                        isSelected: state.reimbursementStatus == .pending
                    ) {
                        state.reimbursementStatus = state.reimbursementStatus == .pending ? .none : .pending
                    }
                }
                control(
                    title: state.date.formatted(.dateTime.month().day().hour().minute()),
                    symbol: "calendar",
                    action: selectDate
                )
                if state.kind == .expense {
                    control(
                        title: state.aaSplitDraft.map { "共 \($0.otherPeopleCount + 1) 人" } ?? "AA",
                        symbol: "person.2.fill",
                        action: editAA
                    )
                }
                control(title: "更多", symbol: "ellipsis", action: showSupplementary)
            }
            EntryInlineValidation(message: validation[.sourceWallet])
        }
    }

    private func control(
        title: String,
        symbol: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
                Text(title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? LedgerPalette.accent : .primary)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .ledgerSurface(.functional, cornerRadius: 17)
    }
}
