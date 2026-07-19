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
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query private var rates: [ExchangeRate]
    @Query(sort: \MonthlyBudget.monthStart, order: .reverse) private var budgets: [MonthlyBudget]
    @Query private var relations: [TransactionRelation]
    @Query private var aaSplits: [AASplit]
    @Query private var aaSettlements: [AASettlement]

    let addTransaction: () -> Void

    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)
    ) ?? .now
    @State private var presentation = HomePresentationState()
    @State private var appliedPreviewState = false
    @State private var expandedTransactionID: UUID?
    @State private var deletingTransaction: LedgerTransaction?
    @State private var transactionActionError: String?

    init(addTransaction: @escaping () -> Void = {}) {
        self.addTransaction = addTransaction
    }

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var ledgerScope: LedgerScope? {
        selectedBook.map {
            LedgerScope(
                bookID: $0.id,
                selectedMonth: selectedMonth,
                baseCurrencyCode: baseCurrencyCode
            )
        }
    }

    private var selectedBookTransactions: [LedgerTransaction] {
        guard let ledgerScope else { return [] }
        return transactions.filter(ledgerScope.transactionBelongsToBook)
    }

    private var selectedMonthTransactions: [LedgerTransaction] {
        guard let ledgerScope else { return [] }
        return selectedBookTransactions.filter { ledgerScope.contains(date: $0.date) }
    }

    private var currentBudget: MonthlyBudget? {
        guard let ledgerScope else { return nil }
        return budgets.first(where: ledgerScope.matches)
    }

    private var monthlySummary: MonthlySummaryResult {
        MonthlySummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(
                for: selectedBookTransactions,
                month: selectedMonth,
                budget: currentBudget?.amount,
                relations: relations,
                aaSplits: aaSplits,
                aaSettlements: aaSettlements
            )
    }

    private var aaItems: [AAReceivableItem] {
        guard let bookID = selectedBook?.id else { return [] }
        return AAQueryService().items(
            splits: aaSplits,
            settlements: aaSettlements,
            transactions: transactions,
            bookID: bookID
        )
    }

    private var aaOverview: AAReceivableOverview {
        AAQueryService().overview(
            items: aaItems,
            baseCurrencyCode: baseCurrencyCode,
            rates: rates
        )
    }

    private var aaRecoveryTransactionIDs: Set<UUID> {
        Set(aaSettlements.map(\.recoveryTransactionID))
    }

    private var recentDayGroups: [TransactionDayGroup] {
        TransactionDayGroup.make(from: Array(selectedMonthTransactions.prefix(6)))
    }

    private var emptyState: (title: String, message: String) {
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: .now)
        ) ?? .now
        if selectedMonth > monthStart {
            return ("这个月还没有记录", "未来的收支记录会显示在这里")
        }
        if Calendar.current.isDate(selectedMonth, equalTo: .now, toGranularity: .month) {
            return ("还没有记账记录", "点击下方 + 开始添加第一笔交易")
        }
        return ("当月没有记录", "可以切换其他月份继续查看")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        MonthlyOverviewCard(
                            currencyCode: baseCurrencyCode,
                            summary: monthlySummary,
                            setBudget: openBudgetEditor
                        )

                        AAReceivableHomeCard(
                            overview: aaOverview,
                            currencyCode: baseCurrencyCode,
                            open: {
                                guard let bookID = selectedBook?.id else { return }
                                presentation.present(.aaReceivables(bookID))
                            }
                        )

                        MonthNavigator(
                            selectedMonth: $selectedMonth,
                            openPicker: { presentation.present(.monthPicker) }
                        )

                        DailyRecordCards(
                            groups: recentDayGroups,
                            emptyTitle: emptyState.title,
                            emptyMessage: emptyState.message,
                            showAddAction: Calendar.current.isDate(
                                selectedMonth,
                                equalTo: .now,
                                toGranularity: .month
                            ),
                            addTransaction: addTransaction,
                            expandedTransactionID: $expandedTransactionID,
                            lockedTransactionIDs: aaRecoveryTransactionIDs,
                            editTransaction: { transaction in
                                expandedTransactionID = nil
                                presentation.present(.editTransaction(transaction))
                            },
                            deleteTransaction: { transaction in
                                expandedTransactionID = nil
                                deletingTransaction = transaction
                            }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, RootEntryLayout.scrollContentClearance)
                }
            }
            .navigationTitle("流水")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { presentation.present(.bookSwitcher) } label: {
                        Label(selectedBook?.name ?? "选择账本", systemImage: "book.closed")
                    }
                    .accessibilityHint("切换账本")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { presentation.present(.transactions) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索流水")

                    Menu {
                        Button { presentation.present(.bookManagement) } label: {
                            Label("管理账本", systemImage: "slider.horizontal.3")
                        }
                        Button { presentation.present(.calendar) } label: {
                            Label("账单日历", systemImage: "calendar")
                        }
                        Button { presentation.present(.smartDraft) } label: {
                            Label("文本或语音记账", systemImage: "waveform.and.mic")
                        }
                        Button { presentation.present(.addAsset(selectedBook)) } label: {
                            Label("新增账户", systemImage: "creditcard.badge.plus")
                        }
                        Divider()
                        Button { presentation.present(.settings) } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多流水操作")
                }
            }
            .navigationDestination(for: LedgerTransaction.self) {
                TransactionDetailView(transaction: $0)
                    .toolbar(.visible, for: .navigationBar)
                    .rootEntryVisibility(.hidden, for: .ledger)
            }
            .background {
                HomeSheetPresenter(
                    presentation: presentation,
                    selectedBookID: $selectedBookID,
                    selectedMonth: $selectedMonth
                )
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
                Text(transactionActionError ?? "未知错误")
            }
            .onAppear {
                ensureSelectedBook()
                applyPreviewStateIfNeeded()
            }
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
        }
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }

    private func openBudgetEditor() {
        guard selectedBook != nil else { return }
        presentation.present(.budgetEditor(
            month: selectedMonth,
            currencyCode: baseCurrencyCode,
            currentAmount: currentBudget?.amount,
            save: saveBudget
        ))
    }

    private func saveBudget(_ amount: Decimal) throws {
        guard let bookID = selectedBook?.id else { throw ValidationError("请先创建账本") }
        _ = try MonthlyBudgetService(context: context).upsert(
            amount: amount,
            bookID: bookID,
            month: selectedMonth,
            currencyCode: baseCurrencyCode
        )
    }

    private func deletePendingTransaction() {
        guard let transaction = deletingTransaction else { return }
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            deletingTransaction = nil
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
            selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        case "future-month":
            selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        case "travel-book":
            if let travelBook = books.first(where: { $0.name == "旅行账本" }) {
                selectedBookID = travelBook.id.uuidString
            }
        case "budget-editor":
            DispatchQueue.main.async { openBudgetEditor() }
        default:
            break
        }
        #endif
    }
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
    @Binding var selectedMonth: Date
    let openPicker: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                monthButton(systemName: "chevron.left") { changeMonth(by: -1) }

                Button(action: openPicker) {
                    HStack(spacing: 5) {
                        Text(selectedMonth.chineseYearMonth)
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
                .accessibilityLabel("选择年月，当前\(selectedMonth.chineseYearMonth)")

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
        return min(actionWidth, max(-actionWidth, proposed))
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
                    if value.translation.width > 34 {
                        revealedSide = .edit
                        expandedTransactionID = transaction.id
                    } else if value.translation.width < -34 {
                        revealedSide = .delete
                        expandedTransactionID = transaction.id
                    } else {
                        revealedSide = nil
                        expandedTransactionID = nil
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
            Image(systemName: transaction.category?.symbolName ?? transaction.type.symbolName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(HomePalette.accent)
                .frame(width: 40, height: 40)

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
    var homeCategoryTitle: String {
        category?.name ?? type.title
    }

    var homeDetailText: String {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedNote.isEmpty ? type.title : trimmedNote
    }

    var homeAccountName: String {
        sourceAccount?.name ?? destinationAccount?.name ?? "未指定账户"
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
    var chineseYearMonth: String {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    var homeDayHeading: String {
        return formatted(
            .dateTime
                .locale(Locale(identifier: "zh_Hans_CN"))
                .month()
                .day()
        )
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
