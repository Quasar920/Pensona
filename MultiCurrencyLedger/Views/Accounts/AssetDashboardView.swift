import SwiftData
import SwiftUI

extension AssetDashboardGroup {
    var initialAccountType: AccountType {
        switch self {
        case .bankCards: .bankCard
        case .credit: .creditCard
        case .cash: .cash
        case .investment: .investment
        case .storedValue: .eWallet
        case .lending: .receivable
        case .legacyOther: .other
        }
    }
}

struct AssetDashboardScreen: View {
    let snapshot: AssetDashboardSnapshot
    let currencyCode: String
    @Binding var isBalanceHidden: Bool
    let openModule: (AssetModuleKind) -> Void
    let selectAccount: (Account) -> Void
    let editAccount: (Account) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("总资产")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(hidden(snapshot.totalAssets))
                        .font(LedgerTypography.largeAmount)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    HStack(spacing: 16) {
                        statementMetric("账户", amount: accountAssets)
                        statementMetric("负债", amount: creditLiabilities)
                        statementMetric("净资产", amount: snapshot.totalAssets)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)

                Divider()

                ForEach(snapshot.groups) { group in
                    VStack(spacing: 0) {
                        HStack {
                            Label(group.group.title, systemImage: group.group.symbolName)
                                .font(.headline)
                            Spacer()
                            Text(hidden(group.subtotal))
                                .font(LedgerTypography.receiptMeta.weight(.semibold))
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                        Divider()

                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            Button { selectAccount(row.account) } label: {
                                AssetDashboardAccountRow(
                                    row: row,
                                    currencyCode: currencyCode,
                                    isBalanceHidden: isBalanceHidden
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("asset-account-\(row.account.id.uuidString)")
                            .contextMenu {
                                Button { editAccount(row.account) } label: {
                                    Label("编辑账户", systemImage: "pencil")
                                }
                            }
                            .accessibilityAction(named: "编辑账户") { editAccount(row.account) }
                            if index < group.rows.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }

                if !snapshot.modules.isEmpty {
                    Text("其他资产")
                        .font(.headline)
                        .padding(.top, 28)
                        .padding(.bottom, 10)
                    Divider()
                    ForEach(snapshot.modules) { module in
                        Button { openModule(module.kind) } label: {
                            HStack {
                                Label(module.kind.title, systemImage: module.kind.symbolName)
                                Spacer()
                                Text(module.missingCodes.isEmpty ? hidden(module.amount) : "--")
                                    .font(LedgerTypography.receiptMeta.weight(.semibold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 52)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding(.horizontal, LedgerLayout.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, RootEntryLayout.scrollContentClearance)
        }
    }

    private func hidden(_ amount: Decimal) -> String {
        isBalanceHidden ? "••••" : MoneyFormatter.string(amount, currencyCode: currencyCode)
    }

    private var accountAssets: Decimal {
        snapshot.groups.filter { $0.group != .credit }.reduce(0) { $0 + $1.subtotal }
    }

    private var creditLiabilities: Decimal {
        abs(snapshot.groups.first(where: { $0.group == .credit })?.subtotal ?? 0)
    }

    private func statementMetric(_ title: String, amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(hidden(amount))
                .font(LedgerTypography.receiptMeta.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AssetDashboardAccountRow: View {
    let row: AssetAccountRowSnapshot
    let currencyCode: String
    let isBalanceHidden: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.account.type.symbolName)
                .font(.subheadline)
                .foregroundStyle(HomePalette.accent)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.account.name)
                    .font(.subheadline.weight(.semibold))
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(amountText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var amountText: String {
        guard !isBalanceHidden else { return "••••" }
        guard row.missingCodes.isEmpty else { return "--" }
        return MoneyFormatter.string(row.amount, currencyCode: currencyCode)
    }

    private var detailText: String {
        switch row.account.type {
        case .bankCard, .savings:
            let lastFour = AccountCardIdentityStore().lastFour(for: row.account.id)
            return lastFour.map { AppLocalization.string( "尾号 \($0)") } ?? AppLocalization.string( "银行卡")
        case .creditCard:
            if isBalanceHidden { return AppLocalization.string( "可用 •••• · 待还 ••••") }
            let available = max(row.amount, 0)
            let due = max(-row.amount, 0)
            return AppLocalization.string( "可用 \(MoneyFormatter.compactString(available, currencyCode: currencyCode)) · 待还 \(MoneyFormatter.compactString(due, currencyCode: currencyCode))")
        case .investment:
            return isBalanceHidden
                ? AppLocalization.string( "收益金额 ••••")
                : AppLocalization.string( "收益金额 \(MoneyFormatter.compactString(row.amount, currencyCode: currencyCode))")
        case .other:
            return AppLocalization.string( "编辑时请选择批准的账户类型")
        default:
            return row.account.allWallets.map(\.currencyCode).joined(separator: " · ")
        }
    }
}

struct AssetModuleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let kind: AssetModuleKind
    let currentBook: LedgerBook?
    let baseCurrencyCode: String
    let isBalanceHidden: Bool

    @State private var currentBookOnly = false
    @State private var module: AssetModuleSnapshot?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: LedgerLayout.sectionSpacing) {
                Picker("范围", selection: $currentBookOnly) {
                    Text("全部账本").tag(false)
                    Text("当前账本").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(currentBook == nil)

                if let module {
                    VStack(spacing: 10) {
                        Image(systemName: kind.symbolName).font(.largeTitle)
                        Text(isBalanceHidden ? "••••" : MoneyFormatter.string(module.amount, currencyCode: baseCurrencyCode))
                            .font(LedgerTypography.largeAmount)
                            .monospacedDigit()
                        Text(
                            AppLocalization.string(
                                "\(module.count) 项 · \(currentBookOnly ? currentBook?.name ?? AppLocalization.string("当前账本") : AppLocalization.string("全部账本"))"
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .ledgerSurface(.summary)
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
                Spacer()
            }
            .padding(LedgerLayout.pagePadding)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task(id: currentBookOnly) { load() }
            .alert("加载失败", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        }
        .presentationDetents([.medium])
    }

    private func load() {
        do {
            let snapshot = try AssetDashboardService(context: context).snapshot(
                baseCurrencyCode: baseCurrencyCode,
                moduleBookID: currentBookOnly ? currentBook?.id : nil
            )
            module = snapshot.modules.first { $0.kind == kind }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
