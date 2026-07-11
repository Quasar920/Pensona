import SwiftUI

struct TransactionFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var range: TransactionDateRange
    @Binding var accountID: UUID?
    @Binding var currencyCode: String?
    @Binding var kind: TransactionKind?
    @Binding var categoryID: UUID?
    let accounts: [Account]
    let categories: [LedgerCategory]

    var body: some View {
        NavigationStack {
            Form {
                Picker("时间", selection: $range) {
                    ForEach(TransactionDateRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("账户", selection: $accountID) {
                    Text("全部账户").tag(nil as UUID?)
                    ForEach(accounts) { Text($0.name).tag($0.id as UUID?) }
                }
                Picker("币种", selection: $currencyCode) {
                    Text("全部币种").tag(nil as String?)
                    ForEach(SupportedCurrency.allCases) { Text($0.rawValue).tag($0.rawValue as String?) }
                }
                Picker("类型", selection: $kind) {
                    Text("全部类型").tag(nil as TransactionKind?)
                    ForEach(TransactionKind.allCases) { Text($0.title).tag($0 as TransactionKind?) }
                }
                Picker("分类", selection: $categoryID) {
                    Text("全部分类").tag(nil as UUID?)
                    ForEach(categories) { Text($0.name).tag($0.id as UUID?) }
                }
                Button("清除全部筛选", role: .destructive) {
                    range = .all
                    accountID = nil
                    currencyCode = nil
                    kind = nil
                    categoryID = nil
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}
