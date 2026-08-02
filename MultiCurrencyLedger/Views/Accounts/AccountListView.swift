import SwiftData
import SwiftUI
import UIKit

struct AccountListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage("homeBalanceHidden") private var isBalanceHidden = false

    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @State private var addAccountType: AccountType?
    @State private var editingAccount: Account?
    @State private var detailPath = NavigationPath()
    @State private var alertMessage: String?
    @State private var snapshot: AssetDashboardSnapshot?
    @State private var selectedModule: AssetModuleKind?
    @State private var refreshGeneration = 0
    @State private var appliedPreviewState = false
    @Binding private var isDetailPresented: Bool

    init(isDetailPresented: Binding<Bool> = .constant(false)) {
        _isDetailPresented = isDetailPresented
    }

    private var selectedBook: LedgerBook? {
        let activeBooks = books.filter { !$0.isArchived }
        return activeBooks.first { $0.id.uuidString == selectedBookID } ?? activeBooks.first
    }

    var body: some View {
        NavigationStack(path: $detailPath) {
            ZStack {
                AssetPagePalette.background.ignoresSafeArea()
                if let snapshot {
                    AssetDashboardScreen(
                        snapshot: snapshot,
                        currencyCode: baseCurrencyCode,
                        isBalanceHidden: $isBalanceHidden,
                        openModule: { selectedModule = $0 },
                        selectAccount: openAccount,
                        editAccount: { editingAccount = $0 }
                    )
                } else {
                    ProgressView("正在加载资产")
                }
            }
            .navigationTitle("资产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isBalanceHidden.toggle()
                    } label: {
                        Image(systemName: isBalanceHidden ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(
                        isBalanceHidden
                            ? AppLocalization.string("显示资产金额")
                            : AppLocalization.string("隐藏资产金额")
                    )
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AssetDashboardGroup.allCases.filter { $0 != .legacyOther }) { group in
                            Button { addAccountType = group.initialAccountType } label: {
                                Label(group.title, systemImage: group.symbolName)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加账户")

                    Button { alertMessage = statusMessage } label: {
                        Image(systemName: snapshot?.missingCodes.isEmpty == false ? "exclamationmark.triangle" : "checkmark.circle")
                    }
                    .accessibilityLabel("查看资产状态")
                }
            }
            .navigationDestination(for: Account.self) { account in
                AccountDetailView(account: account)
            }
            .navigationDestination(for: LedgerTransaction.self) { transaction in
                TransactionDetailView(transaction: transaction)
                    .toolbar(.visible, for: .navigationBar)
            }
            .sheet(item: $addAccountType, onDismiss: reload) { type in
                AddAccountView(initialType: type)
            }
            .sheet(item: $editingAccount, onDismiss: reload) { account in
                AccountEditView(account: account)
            }
            .sheet(item: $selectedModule) { module in
                AssetModuleDetailSheet(
                    kind: module,
                    currentBook: selectedBook,
                    baseCurrencyCode: baseCurrencyCode,
                    isBalanceHidden: isBalanceHidden
                )
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
                applyPreviewStateIfNeeded()
            }
            .onChange(of: books.count) { _, _ in
                ensureSelectedBook()
            }
            .task(id: refreshGeneration) { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .ledgerTransactionsDidChange)) { _ in
                refreshGeneration += 1
            }
        }
        .rootEntryVisibility(detailPath.isEmpty ? .visible : .hidden, for: .assets)
        .onAppear { isDetailPresented = !detailPath.isEmpty }
        .onChange(of: detailPath.count) { _, count in
            isDetailPresented = count > 0
        }
    }

    private var statusMessage: String {
        guard let snapshot else { return AppLocalization.string( "资产数据正在加载。") }
        if snapshot.groups.isEmpty {
            return AppLocalization.string( "还没有账户，点击右上角加号即可添加第一项资产。")
        }
        if !snapshot.missingCodes.isEmpty {
            return AppLocalization.string( "\(snapshot.missingCodes.sorted().joined(separator: "、")) 缺少汇率，相关余额暂未计入汇总。")
        }
        let count = snapshot.groups.reduce(0) { $0 + $1.rows.count }
        return AppLocalization.string( "已按 \(baseCurrencyCode) 汇总全部 \(count) 个可见账户。")
    }

    private func ensureSelectedBook() {
        guard let first = books.first(where: { !$0.isArchived }) else {
            selectedBookID = ""
            return
        }
        if !books.contains(where: { !$0.isArchived && $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }

    private func openAccount(_ account: Account) {
        guard detailPath.isEmpty else { return }
        detailPath.append(account)
    }

    private func reload() {
        do {
            snapshot = try AssetDashboardService(context: context).snapshot(
                baseCurrencyCode: baseCurrencyCode
            )
            runPreviewCyclesIfNeeded()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func applyPreviewStateIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ASSET_PREVIEW_HIDDEN"] == "1" {
            isBalanceHidden = true
        }
        #endif
    }

    private func runPreviewCyclesIfNeeded() {
        #if DEBUG
        guard !appliedPreviewState,
              let countText = ProcessInfo.processInfo.environment["ASSET_PREVIEW_CYCLES"],
              let count = Int(countText), count > 0,
              let account = snapshot?.groups.first?.rows.first?.account else { return }
        appliedPreviewState = true
        Task { @MainActor in
            for _ in 0..<count {
                detailPath.append(account)
                try? await Task.sleep(for: .milliseconds(120))
                if !detailPath.isEmpty { detailPath.removeLast() }
                try? await Task.sleep(for: .milliseconds(120))
            }
            print("ASSET_PREVIEW_CYCLES_COMPLETED=\(count)")
        }
        #endif
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
            .accessibilityLabel(
                isBalanceHidden
                    ? AppLocalization.string("显示总资产")
                    : AppLocalization.string("隐藏总资产")
            )
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
            if let category = transaction.category {
                CategoryIconImage(category: category, size: 38)
            } else {
                Image(systemName: transaction.type.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.11), in: Circle())
            }

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
