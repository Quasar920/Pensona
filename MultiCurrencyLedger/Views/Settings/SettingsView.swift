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
                    NavigationLink("快捷记账与识别") { QuickBookkeepingSettingsView() }
                }

                Section("分类与模板") {
                    NavigationLink("分类管理") { CategoryManagementView() }
                    NavigationLink("标签管理") { TagManagementView() }
                    NavigationLink("交易模板") { TransactionTemplateManagementView() }
                }

                Section("自动化与规划") {
                    NavigationLink("周期账单") { RecurringScheduleManagementView() }
                    NavigationLink("分期管理") { InstallmentPlanManagementView() }
                    NavigationLink("预算管理") { BudgetManagementView() }
                }

                Section("账户与汇率") {
                    NavigationLink("汇率管理") { ExchangeRateListView() }
                    NavigationLink("归档账户") { ArchivedAccountManagementView() }
                }

                Section("数据") {
                    NavigationLink("账单导入") { TransactionImportView() }
                    NavigationLink("数据导出与备份") { ExportView() }
                    NavigationLink("iCloud 私有同步") { CloudSyncSettingsView() }
                    Button("清空全部数据", role: .destructive) { showingClearConfirmation = true }
                }

                Section("安全与外观") {
                    NavigationLink("密码与隐私") { SecuritySettingsView() }
                    NavigationLink("启动与外观") { AppExperienceSettingsView() }
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
            for item in try context.fetch(FetchDescriptor<CloudSyncConflictCopy>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<CloudSyncTombstone>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionImportFingerprint>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionImportBatch>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<SavingsAllocation>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<SavingsGoal>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<RecurringOccurrence>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<InstallmentOccurrence>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<RecurringSchedule>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<InstallmentPlan>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionAttachment>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionRelation>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionTemplate>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<LedgerTransaction>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionPaymentPart>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<TransactionTag>()) { context.delete(item) }
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
                LabeledContent("版本", value: "1.0")
                LabeledContent("数据存储", value: "本机；可选 iCloud 私有同步")
            }
            Section {
                Text("一个金融账户可以拥有多个币种钱包。所有余额变化均由可追溯的统一流水驱动。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于 App")
    }
}
