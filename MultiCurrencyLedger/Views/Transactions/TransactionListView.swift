import SwiftData
import SwiftUI

struct TransactionListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query private var aaSettlements: [AASettlement]

    @State private var query: TransactionQueryState
    @State private var queryConfigured: Bool
    @State private var showingFilters = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedTransactionIDs = Set<UUID>()
    @State private var showingBulkEdit = false
    @State private var showingBulkDelete = false
    @State private var bulkErrorMessage: String?
    @State private var editingTransaction: LedgerTransaction?
    @State private var deletingTransaction: LedgerTransaction?

    init(initialQuery: TransactionQueryState? = nil) {
        _query = State(initialValue: initialQuery ?? TransactionQueryState())
        _queryConfigured = State(initialValue: initialQuery != nil)
    }

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var filtered: [LedgerTransaction] {
        query.applying(to: transactions)
    }

    private var grouped: [(Date, [LedgerTransaction])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return groups.sorted {
            query.sortOrder == .dateAscending ? $0.key < $1.key : $0.key > $1.key
        }
    }

    private var usesDayGrouping: Bool {
        query.sortOrder == .dateDescending || query.sortOrder == .dateAscending
    }

    private var hasFilters: Bool {
        query.hasActiveFilters || query.bookID != selectedBook?.id
    }

    private var selectedTransactions: [LedgerTransaction] {
        transactions.filter { selectedTransactionIDs.contains($0.id) }
    }

    private var aaRecoveryTransactionIDs: Set<UUID> {
        Set(aaSettlements.map(\.recoveryTransactionID))
    }

    private var filterSummary: String {
        var parts: [String] = []
        if query.bookID == nil {
            parts.append("全部账本")
        } else if query.bookID != selectedBook?.id,
                  let book = books.first(where: { $0.id == query.bookID }) {
            parts.append(book.name)
        }
        if query.dateFilter != .all { parts.append(query.dateFilter.title) }
        if query.minimumAmount != nil || query.maximumAmount != nil { parts.append("金额范围") }
        if let account = accounts.first(where: { $0.id == query.accountID }) { parts.append(account.name) }
        if let currencyCode = query.currencyCode { parts.append(currencyCode) }
        if let kind = query.kind { parts.append(kind.title) }
        if let category = categories.first(where: { $0.id == query.categoryID }) { parts.append(category.name) }
        if query.sortOrder != .dateDescending { parts.append(query.sortOrder.title) }
        return parts.isEmpty ? AppLocalization.string( "当前账本 · 全部时间") : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        hasFilters
                            ? AppLocalization.string("没有符合条件的明细")
                            : AppLocalization.string("暂无明细"),
                        systemImage: query.keyword.isEmpty ? "list.bullet.rectangle" : "magnifyingglass",
                        description: Text(
                            hasFilters
                                ? AppLocalization.string("当前条件：\(filterSummary)")
                                : AppLocalization.string("保存第一笔交易后会显示在这里。")
                        )
                    )
                } else {
                    List(selection: $selectedTransactionIDs) {
                        if hasFilters {
                            Section {
                                Button {
                                    showingFilters = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                        Text(filterSummary)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        Spacer()
                                        Text("\(filtered.count) 笔")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if usesDayGrouping {
                            ForEach(grouped, id: \.0) { day, items in
                                Section(day.formatted(.dateTime.year().month().day().weekday())) {
                                    transactionRows(items)
                                }
                            }
                        } else {
                            Section("排序结果 · \(filtered.count) 笔") {
                                transactionRows(filtered)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("明细")
            .searchable(text: $query.keyword, prompt: "搜索商户、备注、分类或账户")
            .navigationDestination(for: LedgerTransaction.self) {
                TransactionDetailView(transaction: $0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if editMode.isEditing, !selectedTransactionIDs.isEmpty {
                        Menu {
                            Button("批量修改") { showingBulkEdit = true }
                            Button("删除所选", role: .destructive) { showingBulkDelete = true }
                        } label: {
                            Label("批量操作", systemImage: "ellipsis.circle")
                        }
                    }
                    Button { showingFilters = true } label: {
                        Label(
                            "筛选",
                            systemImage: hasFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showingFilters) {
                TransactionFilterView(
                    query: query,
                    defaultBookID: selectedBook?.id,
                    books: books,
                    accounts: accounts,
                    categories: categories
                ) { updatedQuery in
                    query = updatedQuery
                }
            }
            .sheet(isPresented: $showingBulkEdit) {
                BulkTransactionEditView(
                    transactions: selectedTransactions,
                    categories: categories
                ) {
                    selectedTransactionIDs.removeAll()
                    editMode = .inactive
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionEditView(transaction: transaction) {}
            }
            .confirmationDialog(
                "删除所选 \(selectedTransactionIDs.count) 笔交易？",
                isPresented: $showingBulkDelete,
                titleVisibility: .visible
            ) {
                Button("删除并回滚全部余额", role: .destructive, action: deleteSelected)
                Button("取消", role: .cancel) {}
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
            .alert("批量操作失败", isPresented: Binding(
                get: { bulkErrorMessage != nil }, set: { if !$0 { bulkErrorMessage = nil } }
            )) { Button("好") {} } message: { Text(bulkErrorMessage ?? AppLocalization.string("未知错误")) }
            .onAppear(perform: configureQueryIfNeeded)
            .onChange(of: books.count) { _, _ in configureQueryIfNeeded() }
            .onChange(of: selectedBookID) { _, _ in
                guard queryConfigured else { return }
                query.bookID = selectedBook?.id
                query.accountID = nil
            }
        }
    }

    @ViewBuilder
    private func transactionRows(_ items: [LedgerTransaction]) -> some View {
        ForEach(items) { transaction in
            if editMode.isEditing {
                if aaRecoveryTransactionIDs.contains(transaction.id) {
                    TransactionCompactRow(transaction: transaction)
                } else {
                    TransactionCompactRow(transaction: transaction)
                        .tag(transaction.id)
                }
            } else {
                if aaRecoveryTransactionIDs.contains(transaction.id) {
                    NavigationLink(value: transaction) {
                        TransactionCompactRow(transaction: transaction)
                    }
                } else {
                    NavigationLink(value: transaction) {
                        TransactionCompactRow(transaction: transaction)
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

    private func configureQueryIfNeeded() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
        guard !queryConfigured else { return }
        query.bookID = selectedBook?.id
        queryConfigured = true
    }

    private func deleteSelected() {
        do {
            try BulkTransactionService(context: context).delete(selectedTransactions)
            selectedTransactionIDs.removeAll()
            editMode = .inactive
        } catch {
            bulkErrorMessage = error.localizedDescription
        }
    }

    private func deletePendingTransaction() {
        guard let transaction = deletingTransaction else { return }
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            deletingTransaction = nil
        } catch {
            bulkErrorMessage = error.localizedDescription
        }
    }
}

private struct BulkTransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let transactions: [LedgerTransaction]
    let categories: [LedgerCategory]
    let onSaved: () -> Void
    @State private var changesCategory = false
    @State private var categoryID: UUID?
    @State private var changesDate = false
    @State private var date = Date.now
    @State private var errorMessage: String?

    private var commonKind: TransactionKind? {
        guard let first = transactions.first?.type,
              transactions.allSatisfy({ $0.type == first }) else { return nil }
        return first
    }

    private var availableCategories: [LedgerCategory] {
        guard let commonKind, commonKind == .expense || commonKind == .income else { return [] }
        let type: CategoryKind = commonKind == .expense ? .expense : .income
        return categories.filter {
            !$0.isArchived && $0.type == type
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("已选") { Text("\(transactions.count) 笔交易") }
                Section("分类") {
                    Toggle("修改分类", isOn: $changesCategory)
                    if changesCategory {
                        Picker("分类", selection: $categoryID) {
                            Text("未分类").tag(nil as UUID?)
                            ForEach(availableCategories) { Text($0.name).tag($0.id as UUID?) }
                        }
                        .disabled(availableCategories.isEmpty)
                    }
                }
                Section("日期") {
                    Toggle("统一日期", isOn: $changesDate)
                    if changesDate { DatePicker("日期", selection: $date) }
                }
            }
            .navigationTitle("批量修改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        }
    }

    private func save() {
        do {
            try BulkTransactionService(context: context).update(
                transactions,
                changesCategory: changesCategory,
                category: categories.first { $0.id == categoryID },
                changesDate: changesDate,
                date: date
            )
            dismiss()
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
