import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("profileImagePath") private var profileImagePath = ""
    @AppStorage("selectedBookID") private var selectedBookID = ""

    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query private var rates: [ExchangeRate]
    @Query(sort: \MonthlyBudget.monthStart, order: .reverse) private var budgets: [MonthlyBudget]

    let addTransaction: () -> Void

    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)
    ) ?? .now
    @State private var showingSettings = false
    @State private var showingAddAsset = false
    @State private var showingBookSwitcher = false
    @State private var showingBookManagement = false
    @State private var showingMonthPicker = false
    @State private var showingBudgetEditor = false
    @State private var appliedPreviewState = false

    init(addTransaction: @escaping () -> Void = {}) {
        self.addTransaction = addTransaction
    }

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var selectedBookTransactions: [LedgerTransaction] {
        guard let bookID = selectedBook?.id else { return [] }
        return transactions.filter {
            $0.sourceAccount?.book?.id == bookID || $0.destinationAccount?.book?.id == bookID
        }
    }

    private var selectedMonthTransactions: [LedgerTransaction] {
        selectedBookTransactions.filter {
            Calendar.current.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var currentBudget: MonthlyBudget? {
        guard let bookID = selectedBook?.id else { return nil }
        return budgets.first {
            $0.bookID == bookID
                && $0.currencyCode == baseCurrencyCode
                && Calendar.current.isDate($0.monthStart, equalTo: .now, toGranularity: .month)
        }
    }

    private var monthlySummary: MonthlySummaryResult {
        MonthlySummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(
                for: selectedBookTransactions,
                month: .now,
                budget: currentBudget?.amount
            )
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
                    LazyVStack(spacing: 12) {
                        HomeHeader(
                            profileImagePath: profileImagePath,
                            bookName: selectedBook?.name ?? "选择账本",
                            openProfile: { showingSettings = true },
                            switchBook: { showingBookSwitcher = true },
                            manageBooks: { showingBookManagement = true },
                            addAsset: { showingAddAsset = true }
                        )

                        MonthlyOverviewCard(
                            currencyCode: baseCurrencyCode,
                            summary: monthlySummary,
                            setBudget: openBudgetEditor
                        )

                        MonthNavigator(
                            selectedMonth: $selectedMonth,
                            openPicker: { showingMonthPicker = true }
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
                            baseCurrencyCode: baseCurrencyCode,
                            rates: rates,
                            addTransaction: addTransaction
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 104)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: LedgerTransaction.self) {
                TransactionDetailView(transaction: $0)
                    .toolbar(.visible, for: .navigationBar)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingAddAsset) {
                AddAccountView(book: selectedBook)
            }
            .sheet(isPresented: $showingBookSwitcher) {
                LedgerBookSwitcherView(selectedBookID: $selectedBookID)
            }
            .sheet(isPresented: $showingBookManagement) {
                LedgerBookManagementView()
            }
            .sheet(isPresented: $showingMonthPicker) {
                MonthPickerView(selectedMonth: $selectedMonth)
            }
            .sheet(isPresented: $showingBudgetEditor) {
                BudgetEditorSheet(
                    month: .now,
                    currencyCode: baseCurrencyCode,
                    currentAmount: currentBudget?.amount,
                    save: saveBudget
                )
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
        showingBudgetEditor = true
    }

    private func saveBudget(_ amount: Decimal) throws {
        guard let bookID = selectedBook?.id else { throw ValidationError("请先创建账本") }
        _ = try MonthlyBudgetService(context: context).upsert(
            amount: amount,
            bookID: bookID,
            month: .now,
            currencyCode: baseCurrencyCode
        )
    }

    private func applyPreviewStateIfNeeded() {
        #if DEBUG
        guard !appliedPreviewState else { return }
        appliedPreviewState = true
        switch ProcessInfo.processInfo.environment["HOME_PREVIEW_STATE"] {
        case "book-switcher":
            DispatchQueue.main.async { showingBookSwitcher = true }
        case "previous-month":
            selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        case "future-month":
            selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        case "travel-book":
            if let travelBook = books.first(where: { $0.name == "旅行账本" }) {
                selectedBookID = travelBook.id.uuidString
            }
        case "budget-editor":
            DispatchQueue.main.async { showingBudgetEditor = true }
        default:
            break
        }
        #endif
    }
}

enum HomePalette {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.045, green: 0.059, blue: 0.078, alpha: 1)
            : UIColor(red: 0.957, green: 0.969, blue: 0.978, alpha: 1)
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
}

private struct HomeHeader: View {
    let profileImagePath: String
    let bookName: String
    let openProfile: () -> Void
    let switchBook: () -> Void
    let manageBooks: () -> Void
    let addAsset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openProfile) {
                ProfileAvatar(path: profileImagePath)
            }
            .buttonStyle(PressableGlassButtonStyle())
            .accessibilityLabel("个人中心")

            Spacer(minLength: 4)

            Button(action: switchBook) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(bookName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: 200)
                .frame(height: 40)
                .background(Color.accentColor.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("当前账本：\(bookName)，点击切换")

            Spacer(minLength: 4)

            Menu {
                Button(action: switchBook) {
                    Label("切换账本", systemImage: "arrow.left.arrow.right")
                }
                Button(action: manageBooks) {
                    Label("管理账本", systemImage: "slider.horizontal.3")
                }
                Divider()
                Button(action: addAsset) {
                    Label("新增资产", systemImage: "creditcard.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().stroke(HomePalette.glassBorder, lineWidth: 0.8))
            }
            .buttonStyle(PressableGlassButtonStyle())
            .accessibilityLabel("更多账本操作")
        }
        .frame(height: 50)
    }
}

private struct ProfileAvatar: View {
    let path: String

    private var image: UIImage? {
        guard !path.isEmpty else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor, Color.accentColor.opacity(0.14))
                    .padding(3)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .background(.thinMaterial, in: Circle())
        .overlay(Circle().stroke(HomePalette.glassBorder, lineWidth: 1))
    }
}

