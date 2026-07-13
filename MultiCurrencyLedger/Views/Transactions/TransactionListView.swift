import SwiftData
import SwiftUI

struct TransactionListView: View {
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var query = TransactionQueryState()
    @State private var queryConfigured = false
    @State private var showingFilters = false

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
        return parts.isEmpty ? "当前账本 · 全部时间" : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        hasFilters ? "没有符合条件的明细" : "暂无明细",
                        systemImage: query.keyword.isEmpty ? "list.bullet.rectangle" : "magnifyingglass",
                        description: Text(hasFilters ? "当前条件：\(filterSummary)" : "保存第一笔交易后会显示在这里。")
                    )
                } else {
                    List {
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
                Button { showingFilters = true } label: {
                    Label(
                        "筛选",
                        systemImage: hasFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
            }
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
            NavigationLink(value: transaction) {
                TransactionCompactRow(transaction: transaction)
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
}
