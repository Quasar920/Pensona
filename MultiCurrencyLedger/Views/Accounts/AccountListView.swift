import SwiftData
import SwiftUI
import UIKit

struct AccountListView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage("homeBalanceHidden") private var isBalanceHidden = false

    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]
    @Query private var rates: [ExchangeRate]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]

    @State private var addAccountGroup: AssetGroup?
    @State private var editingAccount: Account?
    @State private var detailPath = NavigationPath()
    @State private var alertMessage: String?
    @State private var showingBookSwitcher = false
    @Namespace private var cardTransitionNamespace

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var bookAccounts: [Account] {
        guard let bookID = selectedBook?.id else { return [] }
        return accounts.filter { $0.book?.id == bookID }
    }

    private var visibleAccounts: [Account] {
        bookAccounts.filter { !$0.isHidden && !$0.isArchived }
    }

    private var visibleTransactions: [LedgerTransaction] {
        guard let bookID = selectedBook?.id else { return [] }
        return Array(
            transactions.lazy
                .filter {
                    $0.sourceAccount?.book?.id == bookID || $0.destinationAccount?.book?.id == bookID
                }
                .prefix(5)
        )
    }

    private var summary: AssetSummaryResult {
        AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(for: bookAccounts)
    }

    var body: some View {
        if #available(iOS 26.4, *) {
            AccessibilityCrossFadeEnvironmentReader { prefersCrossFadeTransitions in
                accountListContent(prefersCrossFadeTransitions: prefersCrossFadeTransitions)
            }
        } else {
            accountListContent(
                prefersCrossFadeTransitions: UIAccessibility.prefersCrossFadeTransitions
            )
        }
    }

    private func accountListContent(prefersCrossFadeTransitions: Bool) -> some View {
        NavigationStack(path: $detailPath) {
            ZStack {
                AssetPagePalette.background.ignoresSafeArea()

                AssetOverviewScreen(
                    currencyCode: baseCurrencyCode,
                    totalAssets: summary.totalAssets,
                    hasAccounts: !bookAccounts.isEmpty,
                    isBalanceHidden: $isBalanceHidden,
                    accounts: Array(visibleAccounts.prefix(8)),
                    rates: rates,
                    transactions: visibleTransactions,
                    cardTransitionNamespace: cardTransitionNamespace,
                    addAccount: { addAccountGroup = $0 },
                    selectAccount: { account in
                        guard detailPath.isEmpty else { return }
                        detailPath.append(account)
                    },
                    editAccount: { editingAccount = $0 }
                )
            }
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingBookSwitcher = true } label: {
                        Label(selectedBook?.name ?? "选择账本", systemImage: "book.closed")
                    }
                    .accessibilityHint("切换账本")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AssetGroup.allCases) { group in
                            Button { addAccountGroup = group } label: {
                                Label(group.title, systemImage: group.symbolName)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加账户")

                    Button { alertMessage = statusMessage } label: {
                        Image(systemName: summary.missingCodes.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    }
                    .accessibilityLabel("查看资产状态")
                }
            }
            .navigationDestination(for: Account.self) { account in
                accountDetailDestination(
                    for: account,
                    prefersCrossFadeTransitions: prefersCrossFadeTransitions
                )
            }
            .navigationDestination(for: LedgerTransaction.self) { transaction in
                TransactionDetailView(transaction: transaction)
                    .toolbar(.visible, for: .navigationBar)
                    .rootEntryVisibility(.hidden, for: .assets)
            }
            .sheet(item: $addAccountGroup) { group in
                AddAccountView(book: selectedBook, initialGroup: group)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditView(account: account)
            }
            .sheet(isPresented: $showingBookSwitcher) {
                LedgerBookSwitcherView(selectedBookID: $selectedBookID)
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                ensureSelectedBook()
            }
            .onChange(of: books.count) { _, _ in
                ensureSelectedBook()
            }
        }
    }

    @ViewBuilder
    private func accountDetailDestination(
        for account: Account,
        prefersCrossFadeTransitions: Bool
    ) -> some View {
        let detail = AssetCardDetailScreen(
            account: account,
            currencyCode: baseCurrencyCode,
            rates: rates,
            allTransactions: transactions,
            isBalanceHidden: isBalanceHidden
        )

        if prefersCrossFadeTransitions {
            if #available(iOS 27.0, *) {
                detail
                    .rootEntryVisibility(.hidden, for: .assets)
                    .navigationTransition(.crossFade)
            } else {
                detail
                    .rootEntryVisibility(.hidden, for: .assets)
                    .navigationTransition(.automatic)
            }
        } else {
            detail
                .rootEntryVisibility(.hidden, for: .assets)
                .navigationTransition(
                    .zoom(sourceID: account.id, in: cardTransitionNamespace)
                )
        }
    }

    private var statusMessage: String {
        if bookAccounts.isEmpty {
            return "当前账本还没有账户，点击左上角按钮即可添加第一张资产卡。"
        }
        if !summary.missingCodes.isEmpty {
            return "\(summary.missingCodes.sorted().joined(separator: "、")) 缺少汇率，相关余额暂未计入汇总。"
        }
        return "已按 \(baseCurrencyCode) 汇总 \(visibleAccounts.count) 个可见账户。"
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }
}

