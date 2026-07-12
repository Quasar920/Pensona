import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("记账设置") {
                    Picker("本位币", selection: $baseCurrencyCode) {
                        ForEach(SupportedCurrency.allCases) {
                            Text("\($0.rawValue) · \($0.localizedName)").tag($0.rawValue)
                        }
                    }
                    NavigationLink("汇率管理") { ExchangeRateListView() }
                    NavigationLink("分类管理") { CategoryManagementView() }
                    NavigationLink("快捷记账") { QuickBookkeepingSettingsView() }
                }

                Section("数据") {
                    NavigationLink("数据导出与备份") { ExportView() }
                    Button("清空全部数据", role: .destructive) { showingClearConfirmation = true }
                }

                Section {
                    NavigationLink("关于 App") { AboutView() }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "清空全部数据？",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("永久清空", role: .destructive, action: clearAllData)
                Button("取消", role: .cancel) {}
            } message: {
                Text("账户、钱包、交易、月度预算、汇率和自定义分类都将删除，此操作不可撤销。")
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func clearAllData() {
        do {
            for item in try context.fetch(FetchDescriptor<LedgerTransaction>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<MonthlyBudget>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<CurrencyWallet>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<Account>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<LedgerBook>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<ExchangeRate>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<LedgerCategory>()) { context.delete(item) }
            try context.save()
            try InitialDataService.seedIfNeeded(context: context)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("名称", value: "多币种账本")
                LabeledContent("版本", value: "1.0 MVP")
                LabeledContent("数据存储", value: "仅保存在本机")
            }
            Section {
                Text("一个金融账户可以拥有多个币种钱包。所有余额变化均由可追溯的统一流水驱动。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于 App")
    }
}
