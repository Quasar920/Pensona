import SwiftData
import SwiftUI

struct TransactionListView: View {
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var range: TransactionDateRange = .all
    @State private var accountID: UUID?
    @State private var currencyCode: String?
    @State private var kind: TransactionKind?
    @State private var categoryID: UUID?
    @State private var showingFilters = false

    private var filtered: [LedgerTransaction] {
        transactions.filter { transaction in
            range.contains(transaction.date)
            && (accountID == nil || transaction.sourceAccount?.id == accountID || transaction.destinationAccount?.id == accountID)
            && (currencyCode == nil || transaction.sourceCurrencyCode == currencyCode || transaction.destinationCurrencyCode == currencyCode)
            && (kind == nil || transaction.type == kind)
            && (categoryID == nil || transaction.category?.id == categoryID)
        }
    }

    private var grouped: [(Date, [LedgerTransaction])] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
    }

    private var hasFilters: Bool {
        range != .all || accountID != nil || currencyCode != nil || kind != nil || categoryID != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        hasFilters ? "没有符合条件的明细" : "暂无明细",
                        systemImage: "list.bullet.rectangle",
                        description: Text(hasFilters ? "请调整筛选条件。" : "保存第一笔交易后会显示在这里。")
                    )
                } else {
                    List {
                        ForEach(grouped, id: \.0) { day, items in
                            Section(day.formatted(.dateTime.year().month().day().weekday())) {
                                ForEach(items) { transaction in
                                    NavigationLink(value: transaction) {
                                        TransactionCompactRow(transaction: transaction)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("明细")
            .navigationDestination(for: LedgerTransaction.self) {
                TransactionDetailView(transaction: $0)
            }
            .toolbar {
                Button { showingFilters = true } label: {
                    Label("筛选", systemImage: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            .sheet(isPresented: $showingFilters) {
                TransactionFilterView(
                    range: $range,
                    accountID: $accountID,
                    currencyCode: $currencyCode,
                    kind: $kind,
                    categoryID: $categoryID,
                    accounts: accounts,
                    categories: categories
                )
            }
        }
    }
}

enum TransactionDateRange: String, CaseIterable, Identifiable {
    case all, thisMonth, last30Days, thisYear
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部时间"
        case .thisMonth: "本月"
        case .last30Days: "最近 30 天"
        case .thisYear: "今年"
        }
    }
    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return switch self {
        case .all: true
        case .thisMonth: calendar.isDate(date, equalTo: .now, toGranularity: .month)
        case .last30Days: date >= calendar.date(byAdding: .day, value: -30, to: .now)!
        case .thisYear: calendar.isDate(date, equalTo: .now, toGranularity: .year)
        }
    }
}