@available(iOS 26.4, *)
private struct AccessibilityCrossFadeEnvironmentReader<Content: View>: View {
    @Environment(\.accessibilityPrefersCrossFadeTransitions)
    private var prefersCrossFadeTransitions
    private let content: (Bool) -> Content

    init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    var body: some View {
        content(prefersCrossFadeTransitions)
    }
}

private struct AssetOverviewScreen: View {
    let currencyCode: String
    let totalAssets: Decimal
    let hasAccounts: Bool
    @Binding var isBalanceHidden: Bool
    let accounts: [Account]
    let rates: [ExchangeRate]
    let transactions: [LedgerTransaction]
    let cardTransitionNamespace: Namespace.ID
    let addAccount: (AssetGroup) -> Void
    let selectAccount: (Account) -> Void
    let editAccount: (Account) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 19) {
                AssetBalanceHero(
                    currencyCode: currencyCode,
                    totalAssets: totalAssets,
                    hasAccounts: hasAccounts,
                    isBalanceHidden: $isBalanceHidden
                )

                AssetCardStrip(
                    accounts: accounts,
                    currencyCode: currencyCode,
                    rates: rates,
                    isBalanceHidden: isBalanceHidden,
                    cardTransitionNamespace: cardTransitionNamespace,
                    addAccount: { addAccount(.cash) },
                    selectAccount: selectAccount,
                    editAccount: editAccount
                )
                .padding(.horizontal, -18)

                AssetTransactionSection(
                    transactions: transactions,
                    addTransaction: { addAccount(.cash) }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, RootEntryLayout.scrollContentClearance)
        }
    }
}

