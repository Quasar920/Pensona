import SwiftData
import SwiftUI

struct MonthTransactionListView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerTransaction.date, order: .reverse)
    private var transactions: [LedgerTransaction]

    let bookID: UUID?
    let bookName: String
    let month: Date

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
                                NavigationLink(value: transaction) {
                                    HomeTransactionRow(transaction: transaction)
                                        .padding(.horizontal, -1)
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
    }
}
