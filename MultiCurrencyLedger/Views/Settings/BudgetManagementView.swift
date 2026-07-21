import SwiftData
import SwiftUI

struct BudgetManagementView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query private var books: [LedgerBook]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \MonthlyBudget.monthStart, order: .reverse) private var budgets: [MonthlyBudget]
    @Query private var transactions: [LedgerTransaction]
    @Query private var relations: [TransactionRelation]
    @Query private var aaSplits: [AASplit]
    @Query private var rates: [ExchangeRate]
    @State private var period: BudgetPeriod = .monthly
    @State private var date = Date.now
    @State private var editingBudget: MonthlyBudget?
    @State private var showingAdd = false
    @State private var detailRoute: BudgetDetailRoute?
    @State private var errorMessage: String?

    private var bookID: UUID? { UUID(uuidString: selectedBookID) ?? books.first?.id }

    private var periodBudgets: [MonthlyBudget] {
        guard let bookID else { return [] }
        let start = BudgetService(context: context).periodStart(period, containing: date)
        return budgets.filter {
            $0.bookID == bookID
                && $0.period == period
                && $0.currencyCode == baseCurrencyCode
                && Calendar.current.isDate($0.monthStart, inSameDayAs: start)
        }
        .sorted { ($0.categoryID == nil ? 0 : 1, $0.createdAt) < ($1.categoryID == nil ? 0 : 1, $1.createdAt) }
    }

    private var statuses: [BudgetStatus] {
        let service = BudgetStatisticsService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        return periodBudgets.map {
            service.status(
                for: $0,
                transactions: transactions,
                relations: relations,
                aaSplits: aaSplits
            )
        }
    }

    var body: some View {
        ZStack {
            HomePalette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 14) {
                        Picker("预算周期", selection: $period) {
                            ForEach(BudgetPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            DatePicker("查看日期", selection: $date, displayedComponents: .date)
                            Button("复制上期", action: copyPrevious)
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .ledgerGlassCard(cornerRadius: 24)

                    HStack {
                        Text("预算执行").font(.headline)
                        Spacer()
                        Text("\(statuses.count) 项").font(.caption).foregroundStyle(.secondary)
                    }

                    if statuses.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "gauge.with.dots.needle.0percent")
                                .font(.system(size: 28, weight: .semibold)).foregroundStyle(HomePalette.accent)
                            Text("尚未设置预算").font(.headline)
                            Text("添加总预算或分类预算，即可在这里跟踪执行进度。")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
                        .ledgerGlassCard(cornerRadius: 26)
                    } else {
                        ForEach(statuses) { status in
                            Button { openTransactions(status.budget) } label: {
                                BudgetStatusRow(
                                    status: status,
                                    categoryName: categoryName(status.budget.categoryID),
                                    currencyCode: baseCurrencyCode
                                )
                                .padding(16)
                            }
                            .buttonStyle(LedgerGlassPressStyle())
                            .ledgerGlassCard(cornerRadius: 24, tint: status.isOver ? .red : HomePalette.accent)
                            .contextMenu {
                                Button("编辑") { editingBudget = status.budget }
                                Button("删除", role: .destructive) { remove(status.budget) }
                            }
                        }
                    }

                    Button { showingAdd = true } label: {
                        Label("添加总预算或分类预算", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(HomePalette.accent)
                }
                .padding(18)
            }
        }
        .navigationTitle("预算管理")
        .sheet(isPresented: $showingAdd) {
            if let bookID {
                BudgetEditorView(
                    budget: nil,
                    bookID: bookID,
                    period: period,
                    date: date,
                    currencyCode: baseCurrencyCode,
                    categories: scopedCategories(bookID)
                )
            }
        }
        .sheet(item: $editingBudget) { budget in
            BudgetEditorView(
                budget: budget,
                bookID: budget.bookID,
                period: budget.period,
                date: budget.monthStart,
                currencyCode: budget.currencyCode,
                categories: scopedCategories(budget.bookID)
            )
        }
        .sheet(item: $detailRoute) { route in TransactionListView(initialQuery: route.query) }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
    }

    private func scopedCategories(_: UUID) -> [LedgerCategory] {
        categories.filter {
            !$0.isArchived && $0.type == .expense
        }
    }

    private func categoryName(_ id: UUID?) -> String {
        guard let id else { return AppLocalization.string( "总支出") }
        return categories.first { $0.id == id }?.name ?? AppLocalization.string( "已归档分类")
    }

    private func copyPrevious() {
        guard let bookID else { return }
        do {
            _ = try BudgetService(context: context).copyPrevious(
                bookID: bookID,
                period: period,
                containing: date,
                currencyCode: baseCurrencyCode
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ budget: MonthlyBudget) {
        do { try BudgetService(context: context).remove(budget) }
        catch { errorMessage = error.localizedDescription }
    }

    private func openTransactions(_ budget: MonthlyBudget) {
        let interval = BudgetService(context: context).interval(for: budget)
        var query = TransactionQueryState(bookID: budget.bookID)
        query.dateFilter = .custom
        query.customStartDate = interval.start
        query.customEndDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)
        query.kind = .expense
        query.categoryID = budget.categoryID
        detailRoute = BudgetDetailRoute(query: query)
    }
}

private struct BudgetDetailRoute: Identifiable {
    let id = UUID()
    let query: TransactionQueryState
}

private struct BudgetStatusRow: View {
    let status: BudgetStatus
    let categoryName: String
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(categoryName).font(.headline)
                Spacer()
                Text(
                    status.isOver
                        ? AppLocalization.string("超支")
                        : AppLocalization.string("剩余 \(MoneyFormatter.plain(status.remaining, currencyCode: currencyCode))")
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.isOver ? .red : .secondary)
            }
            ProgressView(value: min(max(status.progress, 0), 1))
                .tint(status.isOver ? .red : .accentColor)
            Text("已用 \(MoneyFormatter.plain(status.spent, currencyCode: currencyCode)) / \(MoneyFormatter.plain(status.budget.amount, currencyCode: currencyCode))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let budget: MonthlyBudget?
    let bookID: UUID
    let period: BudgetPeriod
    let date: Date
    let currencyCode: String
    let categories: [LedgerCategory]
    @State private var categoryID: UUID?
    @State private var amountText: String
    @State private var errorMessage: String?

    init(
        budget: MonthlyBudget?,
        bookID: UUID,
        period: BudgetPeriod,
        date: Date,
        currencyCode: String,
        categories: [LedgerCategory]
    ) {
        self.budget = budget
        self.bookID = bookID
        self.period = period
        self.date = date
        self.currencyCode = currencyCode
        self.categories = categories
        _categoryID = State(initialValue: budget?.categoryID)
        _amountText = State(initialValue: budget.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("范围", selection: $categoryID) {
                    Text("总支出").tag(nil as UUID?)
                    ForEach(categories) { Text($0.name).tag($0.id as UUID?) }
                }
                .disabled(budget != nil)
                HStack {
                    Text(currencyCode).foregroundStyle(.secondary)
                    TextField("预算金额", text: $amountText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle(budget == nil ? AppLocalization.string("添加预算") : AppLocalization.string("编辑预算"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        }
    }

    private func save() {
        do {
            guard let amount = DecimalParser.parse(amountText) else { throw BudgetError.invalidAmount }
            _ = try BudgetService(context: context).upsert(
                amount: amount,
                bookID: bookID,
                period: period,
                containing: date,
                currencyCode: currencyCode,
                categoryID: categoryID
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