private struct AssetBalanceHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currencyCode: String
    let totalAssets: Decimal
    let hasAccounts: Bool
    @Binding var isBalanceHidden: Bool

    private var totalText: String {
        guard !isBalanceHidden else { return "••••••" }
        guard hasAccounts else { return "0.00" }
        return MoneyFormatter.plain(totalAssets, currencyCode: currencyCode)
    }

    var body: some View {
        VStack(spacing: 5) {
            Text(totalText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(AssetPagePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(reduceMotion ? .opacity : .numericText())

            Button {
                withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive) {
                    isBalanceHidden.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("总资产 · \(currencyCode)")
                    Image(systemName: isBalanceHidden ? "eye.slash.fill" : "eye.fill")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AssetPagePalette.secondaryInk)
                .frame(minHeight: 44)
            }
            .buttonStyle(AssetPressButtonStyle())
            .accessibilityLabel(isBalanceHidden ? "显示总资产" : "隐藏总资产")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }
}

private struct AssetCardStrip: View {
    let accounts: [Account]
    let currencyCode: String
    let rates: [ExchangeRate]
    let isBalanceHidden: Bool
    let cardTransitionNamespace: Namespace.ID
    let addAccount: () -> Void
    let selectAccount: (Account) -> Void
    let editAccount: (Account) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 24) {
                if accounts.isEmpty {
                    Button(action: addAccount) {
                        EmptyAssetCard()
                            .frame(width: 150, height: 190)
                    }
                    .buttonStyle(AssetPressButtonStyle())
                } else {
                    ForEach(accounts) { account in
                        Button {
                            selectAccount(account)
                        } label: {
                            AssetBankCard(
                                account: account,
                                currencyCode: currencyCode,
                                rates: rates,
                                isBalanceHidden: isBalanceHidden,
                                presentation: .compact,
                                revealsDetail: true
                            )
                            .frame(width: 150, height: 190)
                        }
                        .buttonStyle(AssetPressButtonStyle())
                        .matchedTransitionSource(id: account.id, in: cardTransitionNamespace) { source in
                            source.clipShape(
                                RoundedRectangle(cornerRadius: 23, style: .continuous)
                            )
                        }
                        .contextMenu {
                            Button {
                                editAccount(account)
                            } label: {
                                Label("编辑账户", systemImage: "pencil")
                            }
                        }
                        .accessibilityAction(named: "编辑账户") {
                            editAccount(account)
                        }
                        .accessibilityHint("打开卡片详情")
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .frame(height: 200)
    }
}

private enum AssetCardPresentation {
    case compact
    case expanded
}

private struct AssetBankCard: View {
    let account: Account
    let currencyCode: String
    let rates: [ExchangeRate]
    let isBalanceHidden: Bool
    let presentation: AssetCardPresentation
    let revealsDetail: Bool

    private var valuation: AccountValuationResult {
        AssetSummaryService(baseCurrencyCode: currencyCode, rates: rates)
            .value(for: account)
    }

    private var accent: Color {
        AssetPagePalette.accent(for: account.type.assetGroup)
    }

    private var primaryCurrency: String {
        account.enabledWallets.first?.currencyCode ?? account.allWallets.first?.currencyCode ?? currencyCode
    }

    private var brandText: String {
        account.type.assetGroup == .credit ? "CREDIT" : primaryCurrency
    }

    private var balanceText: String {
        if isBalanceHidden { return "••••" }
        guard valuation.hasEnabledWallets else { return "--" }
        return MoneyFormatter.string(valuation.value, currencyCode: currencyCode)
    }

    private var cornerRadius: CGFloat {
        presentation == .compact ? 23 : 27
    }

    private var maskedCardNumber: String {
        let lastFour = account.type.supportsCardLastFour
            ? AccountCardIdentityStore().lastFour(for: account.id)
            : nil
        return AccountCardIdentityStore.maskedNumber(lastFour: lastFour)
    }

    var body: some View {
        ZStack {
            AssetCardSurface(accent: accent, cornerRadius: cornerRadius)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(brandText)
                        .font(.system(size: presentation == .compact ? 15 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AssetPagePalette.ink)

                    Spacer()
                }

                Spacer()

                if presentation == .compact {
                    Image(systemName: account.type.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 31, height: 31)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())

                    Spacer()

                    Text(account.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AssetPagePalette.ink)
                        .lineLimit(1)
                    Text(balanceText)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(AssetPagePalette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(.top, 3)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(maskedCardNumber)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .tracking(1.2)
                            .foregroundStyle(AssetPagePalette.ink)

                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                    .font(.caption2)
                                    .foregroundStyle(AssetPagePalette.secondaryInk)
                                Text(primaryCurrency)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AssetPagePalette.ink)
                            }

                            Spacer()

                            Text(balanceText)
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(AssetPagePalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    .opacity(revealsDetail ? 1 : 0)
                    .blur(radius: revealsDetail ? 0 : 7)
                }
            }
            .padding(presentation == .compact ? 15 : 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct AssetCardSurface: View {
    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 190, height: 190)
                .offset(x: 92, y: -78)
            Circle()
                .fill(accent.opacity(0.075))
                .frame(width: 150, height: 150)
                .offset(x: -96, y: 92)
            LinearGradient(
                colors: [Color.primary.opacity(0.05), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 0.8)
        }
        .background {
            shape
                .fill(Color.clear)
                .shadow(color: AssetPagePalette.shadow, radius: 8, y: 3)
        }
    }
}

private struct EmptyAssetCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(AssetPagePalette.accent)
                .assetCircleSurface(size: 42)
            Text("添加资产卡")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AssetPagePalette.ink)
            Text("账户将显示在这里")
                .font(.caption2)
                .foregroundStyle(AssetPagePalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .assetGlassSurface(cornerRadius: 23)
    }
}

private struct AssetTransactionSection: View {
    let transactions: [LedgerTransaction]
    let addTransaction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("最近交易")
                    .font(.title3.bold())
                    .foregroundStyle(AssetPagePalette.ink)
                Spacer()
                Text("近 \(transactions.count) 笔")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AssetPagePalette.secondaryInk)
            }

            if transactions.isEmpty {
                Button(action: addTransaction) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AssetPagePalette.accent)
                        Text("暂无交易，添加账户后开始记录")
                            .font(.subheadline)
                            .foregroundStyle(AssetPagePalette.secondaryInk)
                        Spacer()
                    }
                    .padding(16)
                    .assetGlassSurface(cornerRadius: 22)
                }
                .buttonStyle(AssetPressButtonStyle())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        AssetTransactionRow(transaction: transaction)
                            .padding(.horizontal, 14)

                        if index < transactions.count - 1 {
                            Divider()
                                .padding(.leading, 60)
                                .opacity(0.55)
                        }
                    }
                }
                .assetGlassSurface(cornerRadius: 24)
            }
        }
    }
}

private struct AssetTransactionRow: View {
    let transaction: LedgerTransaction

