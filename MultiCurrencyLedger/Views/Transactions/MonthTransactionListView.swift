import SwiftData
import SwiftUI

struct MonthTransactionListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerTransaction.date, order: .reverse)
    private var transactions: [LedgerTransaction]
    @Query private var aaSettlements: [AASettlement]

    let bookID: UUID?
    let bookName: String
    let month: Date
    @State private var editingTransaction: LedgerTransaction?
    @State private var deletingTransaction: LedgerTransaction?
    @State private var errorMessage: String?

    private var filtered: [LedgerTransaction] {
        guard let bookID else { return [] }
        return transactions.filter {
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
                && ($0.sourceAccount?.book?.id == bookID || $0.destinationAccount?.book?.id == bookID)
        }
    }

    private var groups: [TransactionDayGroup] {
        TransactionDayGroup.make(from: filtered)
    }

    private var aaRecoveryTransactionIDs: Set<UUID> {
        Set(aaSettlements.map(\.recoveryTransactionID))
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("当月没有记录", systemImage: "calendar")
                } description: {
                    Text("\(bookName) 在 \(month.chineseYearMonth) 还没有收支记录。")
                }
            } else {
                List {
                    Section {
                        LabeledContent("账本", value: bookName)
                        LabeledContent("记录数", value: "\(filtered.count) 笔")
                    }

                    ForEach(groups) { group in
                        Section(group.date.homeDayHeading) {
                            ForEach(group.transactions) { transaction in
                                if aaRecoveryTransactionIDs.contains(transaction.id) {
                                    NavigationLink(value: transaction) {
                                        HomeTransactionRow(transaction: transaction)
                                            .padding(.horizontal, -1)
                                    }
                                } else {
                                    NavigationLink(value: transaction) {
                                        HomeTransactionRow(transaction: transaction)
                                            .padding(.horizontal, -1)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            editingTransaction = transaction
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            deletingTransaction = transaction
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("\(month.chineseYearMonth) · 全部记录")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label("返回", systemImage: "chevron.left")
                }
            }
        }
        .navigationDestination(for: LedgerTransaction.self) {
            TransactionDetailView(transaction: $0)
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditView(transaction: transaction) {}
        }
        .confirmationDialog(
            "确定删除这笔交易？",
            isPresented: Binding(
                get: { deletingTransaction != nil },
                set: { if !$0 { deletingTransaction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除并回滚余额", role: .destructive, action: deletePendingTransaction)
            Button("取消", role: .cancel) { deletingTransaction = nil }
        } message: {
            Text("删除后，相关账户余额会同步回滚。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func deletePendingTransaction() {
        guard let transaction = deletingTransaction else { return }
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            deletingTransaction = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