private struct MonthNavigator: View {
    @Binding var selectedMonth: Date
    let openPicker: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            monthButton(systemName: "chevron.left") { changeMonth(by: -1) }

            Button(action: openPicker) {
                HStack(spacing: 5) {
                    Text(selectedMonth.chineseYearMonth)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 126, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择年月，当前\(selectedMonth.chineseYearMonth)")

            monthButton(systemName: "chevron.right") { changeMonth(by: 1) }
        }
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(HomePalette.glassBorder, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.035), radius: 12, y: 5)
    }

    private func monthButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(by offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) else { return }
        withAnimation(.snappy(duration: 0.24)) { selectedMonth = month }
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
        rates: [ExchangeRate]
    ) -> (income: Decimal, expense: Decimal) {
        let result = MonthlySummaryService(
            baseCurrencyCode: baseCurrencyCode,
            rates: rates
        ).summary(for: transactions, month: date)
        return (result.income, result.expense)
    }
}

private struct DailyRecordCards: View {
    let groups: [TransactionDayGroup]
    let emptyTitle: String
    let emptyMessage: String
    let showAddAction: Bool
    let baseCurrencyCode: String
    let rates: [ExchangeRate]
    let addTransaction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if groups.isEmpty {
                EmptyRecordsView(
                    title: emptyTitle,
                    message: emptyMessage,
                    addTransaction: showAddAction ? addTransaction : nil
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(HomePalette.glassBorder, lineWidth: 0.8)
                }
            } else {
                ForEach(groups) { group in
                    DailyRecordCard(
                        group: group,
                        baseCurrencyCode: baseCurrencyCode,
                        rates: rates
                    )
                }
            }
        }
    }
}

private struct DailyRecordCard: View {
    let group: TransactionDayGroup
    let baseCurrencyCode: String
    let rates: [ExchangeRate]

    private var cashFlow: (income: Decimal, expense: Decimal) {
        group.cashFlow(baseCurrencyCode: baseCurrencyCode, rates: rates)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(group.date.homeDayHeading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Text("收 \(MoneyFormatter.currencySymbol(currencyCode: baseCurrencyCode))\(MoneyFormatter.plain(cashFlow.income, currencyCode: baseCurrencyCode))")
                    Text("支 \(MoneyFormatter.currencySymbol(currencyCode: baseCurrencyCode))\(MoneyFormatter.plain(cashFlow.expense, currencyCode: baseCurrencyCode))")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 38)

            Divider().padding(.leading, 16)

            ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, transaction in
                NavigationLink(value: transaction) {
                    HomeTransactionRow(transaction: transaction)
                }
                .buttonStyle(.plain)

                if index < group.transactions.count - 1 {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HomePalette.glassBorder, lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 15, y: 7)
    }
}

struct HomeTransactionRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.symbolName ?? transaction.type.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(transaction.homeTint)
                .frame(width: 38, height: 38)
                .background(transaction.homeTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.homeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(transaction.homeRowSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(transaction.summaryAmount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

extension LedgerTransaction {
    var homeTitle: String {
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note
        }
        return category?.name ?? type.title
    }

    var homeRowSubtitle: String {
        "\(category?.name ?? type.title) · \(date.formatted(.dateTime.hour().minute()))"
    }

    var homeTint: Color {
        switch type {
        case .expense: HomePalette.expense
        case .income: .green
        case .transfer: .blue
        case .exchange: .teal
        case .adjustment: .orange
        }
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
}