    private var title: String {
        transaction.merchantOrCounterparty
            ?? transaction.category?.name
            ?? transaction.type.title
    }

    private var tint: Color {
        switch transaction.type {
        case .income:
            AssetPagePalette.positive
        case .expense:
            AssetPagePalette.negative
        default:
            AssetPagePalette.accent
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.symbolName ?? transaction.type.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AssetPagePalette.ink)
                    .lineLimit(1)
                Text(transaction.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(AssetPagePalette.secondaryInk)
            }

            Spacer(minLength: 8)

            Text(transaction.summaryAmount)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minHeight: 57)
    }
}

private struct AssetCardDetailScreen: View {
    let account: Account
    let currencyCode: String
    let rates: [ExchangeRate]
    let allTransactions: [LedgerTransaction]
    let isBalanceHidden: Bool

    private var transactions: [LedgerTransaction] {
        let accountID = account.id
        return allTransactions.filter {
            $0.sourceAccount?.id == accountID || $0.destinationAccount?.id == accountID
        }
    }

    var body: some View {
        ZStack {
            AssetPagePalette.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 17) {
                    AssetBankCard(
                        account: account,
                        currencyCode: currencyCode,
                        rates: rates,
                        isBalanceHidden: isBalanceHidden,
                        presentation: .expanded,
                        revealsDetail: true
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("这张卡的交易")
                            .font(.headline)
                            .foregroundStyle(AssetPagePalette.ink)

                        if transactions.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .foregroundStyle(AssetPagePalette.accent)
                                Text("当前卡片暂无交易")
                                    .font(.subheadline)
                                    .foregroundStyle(AssetPagePalette.secondaryInk)
                                Spacer()
                            }
                            .padding(16)
                            .assetGlassSurface(cornerRadius: 22)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                                    NavigationLink(value: transaction) {
                                        AssetTransactionRow(transaction: transaction)
                                            .padding(.horizontal, 14)
                                    }
                                    .buttonStyle(.plain)

                                    if index < transactions.count - 1 {
                                        Divider()
                                            .padding(.leading, 60)
                                            .opacity(0.55)
                                    }
                                }
                            }
                            .assetGlassSurface(cornerRadius: 24)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private enum AssetPagePalette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static let accent = Color(red: 101 / 255, green: 91 / 255, blue: 223 / 255)
    static let positive = Color(red: 34 / 255, green: 153 / 255, blue: 107 / 255)
    static let negative = Color(red: 210 / 255, green: 73 / 255, blue: 76 / 255)
    static let warning = Color(red: 222 / 255, green: 133 / 255, blue: 42 / 255)
    static let shadow = Color(red: 34 / 255, green: 42 / 255, blue: 64 / 255).opacity(0.1)

    static func accent(for group: AssetGroup) -> Color {
        switch group {
        case .cash:
            Color(red: 48 / 255, green: 150 / 255, blue: 116 / 255)
        case .credit:
            Color(red: 208 / 255, green: 91 / 255, blue: 132 / 255)
        case .recharge:
            Color(red: 43 / 255, green: 139 / 255, blue: 202 / 255)
        case .investment:
            Color(red: 111 / 255, green: 92 / 255, blue: 205 / 255)
        case .receivable:
            Color(red: 51 / 255, green: 160 / 255, blue: 175 / 255)
        case .payable:
            Color(red: 225 / 255, green: 130 / 255, blue: 61 / 255)
        }
    }
}

private struct AssetGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let castsShadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .overlay {
                shape.stroke(Color(uiColor: .separator).opacity(0.22), lineWidth: 0.8)
            }
            .shadow(
                color: castsShadow ? AssetPagePalette.shadow : .clear,
                radius: castsShadow ? 8 : 0,
                y: castsShadow ? 3 : 0
            )
    }
}

private struct AssetPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.88 : 1)
            .animation(
                pressAnimation(isPressed: configuration.isPressed),
                value: configuration.isPressed
            )
    }

    private func pressAnimation(isPressed: Bool) -> Animation {
        if isPressed {
            return reduceMotion
                ? LedgerMotion.reduced
                : .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
        }

        return reduceMotion
            ? .easeOut(duration: 0.10)
            : .timingCurve(0.23, 1, 0.32, 1, duration: 0.10)
    }
}

private extension View {
    func assetGlassSurface(cornerRadius: CGFloat, castsShadow: Bool = true) -> some View {
        modifier(AssetGlassSurface(cornerRadius: cornerRadius, castsShadow: castsShadow))
    }

    func assetCircleSurface(size: CGFloat) -> some View {
        frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
    }
}
