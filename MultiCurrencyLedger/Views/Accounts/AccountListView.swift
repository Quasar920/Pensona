import SwiftData
import SwiftUI

struct AccountListView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage("homeBalanceHidden") private var isBalanceHidden = false

    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]
    @Query private var rates: [ExchangeRate]

    @State private var addAccountGroup: AssetGroup?
    @State private var appliedPreviewState = false

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var visibleAccounts: [Account] {
        guard let bookID = selectedBook?.id else { return [] }
        return accounts.filter { !$0.isHidden && $0.book?.id == bookID }
    }

    private var summary: AssetSummaryResult {
        AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(for: visibleAccounts)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 22) {
                        AssetPageHeader(
                            bookName: selectedBook?.name ?? "当前账本",
                            currencyCode: baseCurrencyCode
                        )

                        AssetSummaryCard(
                            currencyCode: baseCurrencyCode,
                            totalAssets: summary.totalAssets,
                            missingCodes: summary.missingCodes,
                            hasAccounts: !visibleAccounts.isEmpty,
                            isHidden: $isBalanceHidden
                        )

                        ForEach(AssetGroup.allCases) { group in
                            AssetAccountSection(
                                group: group,
                                accounts: accounts(in: group),
                                baseCurrencyCode: baseCurrencyCode,
                                rates: rates,
                                isBalanceHidden: isBalanceHidden,
                                addAccount: { addAccountGroup = group }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Account.self) {
                AccountDetailView(account: $0)
                    .toolbar(.visible, for: .navigationBar)
            }
            .sheet(item: $addAccountGroup) { group in
                AddAccountView(book: selectedBook, initialGroup: group)
            }
            .onAppear {
                ensureSelectedBook()
                applyPreviewStateIfNeeded()
            }
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
        }
    }

    private func accounts(in group: AssetGroup) -> [Account] {
        visibleAccounts.filter { $0.type.assetGroup == group }
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }

    private func applyPreviewStateIfNeeded() {
        #if DEBUG
        guard !appliedPreviewState else { return }
        appliedPreviewState = true
        switch ProcessInfo.processInfo.environment["ASSET_PREVIEW_STATE"] {
        case "hidden-balance":
            isBalanceHidden = true
        case "add-credit":
            DispatchQueue.main.async { addAccountGroup = .credit }
        default:
            break
        }
        #endif
    }
}

private struct AssetPageHeader: View {
    let bookName: String
    let currencyCode: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("资产")
                    .font(.largeTitle.bold())
                Text(bookName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Image(systemName: "globe.asia.australia.fill")
                Text(currencyCode)
                    .monospaced()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.accentColor.opacity(0.09), in: Capsule())
            .accessibilityLabel("本位币 \(currencyCode)")
        }
        .frame(minHeight: 58)
    }
}

private struct AssetSummaryCard: View {
    let currencyCode: String
    let totalAssets: Decimal
    let missingCodes: Set<String>
    let hasAccounts: Bool
    @Binding var isHidden: Bool

    private var helperText: String {
        if !hasAccounts { return "添加账户后，这里会汇总你的资产" }
        if !missingCodes.isEmpty {
            return "\(missingCodes.sorted().joined(separator: "、")) 缺少汇率，相关余额暂未计入"
        }
        return "按本位币折算后的资产总额"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Color.accentColor)
                Text("总资产")
                    .font(.headline)

                Spacer()

                Text(currencyCode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isHidden.toggle() }
                } label: {
                    Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(AssetPressButtonStyle())
                .accessibilityLabel(isHidden ? "显示全部资产金额" : "隐藏全部资产金额")
            }

            Text(isHidden
                 ? MoneyFormatter.currencySymbol(currencyCode: currencyCode) + "••••••"
                 : MoneyFormatter.string(totalAssets, currencyCode: currencyCode))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .tracking(-1.2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .contentTransition(.numericText())

            Text(helperText)
                .font(.footnote)
                .foregroundStyle(missingCodes.isEmpty ? Color.secondary : Color.orange)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.075), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(HomePalette.glassBorder, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 20, y: 9)
    }
}

private struct AssetAccountSection: View {
    let group: AssetGroup
    let accounts: [Account]
    let baseCurrencyCode: String
    let rates: [ExchangeRate]
    let isBalanceHidden: Bool
    let addAccount: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: group.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.10), in: Circle())

                Text(group.title)
                    .font(.headline)

                Spacer()

                Button(action: addAccount) {
                    Label("添加", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 68, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AssetPressButtonStyle())
                .accessibilityLabel("添加\(group.title)")
            }

            if accounts.isEmpty {
                EmptyAccountCard(group: group, addAccount: addAccount)
            } else {
                ForEach(accounts) { account in
                    NavigationLink(value: account) {
                        AccountGlassCard(
                            account: account,
                            baseCurrencyCode: baseCurrencyCode,
                            rates: rates,
                            isBalanceHidden: isBalanceHidden
                        )
                    }
                    .buttonStyle(AssetPressButtonStyle())
                }
            }
        }
    }
}

private struct AccountGlassCard: View {
    let account: Account
    let baseCurrencyCode: String
    let rates: [ExchangeRate]
    let isBalanceHidden: Bool

    private var valuation: AccountValuationResult {
        AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .value(for: account)
    }

    private var walletDescription: String {
        let codes = account.enabledWallets.map(\.currencyCode)
        if codes.isEmpty { return "尚未添加币种" }
        if !valuation.missingCodes.isEmpty { return "部分币种缺少汇率" }
        return codes.joined(separator: " / ")
    }

    private var balanceText: String {
        if isBalanceHidden { return "••••" }
        guard valuation.hasEnabledWallets else { return "--" }
        return MoneyFormatter.string(valuation.value, currencyCode: baseCurrencyCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.assetGroup.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(HomePalette.glassBorder, lineWidth: 0.8))

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(walletDescription)
                    .font(.caption)
                    .foregroundStyle(valuation.missingCodes.isEmpty ? Color.secondary : Color.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(balanceText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        !isBalanceHidden && valuation.value < 0
                            ? HomePalette.expense
                            : Color.primary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if valuation.hasEnabledWallets && valuation.value < 0 && !isBalanceHidden {
                    Text("待还款")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(HomePalette.expense)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 70)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.glassBorder, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 15, y: 7)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开账户详情")
    }
}

private struct EmptyAccountCard: View {
    let group: AssetGroup
    let addAccount: () -> Void

    var body: some View {
        Button(action: addAccount) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("暂无账户")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("添加第一个\(group.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(HomePalette.glassBorder, lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(AssetPressButtonStyle())
    }
}

private struct AssetPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
