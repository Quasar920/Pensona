import Observation
import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""

    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]

    let addTransaction: () -> Void
    @Binding private var isDetailPresented: Bool

    @State private var billState = BillPageState(selectedMonth: Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)
    ) ?? .now)
    @State private var snapshot: BillPageSnapshot?
    @State private var refreshGeneration = 0
    @State private var loadError: String?
    @State private var presentation = HomePresentationState()
    @State private var appliedPreviewState = false
    @State private var expandedTransactionID: UUID?
    @State private var detailPath = NavigationPath()
    @State private var deletingTransaction: LedgerTransaction?
    @State private var transactionActionError: String?
    @State private var isBillSearchPresented = false
    @State private var bookSwitcherGenie = CenteredGenieCardPresentation()
    @State private var bookSwitcherSourceFrame = CGRect.zero
    @State private var pendingBookSheet: HomeSheetDestination?

    init(
        addTransaction: @escaping () -> Void = {},
        isDetailPresented: Binding<Bool> = .constant(false)
    ) {
        self.addTransaction = addTransaction
        _isDetailPresented = isDetailPresented
    }

    private var activeBooks: [LedgerBook] {
        books.filter { !$0.isArchived }
    }

    private var selectedBook: LedgerBook? {
        activeBooks.first { $0.id.uuidString == selectedBookID } ?? activeBooks.first
    }

    private var loadKey: BillLoadKey {
        BillLoadKey(
            bookID: selectedBook?.id,
            month: billState.selectedMonth,
            keyword: billState.searchText,
            generation: refreshGeneration
        )
    }

    private var emptyState: (title: String, message: String) {
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: .now)
        ) ?? .now
        if billState.selectedMonth > monthStart {
            return (
                AppLocalization.string( "这个月还没有记录"),
                AppLocalization.string( "未来的收支记录会显示在这里")
            )
        }
        if Calendar.current.isDate(billState.selectedMonth, equalTo: .now, toGranularity: .month) {
            return (
                AppLocalization.string( "还没有记账记录"),
                AppLocalization.string( "点击下方 + 开始添加第一笔交易")
            )
        }
        return (
            AppLocalization.string( "当月没有记录"),
            AppLocalization.string( "可以切换其他月份继续查看")
        )
    }

    var body: some View {
        NavigationStack(path: $detailPath) {
            ZStack {
                HomePalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: LedgerLayout.sectionSpacing) {
                        BillTopControls(
                            bookName: selectedBook?.name ?? AppLocalization.string("选择账本"),
                            openBook: presentBookSwitcher,
                            openSearch: { isBillSearchPresented = true },
                            openSettings: { presentation.present(.settings) }
                        )

                        BillMonthHeader(
                            selectedMonth: billState.selectedMonth,
                            openPicker: { presentation.present(.monthPicker) },
                            changeMonth: changeMonth
                        )

                        if let snapshot {
                            BillMonthlySummaryPanel(
                                summary: snapshot.summary,
                                currencyCode: baseCurrencyCode,
                                openBudget: openBudgetEditor
                            )

                            if snapshot.dayGroups.isEmpty {
                                EmptyRecordsView(
                                    title: billState.searchText.isEmpty
                                        ? emptyState.title
                                        : AppLocalization.string("没有匹配的账单"),
                                    message: billState.searchText.isEmpty
                                        ? emptyState.message
                                        : AppLocalization.string("试试其他关键词"),
                                    addTransaction: billState.searchText.isEmpty ? addTransaction : nil
                                )
                                .ledgerSurface(.functional)
                            } else {
                                ForEach(snapshot.dayGroups) { group in
                                    BillDailyGroup(
                                        group: group,
                                        expandedTransactionID: $expandedTransactionID,
                                        open: openTransaction,
                                        edit: edit,
                                        delete: requestDelete
                                    )
                                }
                            }
                        } else {
                            ProgressView("正在加载账单")
                                .frame(maxWidth: .infinity, minHeight: 180)
                                .ledgerSurface(.functional)
                        }
                    }
                    .padding(.horizontal, LedgerLayout.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, RootEntryLayout.scrollContentClearance)
                }
            }
            .overlay {
                CenteredGenieCardHost(
                    presentation: $bookSwitcherGenie,
                    maximumWidth: 390,
                    onDismissed: presentPendingBookSheet
                ) {
                    HomeBookSwitcherCard(
                        books: activeBooks,
                        selectedBookID: $selectedBookID,
                        dismiss: { bookSwitcherGenie.requestDismissal() },
                        manageBooks: {
                            pendingBookSheet = .bookManagement
                            bookSwitcherGenie.requestDismissal()
                        }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LedgerTransaction.self) {
                TransactionDetailView(transaction: $0)
                    .toolbar(.visible, for: .navigationBar)
            }
            .background {
                HomeSheetPresenter(
                    presentation: presentation,
                    selectedBookID: $selectedBookID,
                    selectedMonth: $billState.selectedMonth
                )
            }
            .fullScreenCover(isPresented: $isBillSearchPresented) {
                BillSearchView()
            }
            .confirmationDialog(
                "确定删除这笔交易？",
                isPresented: Binding(
                    get: { deletingTransaction != nil },
                    set: { if !$0 { deletingTransaction = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除并回滚余额", role: .destructive, action: deletePendingTransaction)
                Button("取消", role: .cancel) { deletingTransaction = nil }
            } message: {
                Text("删除后，相关账户余额会同步回滚。")
            }
            .alert("操作失败", isPresented: Binding(
                get: { transactionActionError != nil },
                set: { if !$0 { transactionActionError = nil } }
            )) { Button("好") {} } message: {
                Text(transactionActionError ?? AppLocalization.string("未知错误"))
            }
            .onAppear {
                ensureSelectedBook()
                applyPreviewStateIfNeeded()
            }
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
            .onPreferenceChange(CenteredGenieSourceFramePreferenceKey.self) { frames in
                if let frame = frames["home-book-switcher"], !frame.isEmpty {
                    bookSwitcherSourceFrame = frame
                }
            }
            .task(id: loadKey) {
                if !billState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                }
                loadSnapshot()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ledgerTransactionsDidChange)) { _ in
                refreshGeneration += 1
            }
            .alert("账单加载失败", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) { Button("好") {} } message: {
                Text(loadError ?? AppLocalization.string("未知错误"))
            }
        }
        .coordinateSpace(name: CenteredGenieCoordinateSpace.name)
        .rootEntryVisibility(detailPath.isEmpty ? .visible : .hidden, for: .ledger)
        .onAppear { isDetailPresented = !detailPath.isEmpty }
        .onChange(of: detailPath.count) { _, count in
            isDetailPresented = count > 0
        }
    }

    private func ensureSelectedBook() {
        guard let first = activeBooks.first else {
            selectedBookID = ""
            return
        }
        if !activeBooks.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }

    private func presentBookSwitcher() {
        let fallback = CGRect(x: 24, y: 54, width: 160, height: LedgerLayout.minimumHitSize)
        bookSwitcherGenie.present(
            from: bookSwitcherSourceFrame.isEmpty ? fallback : bookSwitcherSourceFrame
        )
    }

    private func presentPendingBookSheet() {
        guard let destination = pendingBookSheet else { return }
        pendingBookSheet = nil
        presentation.present(destination)
    }

    private func openBudgetEditor() {
        guard selectedBook != nil else { return }
        presentation.present(.budgetEditor(
            month: billState.selectedMonth,
            currencyCode: baseCurrencyCode,
            currentAmount: snapshot?.summary.budget,
            save: saveBudget
        ))
    }

    private func saveBudget(_ amount: Decimal) throws {
        guard let bookID = selectedBook?.id else { throw ValidationError("请先创建账本") }
        _ = try MonthlyBudgetService(context: context).upsert(
            amount: amount,
            bookID: bookID,
            month: billState.selectedMonth,
            currencyCode: baseCurrencyCode
        )
        refreshGeneration += 1
    }

    private func deletePendingTransaction() {
        guard let transaction = deletingTransaction else { return }
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            deletingTransaction = nil
            refreshGeneration += 1
        } catch {
            transactionActionError = error.localizedDescription
        }
    }

    private func applyPreviewStateIfNeeded() {
        #if DEBUG
        guard !appliedPreviewState else { return }
        appliedPreviewState = true
        switch ProcessInfo.processInfo.environment["HOME_PREVIEW_STATE"] {
        case "book-switcher":
            DispatchQueue.main.async { presentation.present(.bookSwitcher) }
        case "previous-month":
            billState.changeMonth(by: -1)
        case "future-month":
            billState.changeMonth(by: 1)
        case "travel-book":
            if let travelBook = books.first(where: { $0.name == "旅行账本" }) {
                selectedBookID = travelBook.id.uuidString
            }
        case "budget-editor":
            DispatchQueue.main.async { openBudgetEditor() }
        case "bill-search":
            isBillSearchPresented = true
        default:
            break
        }
        #endif
    }

    private func changeMonth(_ offset: Int) {
        expandedTransactionID = nil
        billState.changeMonth(by: offset)
    }

    private func edit(_ transaction: LedgerTransaction) {
        expandedTransactionID = nil
        presentation.present(.editTransaction(transaction))
    }

    private func openTransaction(_ transaction: LedgerTransaction) {
        expandedTransactionID = nil
        detailPath.append(transaction)
    }

    private func requestDelete(_ transaction: LedgerTransaction) {
        expandedTransactionID = nil
        deletingTransaction = transaction
    }

    private func loadSnapshot() {
        guard let bookID = selectedBook?.id else {
            snapshot = nil
            return
        }
        do {
            snapshot = try BillQueryService(context: context).load(
                bookID: bookID,
                month: billState.selectedMonth,
                baseCurrencyCode: baseCurrencyCode,
                keyword: billState.searchText
            )
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct HomeBookSwitcherCard: View {
    let books: [LedgerBook]
    @Binding var selectedBookID: String
    let dismiss: () -> Void
    let manageBooks: () -> Void

    var body: some View {
        CenteredGenieCardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("切换账本")
                            .font(.title3.weight(.bold))
                        Text("选择要查看的账本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(LedgerGlassPressStyle())
                    .accessibilityLabel("关闭")
                }

                bookRows

                Button(action: manageBooks) {
                    Label("管理账本", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(LedgerGlassPressStyle())
                .foregroundStyle(HomePalette.accent)
                .background(HomePalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .accessibilityIdentifier("home-book-switcher-card")
    }

    @ViewBuilder
    private var bookRows: some View {
        if books.count > 4 {
            ScrollView {
                bookRowStack
            }
            .frame(maxHeight: 300)
            .scrollIndicators(.hidden)
        } else {
            bookRowStack
        }
    }

    private var bookRowStack: some View {
        VStack(spacing: 8) {
            ForEach(books) { book in
                Button {
                    selectedBookID = book.id.uuidString
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(HomePalette.accent)
                            .frame(width: 38, height: 38)
                            .background(HomePalette.accent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(book.accounts.filter { !$0.isHidden }.count) 个资产账户")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedBookID == book.id.uuidString {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(HomePalette.accent)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(LedgerGlassPressStyle())
            }
        }
    }
}

private struct BillLoadKey: Hashable {
    let bookID: UUID?
    let month: Date
    let keyword: String
    let generation: Int
}

private struct HomeSheetPresentation: Identifiable {
    let id = UUID()
    let destination: HomeSheetDestination
}

private enum HomeSheetDestination {
    case settings
    case addAsset(LedgerBook?)
    case bookSwitcher
    case bookManagement
    case transactions
    case monthPicker
    case budgetEditor(
        month: Date,
        currencyCode: String,
        currentAmount: Decimal?,
        save: (Decimal) throws -> Void
    )
    case budgetManagement
    case reports
    case calendar
    case smartDraft
    case aaReceivables(UUID)
    case editTransaction(LedgerTransaction)
}

@MainActor
@Observable
private final class HomePresentationState {
    var sheet: HomeSheetPresentation?

    func present(_ destination: HomeSheetDestination) {
        sheet = HomeSheetPresentation(destination: destination)
    }
}

private struct HomeSheetPresenter: View {
    @Bindable var presentation: HomePresentationState
    @Binding var selectedBookID: String
    @Binding var selectedMonth: Date

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $presentation.sheet) { presentation in
                destination(for: presentation.destination)
            }
    }

    @ViewBuilder
    private func destination(for destination: HomeSheetDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .addAsset(let book):
            AddAccountView(book: book)
        case .bookSwitcher:
            LedgerBookSwitcherView(selectedBookID: $selectedBookID)
        case .bookManagement:
            LedgerBookManagementView()
        case .transactions:
            TransactionListView()
        case .monthPicker:
            MonthPickerView(selectedMonth: $selectedMonth)
        case let .budgetEditor(month, currencyCode, currentAmount, save):
            BudgetEditorSheet(
                month: month,
                currencyCode: currencyCode,
                currentAmount: currentAmount,
                save: save
            )
        case .budgetManagement:
            NavigationStack { BudgetManagementView() }
        case .reports:
            ReportsView()
        case .calendar:
            TransactionCalendarView()
        case .smartDraft:
            NavigationStack { SmartDraftEntryView() }
        case .aaReceivables(let bookID):
            AAReceivableListView(bookID: bookID)
        case .editTransaction(let transaction):
            TransactionEditView(transaction: transaction) {}
        }
    }
}

enum HomePalette {
    static let accent = Color(red: 22 / 255, green: 134 / 255, blue: 232 / 255)

    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.045, green: 0.059, blue: 0.078, alpha: 1)
            : UIColor(white: 0.965, alpha: 1)
    })

    static let expense = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.50, blue: 0.47, alpha: 1)
            : UIColor(red: 0.76, green: 0.24, blue: 0.22, alpha: 1)
    })

    static let glassBorder = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(white: 1, alpha: 0.52)
    })

    static let gaugeTrack = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.14)
            : UIColor(white: 1, alpha: 0.88)
    })

    static let gaugeProgress = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.90, alpha: 1)
            : UIColor(white: 0.26, alpha: 1)
    })

    static let glassHighlightShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.025)
            : UIColor(white: 1, alpha: 0.62)
    })
}

