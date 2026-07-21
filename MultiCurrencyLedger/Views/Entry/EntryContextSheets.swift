import SwiftUI

struct EntryAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let wallets: [CurrencyWallet]
    let selectedID: UUID?
    let select: (CurrencyWallet) -> Void
    @State private var searchText = ""

    private var filtered: [CurrencyWallet] {
        guard !searchText.isEmpty else { return wallets }
        return wallets.filter {
            ($0.account?.name ?? "").localizedCaseInsensitiveContains(searchText)
                || $0.currencyCode.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(filtered) { wallet in
                        Button {
                            select(wallet)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: wallet.account?.type.symbolName ?? "creditcard")
                                    .font(.headline).foregroundStyle(LedgerPalette.accent)
                                    .frame(width: 36, height: 36)
                                    .background(LedgerPalette.accent.opacity(0.10), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(wallet.account?.name ?? AppLocalization.string("未知账户"))
                                        .font(.headline)
                                    Text("\(wallet.currencyCode) · \(MoneyFormatter.plain(wallet.balance, currencyCode: wallet.currencyCode))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedID == wallet.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LedgerPalette.accent)
                                }
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .ledgerSurface(.functional, cornerRadius: 20)
                    }
                }
                .padding(18)
            }
            .ledgerPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索账户或币种")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct EntryDateTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @State private var draftDate: Date

    init(date: Binding<Date>) {
        _date = date
        _draftDate = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("日期与时间", selection: $draftDate)
                    .datePickerStyle(.compact)
                    .padding(18)
                    .ledgerSurface(.sheetChrome, cornerRadius: 22)
                Button("回到现在") { draftDate = .now }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding(18)
            .ledgerPageBackground()
            .navigationTitle("选择日期与时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { date = draftDate; dismiss() }
                }
            }
        }
    }
}

struct EntrySupplementarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if state.kind != .adjustment {
                        fieldCard(title: state.kind == .expense || state.kind == .income ? "商户或交易对方" : "交易对方") {
                            TextField("可选", text: $state.merchantOrCounterparty)
                                .textFieldStyle(.plain)
                        }
                    }
                    if state.kind == .expense || state.kind == .income {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(state.kind == .expense ? "组合付款" : "多账户收款", isOn: Binding(
                                get: { state.usesSplitPayment },
                                set: { state.setSplitPaymentEnabled($0, wallets: wallets) }
                            ))
                            if state.usesSplitPayment {
                                ForEach(Array(state.paymentParts.indices), id: \.self) { index in
                                    HStack {
                                        Picker("账户", selection: $state.paymentParts[index].walletID) {
                                            ForEach(wallets) { wallet in
                                                Text(wallet.account?.name ?? wallet.currencyCode).tag(wallet.id as UUID?)
                                            }
                                        }
                                        TextField("金额", text: $state.paymentParts[index].amountText)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .ledgerSurface(.functional, cornerRadius: 20)
                    }
                    if state.kind == .transfer || state.kind == .exchange, state.includesFee {
                        fieldCard(title: "手续费扣款账户") {
                            Picker("账户", selection: $state.feeWalletID) {
                                ForEach(wallets) { wallet in
                                    Text(wallet.account?.name ?? wallet.currencyCode).tag(wallet.id as UUID?)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .ledgerPageBackground()
            .navigationTitle("更多信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func fieldCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .ledgerSurface(.functional, cornerRadius: 20)
    }
}
