import SwiftUI

struct TransactionFormSections: View {
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]

    private let adjustmentReasons = ["银行利息", "投资收益", "投资亏损", "手动校准", "其他"]

    private var sourceWallet: CurrencyWallet? {
        wallets.first { $0.id == state.sourceWalletID }
    }

    private var destinationWallet: CurrencyWallet? {
        wallets.first { $0.id == state.destinationWalletID }
    }

    private var feeWallet: CurrencyWallet? {
        wallets.first { $0.id == state.feeWalletID }
    }

    private var filteredCategories: [LedgerCategory] {
        let categoryKind: CategoryKind = state.kind == .income ? .income : .expense
        return categories.filter { $0.type == categoryKind }
    }

    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter { candidate in
            guard candidate.id != sourceWallet.id else { return false }
            switch state.kind {
            case .transfer:
                return candidate.currencyCode == sourceWallet.currencyCode
            case .exchange:
                return candidate.currencyCode != sourceWallet.currencyCode
            default:
                return false
            }
        }
    }

    var body: some View {
        Picker("类型", selection: $state.kind) {
            ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        amountSection
        walletSection
        detailSection
    }

    private var amountSection: some View {
        Section(state.kind == .exchange ? "换出金额" : "金额") {
            HStack(alignment: .firstTextBaseline) {
                Text(sourceWallet?.currencyCode ?? "--")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $state.amountText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if state.kind == .exchange {
                HStack {
                    Text(destinationWallet?.currencyCode ?? "目标币种")
                        .foregroundStyle(.secondary)
                    TextField("换入金额", text: $state.destinationAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var walletSection: some View {
        Section("账户与币种") {
            Picker(state.kind == .transfer || state.kind == .exchange ? "从" : "钱包", selection: $state.sourceWalletID) {
                ForEach(wallets) { wallet in
                    Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                }
            }

            if state.kind == .transfer || state.kind == .exchange {
                Picker("到", selection: $state.destinationWalletID) {
                    ForEach(destinationOptions) { wallet in
                        Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                    }
                }

                Toggle("包含手续费", isOn: $state.includesFee)
                if state.includesFee {
                    Picker("手续费钱包", selection: $state.feeWalletID) {
                        ForEach(wallets) { wallet in
                            Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                        }
                    }
                    HStack {
                        Text(feeWallet?.currencyCode ?? "--")
                            .foregroundStyle(.secondary)
                        TextField("手续费", text: $state.feeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("手续费会从所选钱包单独扣除。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        Section("详情") {
            if state.kind == .expense || state.kind == .income {
                Picker("分类", selection: $state.categoryID) {
                    Text("未分类").tag(nil as UUID?)
                    ForEach(filteredCategories) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(category.id as UUID?)
                    }
                }
                TextField("商户或交易对方（可选）", text: $state.merchantOrCounterparty)
            } else if state.kind == .transfer || state.kind == .exchange {
                TextField("交易对方（可选）", text: $state.merchantOrCounterparty)
            }

            if state.kind == .adjustment {
                Picker("方向", selection: $state.adjustmentDirection) {
                    ForEach(AdjustmentDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("原因", selection: $state.adjustmentReason) {
                    ForEach(adjustmentReasons, id: \.self) { Text($0).tag($0) }
                }
            }

            DatePicker("日期", selection: $state.date)
            TextField("备注（可选）", text: $state.note, axis: .vertical)
        }
    }

    private func walletLabel(_ wallet: CurrencyWallet) -> String {
        let balance = MoneyFormatter.plain(wallet.balance, currencyCode: wallet.currencyCode)
        return "\(wallet.account?.name ?? "未知账户") / \(wallet.currencyCode) / \(balance)"
    }
}