private struct MonthNavigator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Binding var selectedMonth: Date
    let openPicker: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                monthButton(systemName: "chevron.left") { changeMonth(by: -1) }

                Button(action: openPicker) {
                    HStack(spacing: 5) {
                        Text(selectedMonth.yearMonthText(locale: locale))
                            .font(.system(size: 13, weight: .semibold))
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.18),
                                value: selectedMonth
                            )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 126, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.glass)
                .accessibilityLabel("选择年月，当前\(selectedMonth.yearMonthText(locale: locale))")

                monthButton(systemName: "chevron.right") { changeMonth(by: 1) }
            }
        }
    }

    private func monthButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HomePalette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glass)
    }

    private func changeMonth(by offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        selectedMonth = month
    }
}

struct TransactionDayGroup: Identifiable {
    let date: Date
    let transactions: [LedgerTransaction]
    var id: Date { date }

    static func make(from transactions: [LedgerTransaction]) -> [TransactionDayGroup] {
        Dictionary(grouping: transactions) { Calendar.current.startOfDay(for: $0.date) }
            .map { TransactionDayGroup(date: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    func cashFlow(
        baseCurrencyCode: String,
        rates: [ExchangeRate],
        relations: [TransactionRelation] = []
    ) -> (income: Decimal, expense: Decimal) {
        let result = MonthlySummaryService(
            baseCurrencyCode: baseCurrencyCode,
            rates: rates
        ).summary(for: transactions, month: date, relations: relations)
        return (result.income, result.expense)
    }
}

private struct DailyRecordCards: View {
    let groups: [TransactionDayGroup]
    let emptyTitle: String
    let emptyMessage: String
    let showAddAction: Bool
    let addTransaction: () -> Void
    @Binding var expandedTransactionID: UUID?
    let lockedTransactionIDs: Set<UUID>
    let editTransaction: (LedgerTransaction) -> Void
    let deleteTransaction: (LedgerTransaction) -> Void

    var body: some View {
        VStack(spacing: 18) {
            if groups.isEmpty {
                EmptyRecordsView(
                    title: emptyTitle,
                    message: emptyMessage,
                    addTransaction: showAddAction ? addTransaction : nil
                )
                .ledgerContentSurface(cornerRadius: 24)
            } else {
                ForEach(groups) { group in
                    DailyRecordCard(
                        group: group,
                        expandedTransactionID: $expandedTransactionID,
                        lockedTransactionIDs: lockedTransactionIDs,
                        editTransaction: editTransaction,
                        deleteTransaction: deleteTransaction
                    )
                }
            }
        }
    }
}

private struct DailyRecordCard: View {
    let group: TransactionDayGroup
    @Binding var expandedTransactionID: UUID?
    let lockedTransactionIDs: Set<UUID>
    let editTransaction: (LedgerTransaction) -> Void
    let deleteTransaction: (LedgerTransaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(group.date.figmaHomeDayHeading)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.leading, 6)

            VStack(spacing: 14) {
                ForEach(group.transactions) { transaction in
                    if lockedTransactionIDs.contains(transaction.id) {
                        NavigationLink(value: transaction) {
                            HomeTransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    } else {
                        SwipeableHomeTransactionRow(
                            transaction: transaction,
                            expandedTransactionID: $expandedTransactionID,
                            edit: { editTransaction(transaction) },
                            delete: { deleteTransaction(transaction) }
                        )
                    }
                }
            }
        }
    }
}

private struct SwipeableHomeTransactionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum RevealedSide {
        case edit
        case delete
    }

    private let actionWidth: CGFloat = 82
    private let openThreshold: CGFloat = 48
    private let closeThreshold: CGFloat = 32

    let transaction: LedgerTransaction
    @Binding var expandedTransactionID: UUID?
    let edit: () -> Void
    let delete: () -> Void

    @State private var revealedSide: RevealedSide?
    @GestureState private var dragTranslation: CGFloat = 0

    private var restingOffset: CGFloat {
        guard expandedTransactionID == transaction.id else { return 0 }
        switch revealedSide {
        case .edit: return actionWidth
        case .delete: return -actionWidth
        case nil: return 0
        }
    }

    private var horizontalOffset: CGFloat {
        let proposed = restingOffset + dragTranslation
        switch revealedSide {
        case .edit:
            // Once one side is open, a reverse gesture only closes it. This
            // prevents a single gesture from jumping through center and
            // revealing the action on the other side.
            return min(actionWidth, max(0, proposed))
        case .delete:
            return min(0, max(-actionWidth, proposed))
        case nil:
            return min(actionWidth, max(-actionWidth, proposed))
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                swipeButton(
                    title: "编辑",
                    symbol: "pencil",
                    color: HomePalette.accent,
                    action: edit
                )
                .opacity(horizontalOffset > 0 ? 1 : 0)
                .allowsHitTesting(horizontalOffset > 0)
                Spacer(minLength: 0)
                swipeButton(
                    title: "删除",
                    symbol: "trash",
                    color: HomePalette.expense,
                    action: delete
                )
                .opacity(horizontalOffset < 0 ? 1 : 0)
                .allowsHitTesting(horizontalOffset < 0)
            }
            .padding(.horizontal, 6)

            NavigationLink(value: transaction) {
                HomeTransactionRow(transaction: transaction)
            }
            .buttonStyle(.plain)
            .offset(x: horizontalOffset)
            .simultaneousGesture(swipeGesture)
            .accessibilityAction(named: "编辑交易", edit)
            .accessibilityAction(named: "删除交易", delete)
        }
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .onChange(of: expandedTransactionID) { _, id in
            if id != transaction.id { revealedSide = nil }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($dragTranslation) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical) {
                    switch revealedSide {
                    case nil where value.translation.width >= openThreshold:
                        revealedSide = .edit
                        expandedTransactionID = transaction.id
                    case nil where value.translation.width <= -openThreshold:
                        revealedSide = .delete
                        expandedTransactionID = transaction.id
                    case .edit where value.translation.width <= -closeThreshold,
                         .delete where value.translation.width >= closeThreshold:
                        revealedSide = nil
                        expandedTransactionID = nil
                    default:
                        break
                    }
                }
            }
    }

    private func swipeButton(
        title: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .frame(width: actionWidth, height: 80)
                .background(color)
        }
        .buttonStyle(.plain)
    }
}

