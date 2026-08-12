import SwiftData
import SwiftUI

struct MonthTransactionListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue

    let bookID: UUID?
    let bookName: String
    let month: Date
    @State private var editingTransaction: LedgerTransaction?
    @State private var deletingTransaction: LedgerTransaction?
    @State private var errorMessage: String?
    @State private var snapshot: BillPageSnapshot?
    @State private var refreshGeneration = 0

    private var filtered: [LedgerTransaction] {
        snapshot?.transactions ?? []
    }

    private var groups: [BillDayGroup] {
        snapshot?.dayGroups ?? []
    }

    private var aaRecoveryTransactionIDs: Set<UUID> {
        []
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("当月没有记录", systemImage: "calendar")
                } description: {
                    Text("\(bookName) 在 \(month.yearMonthText(locale: locale)) 还没有收支记录。")
                }
            } else {
                List {
                    Section {
                        LabeledContent("账本", value: bookName)
                        LabeledContent("记录数", value: "\(filtered.count) 笔")
                    }

                    ForEach(groups) { group in
                        Section(group.date.dayHeading(locale: locale)) {
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
                                        .tint(LedgerPalette.ink)
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
        .navigationTitle("\(month.yearMonthText(locale: locale)) · 全部记录")
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
            Text(errorMessage ?? AppLocalization.string("未知错误"))
        }
        .task(id: refreshGeneration) { load() }
        .onReceive(NotificationCenter.default.publisher(for: .ledgerTransactionsDidChange)) { _ in
            refreshGeneration += 1
        }
    }

    private func deletePendingTransaction() {
        guard let transaction = deletingTransaction else { return }
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            deletingTransaction = nil
            refreshGeneration += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() {
        guard let bookID else {
            snapshot = nil
            return
        }
        do {
            snapshot = try BillQueryService(context: context).load(
                bookID: bookID,
                month: month,
                baseCurrencyCode: baseCurrencyCode
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
