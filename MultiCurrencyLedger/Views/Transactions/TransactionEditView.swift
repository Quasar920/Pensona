import SwiftData
import SwiftUI

struct TransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let transaction: LedgerTransaction
    let onSaved: () -> Void
    @State private var amountText: String
    @State private var destinationAmountText: String
    @State private var feeText: String
    @State private var date: Date
    @State private var note: String
    @State private var errorMessage: String?

    init(transaction: LedgerTransaction, onSaved: @escaping () -> Void) {
        self.transaction = transaction
        self.onSaved = onSaved
        _amountText = State(initialValue: "\(transaction.sourceAmount ?? transaction.amount ?? 0)")
        _destinationAmountText = State(initialValue: "\(transaction.destinationAmount ?? 0)")
        _feeText = State(initialValue: transaction.feeAmount.map(String.init(describing:)) ?? "")
        _date = State(initialValue: transaction.date)
        _note = State(initialValue: transaction.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金额") {
                    TextField("金额", text: $amountText).keyboardType(.decimalPad)
                    if transaction.type == .exchange {
                        TextField("换入金额", text: $destinationAmountText).keyboardType(.decimalPad)
                    }
                    if transaction.type == .transfer || transaction.type == .exchange {
                        TextField("手续费（可选）", text: $feeText).keyboardType(.decimalPad)
                    }
                }
                Section("详情") {
                    DatePicker("日期", selection: $date)
                    TextField("备注", text: $note, axis: .vertical)
                }
                Section {
                    Text("保存时会先回滚原交易余额，再应用新金额。账户、币种、类型和分类保持不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑\(transaction.type.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        guard let amount = DecimalParser.parse(amountText), amount > 0 else {
            errorMessage = "请输入大于 0 的有效金额"
            return
        }
        let destinationAmount: Decimal?
        if transaction.type == .exchange {
            guard let parsed = DecimalParser.parse(destinationAmountText), parsed > 0 else {
                errorMessage = "请输入大于 0 的换入金额"
                return
            }
            destinationAmount = parsed
        } else if transaction.type == .transfer {
            destinationAmount = amount
        } else {
            destinationAmount = nil
        }
        let fee = feeText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : DecimalParser.parse(feeText)
        if let fee, fee <= 0 {
            errorMessage = "手续费必须大于 0"
            return
        }

        let replacement = LedgerTransaction(
            type: transaction.type,
            amount: transaction.type == .expense || transaction.type == .income || transaction.type == .adjustment ? amount : nil,
            currencyCode: transaction.currencyCode,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            sourceAccount: transaction.sourceAccount,
            sourceWallet: transaction.sourceWallet,
            destinationAccount: transaction.destinationAccount,
            destinationWallet: transaction.destinationWallet,
            sourceAmount: amount,
            sourceCurrencyCode: transaction.sourceCurrencyCode,
            destinationAmount: destinationAmount,
            destinationCurrencyCode: transaction.destinationCurrencyCode,
            feeAmount: fee,
            feeCurrencyCode: fee == nil ? nil : transaction.feeCurrencyCode,
            feeWallet: fee == nil ? nil : transaction.feeWallet,
            exchangeRate: transaction.type == .exchange ? destinationAmount! / amount : nil,
            adjustmentDirection: transaction.adjustmentDirection,
            adjustmentReason: transaction.adjustmentReason,
            category: transaction.category,
            createdAt: transaction.createdAt
        )

        do {
            try LedgerService(context: context).replaceTransaction(transaction, with: replacement)
            dismiss()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
