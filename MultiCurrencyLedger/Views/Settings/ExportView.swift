import SwiftData
import SwiftUI

struct ExportView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @Query private var accounts: [Account]
    @Query private var wallets: [CurrencyWallet]
    @Query private var transactions: [LedgerTransaction]
    @Query private var categories: [LedgerCategory]
    @Query private var rates: [ExchangeRate]
    @Query private var budgets: [MonthlyBudget]
    @State private var jsonURL: URL?
    @State private var csvURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("JSON 完整备份", systemImage: "curlybraces")
                        .font(.headline)
                    Text("包含账户、钱包、交易、月度预算、分类、汇率和 App 设置，可供未来导入功能使用。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let jsonURL {
                        ShareLink(item: jsonURL) {
                            Label("分享 JSON 备份", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("生成 JSON 备份", action: prepareJSON)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("CSV 交易明细", systemImage: "tablecells")
                        .font(.headline)
                    Text("按日期导出全部流水，使用 UTF-8 编码并兼容常见表格软件。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("分享 CSV 流水", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("生成 CSV 流水", action: prepareCSV)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("数据导出")
        .alert("导出失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func prepareJSON() {
        do {
            jsonURL = try ExportService.makeJSONBackup(
                accounts: accounts,
                wallets: wallets,
                transactions: transactions,
                categories: categories,
                rates: rates,
                budgets: budgets,
                baseCurrencyCode: baseCurrencyCode
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCSV() {
        do {
            csvURL = try ExportService.makeCSV(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
