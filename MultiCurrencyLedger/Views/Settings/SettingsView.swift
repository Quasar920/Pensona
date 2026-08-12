import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            ZStack {
                LedgerPageBackground()

                List {
                    Section {
                        SettingsDestinationRow(
                            title: "账单导入",
                            subtitle: "从表格或文件导入历史账单",
                            symbol: "square.and.arrow.down"
                        ) {
                            TransactionImportView()
                        }
                        SettingsDestinationRow(
                            title: "备份与导出",
                            subtitle: "导出账单并管理完整备份",
                            symbol: "square.and.arrow.up"
                        ) {
                            ExportView()
                        }
                    } header: {
                        SettingsSectionHeader("数据导入与导出")
                    }

                    Section {
                        SettingsDestinationRow(
                            title: "密码、解锁与隐私遮罩",
                            subtitle: "保护本机数据和后台预览",
                            symbol: "faceid"
                        ) {
                            SecuritySettingsView()
                        }
                    } header: {
                        SettingsSectionHeader("安全与隐私")
                    }

                    Section {
                        SettingsDestinationRow(
                            title: "显示、触觉与金额颜色",
                            subtitle: "选择主题、触觉反馈和收支配色",
                            symbol: "circle.lefthalf.filled"
                        ) {
                            AppearanceAndAmountSettingsView()
                        }
                    } header: {
                        SettingsSectionHeader("外观与金额颜色")
                    }

                    Section {
                        SettingsDestinationRow(
                            title: "本位币与汇率管理",
                            subtitle: "设置本位币并管理换算汇率",
                            symbol: "arrow.triangle.2.circlepath"
                        ) {
                            CurrencyAndRatesSettingsView()
                        }
                    } header: {
                        SettingsSectionHeader("币种与汇率")
                    }

                    Section {
                        SettingsDestinationRow(
                            title: "备份恢复、迁移快照与清除",
                            subtitle: "校验备份、迁移快照或清空数据",
                            symbol: "lifepreserver.fill"
                        ) {
                            DataRecoverySettingsView(clearAllData: clearAllData)
                        }
                    } header: {
                        SettingsSectionHeader("数据恢复与迁移")
                    }

                    Section {
                        SettingsDestinationRow(
                            title: "App 显示语言",
                            subtitle: "选择 App 的显示语言",
                            symbol: "globe"
                        ) {
                            LanguageSettingsView()
                        }
                    } header: {
                        SettingsSectionHeader("语言")
                    }

                    Section {
                        Button {
                            showingAbout = true
                        } label: {
                            SettingsAboutFooter()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-about-footer")
                        .listRowInsets(EdgeInsets(top: 22, leading: 16, bottom: 42, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(22)
                .scrollContentBackground(.hidden)
                .listRowBackground(SettingsSurfacePalette.rowBackground)
                .listRowSeparatorTint(LedgerPalette.separator)
                .contentMargins(.top, 6, for: .scrollContent)
            }
            .navigationTitle("设置")
            .navigationDestination(isPresented: $showingAbout) {
                AboutView()
            }
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

private enum SettingsSurfacePalette {
    static let rowBackground = Color(uiColor: .secondarySystemBackground).opacity(0.78)
}

private struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

private struct SettingsDestinationRow<Destination: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    @ViewBuilder let destination: Destination

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LedgerGlassPressStyle())
    }
}

private struct SettingsAboutFooter: View {
    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "OneTsu"
    }

    private var version: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 27, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HomePalette.accent)
                .frame(width: 64, height: 64)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(HomePalette.glassBorder, lineWidth: 0.75)
                }
                .padding(.bottom, 5)

            Text(displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 0) {
                Text("版本")
                Text(verbatim: " \(version)")
            }

            if AppCapabilities.current.cloudSync {
                Text("本机；可选 iCloud 私有同步")
                    .padding(.top, 4)
            } else {
                Text("storage.onDeviceOnly")
                    .padding(.top, 4)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("关于 App 与数据说明")
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
                LabeledContent("名称") {
                    Text(verbatim: "OneTsu")
                }
                LabeledContent("版本", value: "1.0")
                LabeledContent("数据存储") {
                    if AppCapabilities.current.cloudSync {
                        Text("本机；可选 iCloud 私有同步")
                    } else {
                        Text("storage.onDeviceOnly")
                    }
                }
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
