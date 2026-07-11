import SwiftData
import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let account: Account
    @State private var currency: SupportedCurrency = .CNY
    @State private var initialBalance = ""
    @State private var errorMessage: String?

    private var availableCurrencies: [SupportedCurrency] {
        SupportedCurrency.allCases.filter { currency in
            !account.wallets.contains { $0.currencyCode == currency.rawValue }
        }
    }

    private var isLiabilityAccount: Bool { account.type.isLiability }

    var body: some View {
        NavigationStack {
            Form {
                if availableCurrencies.isEmpty {
                    ContentUnavailableView("已添加全部币种", systemImage: "checkmark.circle")
                } else {
                    Picker("币种", selection: $currency) {
                        ForEach(availableCurrencies) { item in
                            Text("\(item.rawValue) · \(item.localizedName)").tag(item)
                        }
                    }
                    TextField(
                        isLiabilityAccount ? "初始欠款（默认 0）" : "初始余额（默认 0）",
                        text: $initialBalance
                    )
                    .keyboardType(.decimalPad)
                    Text(isLiabilityAccount
                         ? "输入正数即可，初始欠款会记为负余额，并写入一条“调整”流水。"
                         : "初始余额会写入一条“调整”流水，便于以后追溯。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加币种")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let first = availableCurrencies.first { currency = first }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(availableCurrencies.isEmpty)
                }
            }
            .alert("无法添加币种", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        let amount: Decimal
        if initialBalance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            amount = 0
        } else if let parsed = DecimalParser.parse(initialBalance), parsed >= 0 {
            amount = parsed
        } else {
            errorMessage = isLiabilityAccount
                ? "请输入有效且不小于 0 的初始欠款"
                : "请输入有效且不小于 0 的初始余额"
            return
        }

        do {
            _ = try AccountService(context: context).addWallet(
                currency: currency,
                initialBalance: amount,
                to: account
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
