import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let transaction: LedgerTransaction
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: transaction.type.symbolName)
                            .font(.largeTitle).foregroundStyle(transaction.type.color)
                        Text(transaction.summaryAmount)
                            .font(.title2.bold()).monospacedDigit()
                        Text(transaction.type.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical)
            }

            Section("交易信息") {
                LabeledContent("日期", value: transaction.date.formatted(date: .long, time: .shortened))
                if let category = transaction.category { LabeledContent("分类", value: category.name) }
                if let account = transaction.sourceAccount { LabeledContent("来源账户", value: account.name) }
                if let code = transaction.sourceCurrencyCode { LabeledContent("来源币种", value: code) }
                if let account = transaction.destinationAccount { LabeledContent("目标账户", value: account.name) }
                if let code = transaction.destinationCurrencyCode { LabeledContent("目标币种", value: code) }
                if let rate = transaction.exchangeRate { LabeledContent("实际汇率", value: "\(rate)") }
                if let fee = transaction.feeAmount, fee > 0 {
                    LabeledContent("手续费", value: "\(MoneyFormatter.plain(fee, currencyCode: transaction.feeCurrencyCode ?? "CNY")) \(transaction.feeCurrencyCode ?? "")")
                }
                if let reason = transaction.adjustmentReason { LabeledContent("调整原因", value: reason) }
                if let note = transaction.note, !note.isEmpty { LabeledContent("备注", value: note) }
            }

            Section {
                Button("编辑") { showingEdit = true }
                Button("删除交易", role: .destructive) { showingDelete = true }
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            TransactionEditView(transaction: transaction) { dismiss() }
        }
        .confirmationDialog("确定删除这笔交易？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除并回滚余额", role: .destructive, action: deleteTransaction)
            Button("取消", role: .cancel) {}
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func deleteTransaction() {
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
