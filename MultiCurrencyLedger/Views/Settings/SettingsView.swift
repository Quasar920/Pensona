import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        SettingsGroupCard(title: "数据导入与导出", symbol: "arrow.up.arrow.down.circle.fill") {
                            SettingsDestinationRow(title: "账单导入", symbol: "square.and.arrow.down") {
                                TransactionImportView()
                            }
                            SettingsDestinationRow(title: "备份与导出", symbol: "square.and.arrow.up") {
                                ExportView()
                            }
                        }
                        SettingsGroupCard(title: "安全与隐私", symbol: "lock.shield.fill") {
                            SettingsDestinationRow(title: "密码、解锁与隐私遮罩", symbol: "faceid") {
                                SecuritySettingsView()
                            }
                        }
                        SettingsGroupCard(title: "外观与金额颜色", symbol: "paintpalette.fill") {
                            SettingsDestinationRow(title: "显示、触觉与金额颜色", symbol: "circle.lefthalf.filled") {
                                AppearanceAndAmountSettingsView()
                            }
                        }
                        SettingsGroupCard(title: "币种与汇率", symbol: "yensign.bank.building.fill") {
                            SettingsDestinationRow(title: "本位币与汇率管理", symbol: "arrow.triangle.2.circlepath") {
                                CurrencyAndRatesSettingsView()
                            }
                        }
                        SettingsGroupCard(title: "数据恢复与迁移", symbol: "externaldrive.badge.timemachine") {
                            SettingsDestinationRow(title: "备份恢复、迁移快照与清除", symbol: "lifepreserver.fill") {
                                DataRecoverySettingsView(clearAllData: clearAllData)
                            }
                        }
                        SettingsGroupCard(title: "语言", symbol: "character.bubble.fill") {
                            SettingsDestinationRow(title: "App 显示语言", symbol: "globe") {
                                LanguageSettingsView()
                            }
                        }
                        SettingsGroupCard(title: "关于与帮助", symbol: "info.circle.fill") {
                            SettingsDestinationRow(title: "关于 App 与数据说明", symbol: "questionmark.circle") {
                                AboutView()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("设置")
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
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
            for item in try context.fetch(FetchDescriptor<RepaymentReminder>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<AASettlement>()) { context.delete(item) }
            for item in try context.fetch(FetchDescriptor<AASplit>()) { context.delete(item) }
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
            AccountCardIdentityStore().removeAll()
            try InitialDataService.seedIfNeeded(context: context)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

private struct SettingsGroupCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(HomePalette.accent)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            content
        }
        .padding(.bottom, 6)
        .ledgerGlassCard(cornerRadius: 24, tint: HomePalette.accent)
    }
}

private struct SettingsDestinationRow<Destination: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let destination: Destination

    init(
        title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.symbol = symbol
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .frame(minHeight: 48)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(LedgerGlassPressStyle())
    }
}

private struct CurrencyAndRatesSettingsView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue

    var body: some View {
        List {
            Section("本位币") {
                Picker("本位币", selection: $baseCurrencyCode) {
                    ForEach(SupportedCurrency.allCases) {
                        Text("\($0.rawValue) · \($0.localizedName)").tag($0.rawValue)
                    }
                }
            }
            Section {
                NavigationLink("汇率管理") { ExchangeRateListView() }
            }
        }
        .navigationTitle("币种与汇率")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataRecoverySettingsView: View {
    let clearAllData: () -> Void
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            Section {
                NavigationLink("校验并恢复 JSON 备份") { ExportView() }
                NavigationLink("Schema 迁移快照") { MigrationRecoveryView() }
            }
            Section {
                Text("危险操作只影响本机数据，执行前请先导出完整备份。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("清空全部数据", role: .destructive) { showingClearConfirmation = true }
            } header: {
                Text("危险操作")
            }
        }
        .navigationTitle("数据恢复与迁移")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("清空全部数据？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("永久清空", role: .destructive, action: clearAllData)
            Button("取消", role: .cancel) {}
        } message: {
            Text("账户、钱包、交易、计划、汇率和自定义分类都将删除，此操作不可撤销。")
        }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("名称", value: AppLocalization.string("多币种账本"))
                LabeledContent("版本", value: "1.0")
                LabeledContent("数据存储", value: AppLocalization.string("本机；可选 iCloud 私有同步"))
            }
            Section {
                Text("一个金融账户可以拥有多个币种钱包。所有余额变化均由可追溯的统一流水驱动。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于与帮助")
        .navigationBarTitleDisplayMode(.inline)
    }
}