struct HomeTransactionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let transaction: LedgerTransaction

    var body: some View {
        HStack(spacing: 13) {
            if let category = transaction.category {
                CategoryIconImage(category: category, size: 40)
            } else {
                Image(systemName: transaction.type.symbolName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(HomePalette.accent)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(transaction.homeCategoryTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("/ \(transaction.figmaHomeTimestamp)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(transaction.summaryAmount)
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }

                HStack(spacing: 8) {
                    Text(transaction.homeDetailText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(transaction.homeAccountName)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .ledgerContentSurface(cornerRadius: 25)
        .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .padding(.horizontal, 6)
    }
}

private struct EmptyRecordsView: View {
    let title: String
    let message: String
    let addTransaction: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.10), in: Circle())
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let addTransaction {
                Button("添加交易", action: addTransaction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 22)
    }
}

private struct MonthPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMonth: Date
    @State private var year: Int
    @State private var month: Int

    private let years: [Int]

    init(selectedMonth: Binding<Date>) {
        _selectedMonth = selectedMonth
        let components = Calendar.current.dateComponents([.year, .month], from: selectedMonth.wrappedValue)
        let currentYear = Calendar.current.component(.year, from: .now)
        _year = State(initialValue: components.year ?? currentYear)
        _month = State(initialValue: components.month ?? 1)
        years = Array((currentYear - 10)...(currentYear + 5))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("年", selection: $year) {
                    ForEach(years, id: \.self) { Text("\($0)年").tag($0) }
                }
                .pickerStyle(.wheel)

                Picker("月", selection: $month) {
                    ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal)
            .navigationTitle("选择月份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: apply)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
    }

    private func apply() {
        if let value = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) {
            selectedMonth = value
        }
        dismiss()
    }
}

private struct PressableGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive, value: configuration.isPressed)
    }
}

extension LedgerTransaction {
    var displayNote: String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var homeCategoryTitle: String {
        category?.localizedName(locale: AppLocalization.locale) ?? type.title
    }

    var homeDetailText: String {
        displayNote ?? type.title
    }

    var homeAccountName: String {
        sourceAccount?.name ?? destinationAccount?.name ?? AppLocalization.string("未指定账户")
    }

    var figmaHomeTimestamp: String {
        let components = Calendar.current.dateComponents(
            [.month, .day, .hour, .minute],
            from: date
        )
        return String(
            format: "%02d月%02d日 %02d:%02d",
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

}

extension Date {
    func yearMonthText(locale: Locale) -> String {
        formatted(
            .dateTime
                .locale(locale)
                .year()
                .month(.wide)
        )
    }

    func dayHeading(locale: Locale) -> String {
        formatted(.dateTime.locale(locale).month().day())
    }

    var figmaHomeDayHeading: String {
        let components = Calendar.current.dateComponents([.month, .day], from: self)
        return String(
            format: "%02d月%02d日",
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
