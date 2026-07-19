import SwiftData
import SwiftUI

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query private var accounts: [Account]
    @Query private var rates: [ExchangeRate]
    @Query(sort: \SavingsGoal.updatedAt, order: .reverse) private var goals: [SavingsGoal]
    @Query(sort: \SavingsAllocation.date, order: .reverse) private var allocations: [SavingsAllocation]

    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingBookSwitcher = false
    @State private var showingBudgets = false
    @State private var showingRecurring = false
    @State private var showingInstallments = false
    @State private var showsArchived = false
    @State private var selectedSegment = SavingsGoalListSegment.inProgress

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var bookID: UUID? { selectedBook?.id }

    private var bookGoals: [SavingsGoal] {
        guard let bookID else { return [] }
        return goals.filter { $0.bookID == bookID }
    }

    private var displayedGoals: [SavingsGoal] {
        if showsArchived {
            return bookGoals.filter { $0.status == .archived }
        }

        switch selectedSegment {
        case .inProgress:
            return bookGoals.filter { $0.status == .active || $0.status == .paused }
        case .completed:
            return bookGoals.filter { $0.status == .completed }
        }
    }

    private var summarizedGoals: [SavingsGoal] {
        showsArchived
            ? bookGoals.filter { $0.status == .archived }
            : bookGoals.filter { $0.status != .archived }
    }

    private var allocationSummary: (allocated: Decimal, netWorth: Decimal, missing: Set<String>) {
        guard let bookID else { return (0, 0, []) }
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        var allocated = Decimal.zero
        var missing = Set<String>()

        for goal in summarizedGoals {
            let amount = goalAllocations(for: goal).reduce(Decimal.zero) { $0 + $1.amount }
            if let value = valuation.value(amount, currencyCode: goal.currencyCode) { allocated += value }
            else { missing.insert(goal.currencyCode) }
        }

        let assetSummary = AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(for: accounts.filter { $0.book?.id == bookID })
        missing.formUnion(assetSummary.missingCodes)
        return (allocated, assetSummary.ownerEquity, missing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        PlanningQuickAccess(
                            openBudgets: { showingBudgets = true },
                            openRecurring: { showingRecurring = true },
                            openInstallments: { showingInstallments = true }
                        )

                        if showsArchived {
                            SavingsPageTitle(isArchivedMode: true)
                        }

                        SavingsAllocationSummaryCard(
                            allocated: allocationSummary.allocated,
                            netWorth: allocationSummary.netWorth,
                            currencyCode: baseCurrencyCode,
                            goalCount: summarizedGoals.count,
                            isArchivedMode: showsArchived,
                            missingCodes: allocationSummary.missing
                        )

                        SavingsGoalSegmentedControl(
                            selectedSegment: $selectedSegment,
                            isArchivedMode: showsArchived
                        )

                        if displayedGoals.isEmpty {
                            SavingsGoalEmptyCard(
                                isArchivedMode: showsArchived,
                                segment: selectedSegment,
                                createGoal: { showingAdd = true }
                            )
                        } else {
                            ForEach(displayedGoals) { goal in
                                NavigationLink(value: goal) {
                                    SavingsGoalCard(
                                        goal: goal,
                                        progress: SavingsGoalService(context: context).progress(
                                            for: goal,
                                            allocations: goalAllocations(for: goal)
                                        )
                                    )
                                }
                                .buttonStyle(LedgerGlassPressStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, RootEntryLayout.scrollContentClearance)
                }
            }
            .navigationTitle("计划")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingBookSwitcher = true } label: {
                        Label(selectedBook?.name ?? "选择账本", systemImage: "book.closed")
                    }
                    .accessibilityHint("切换账本")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(bookID == nil)
                    .accessibilityLabel("新建存钱目标")

                    Menu {
                        Button { showingBudgets = true } label: {
                            Label("预算管理", systemImage: "gauge.with.dots.needle.50percent")
                        }
                        Button { showingRecurring = true } label: {
                            Label("周期账单", systemImage: "repeat")
                        }
                        Button { showingInstallments = true } label: {
                            Label("分期计划", systemImage: "calendar.badge.clock")
                        }
                        Divider()
                        Button {
                            withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive) {
                                showsArchived.toggle()
                            }
                        } label: {
                            Label(
                                showsArchived ? "返回进行中" : "查看已归档",
                                systemImage: showsArchived ? "arrow.uturn.backward" : "archivebox"
                            )
                        }
                        Button { showingSettings = true } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多计划操作")
                }
            }
            .navigationDestination(for: SavingsGoal.self) { goal in
                SavingsGoalDetailView(goal: goal)
                    .toolbar(.visible, for: .navigationBar)
                    .rootEntryVisibility(.hidden, for: .savings)
            }
            .sheet(isPresented: $showingAdd) {
                if let bookID { SavingsGoalEditorView(bookID: bookID, goal: nil) }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingBookSwitcher) {
                LedgerBookSwitcherView(selectedBookID: $selectedBookID)
            }
            .sheet(isPresented: $showingBudgets) {
                NavigationStack { BudgetManagementView() }
            }
            .sheet(isPresented: $showingRecurring) {
                NavigationStack { RecurringScheduleManagementView() }
            }
            .sheet(isPresented: $showingInstallments) {
                NavigationStack { InstallmentPlanManagementView() }
            }
            .onAppear(perform: ensureSelectedBook)
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
        }
    }

    private func goalAllocations(for goal: SavingsGoal) -> [SavingsAllocation] {
        allocations.filter { $0.goal?.id == goal.id }
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }
}

private struct PlanningQuickAccess: View {
    let openBudgets: () -> Void
    let openRecurring: () -> Void
    let openInstallments: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            destination("预算", symbol: "gauge.with.dots.needle.50percent", action: openBudgets)
            Divider().frame(height: 38)
            destination("周期", symbol: "repeat", action: openRecurring)
            Divider().frame(height: 38)
            destination("分期", symbol: "calendar.badge.clock", action: openInstallments)
        }
        .padding(.vertical, 10)
        .ledgerContentSurface(cornerRadius: 22)
    }

    private func destination(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(HomePalette.accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(LedgerGlassPressStyle())
    }
}

private enum SavingsGoalListSegment: String, CaseIterable, Identifiable {
    case inProgress
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .inProgress: "未完成"
        case .completed: "已完成"
        }
    }
}

private struct SavingsPageTitle: View {
    let isArchivedMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isArchivedMode ? "已归档目标" : "存钱计划")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(isArchivedMode ? "查看已归档目标及其分配记录" : "查看目标进度和每月建议金额")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SavingsAllocationSummaryCard: View {
    let allocated: Decimal
    let netWorth: Decimal
    let currencyCode: String
    let goalCount: Int
    let isArchivedMode: Bool
    let missingCodes: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(isArchivedMode ? "已归档已存入" : "总已存入")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(MoneyFormatter.string(allocated, currencyCode: currencyCode))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: isArchivedMode ? "archivebox.fill" : "banknote.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(HomePalette.accent)
                    .frame(width: 46, height: 46)
                    .background(HomePalette.accent.opacity(0.1), in: Circle())
            }

            HStack {
                Label("当前账本 \(goalCount) 个目标", systemImage: "target")
                Spacer(minLength: 12)
                Text("净资产 \(MoneyFormatter.string(netWorth, currencyCode: currencyCode))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            if allocated > netWorth {
                SavingsGoalWarningRow(
                    text: "目标分配已超过当前净资产，请检查分配记录。",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            if !missingCodes.isEmpty {
                SavingsGoalWarningRow(
                    text: "\(missingCodes.sorted().joined(separator: "、")) 缺少汇率，暂未计入汇总。",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
        }
        .padding(20)
        .ledgerGlassCard(cornerRadius: 28, tint: HomePalette.accent)
    }
}

private struct SavingsGoalWarningRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(SavingsPagePalette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SavingsGoalSegmentedControl: View {
    @Binding var selectedSegment: SavingsGoalListSegment
    let isArchivedMode: Bool

    var body: some View {
        Group {
            if isArchivedMode {
                HStack(spacing: 9) {
                    Image(systemName: "archivebox.fill")
                    Text("仅显示已归档目标")
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomePalette.accent)
                .padding(.horizontal, 16)
                .frame(height: 48)
            } else {
                Picker("计划状态", selection: $selectedSegment) {
                    ForEach(SavingsGoalListSegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)
            }
        }
        .ledgerGlassCard(cornerRadius: 22, tint: HomePalette.accent)
    }
}

private struct SavingsGoalEmptyCard: View {
    let isArchivedMode: Bool
    let segment: SavingsGoalListSegment
    let createGoal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyIcon)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(HomePalette.accent)
                .frame(width: 52, height: 52)
                .background(HomePalette.accent.opacity(0.1), in: Circle())

            Text(emptyTitle)
                .font(.headline)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !isArchivedMode, segment == .inProgress {
                Button("新建第一个目标", action: createGoal)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)
                    .buttonStyle(LedgerGlassPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 27)
        .padding(.horizontal, 22)
        .ledgerGlassCard(cornerRadius: 26, tint: HomePalette.accent)
    }

    private var emptyIcon: String {
        isArchivedMode ? "archivebox" : (segment == .completed ? "checkmark.seal" : "target")
    }

    private var emptyTitle: String {
        if isArchivedMode { return "还没有已归档目标" }
        return segment == .completed ? "还没有完成的目标" : "设定一个存钱目标"
    }

    private var emptyMessage: String {
        if isArchivedMode { return "从目标详情将不再需要的计划归档后，会显示在这里。" }
        if segment == .completed { return "已完成的存钱计划会集中收纳在这里。" }
        return "目标分配只用于规划资金用途，不会改变真实钱包余额。"
    }
}

private struct SavingsGoalCard: View {
    let goal: SavingsGoal
    let progress: SavingsGoalProgress

    private var goalColor: Color {
        Color.ledgerHex(goal.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                Image(systemName: goal.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(goalColor)
                    .frame(width: 48, height: 48)
                    .background(goalColor.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 0.8))

                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(monthlyRecommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(goal.status.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.primary.opacity(0.78))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(statusColor.opacity(0.1), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已存入")
                    Text(MoneyFormatter.string(progress.allocated, currencyCode: goal.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("目标")
                    Text(MoneyFormatter.string(progress.target, currencyCode: goal.currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)

            ProgressView(value: min(max(progress.fraction, 0), 1))
                .tint(goalColor)

            if progress.allocated > progress.target {
                Label("已超出目标金额，可在详情中调整分配。", systemImage: "exclamationmark.circle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SavingsPagePalette.warning)
            }
        }
        .padding(18)
        .ledgerGlassCard(cornerRadius: 26, tint: goalColor)
    }

    private var monthlyRecommendation: String {
        if goal.status == .completed { return "目标已完成" }
        if goal.status == .paused { return "计划已暂停" }
        if goal.status == .archived { return "目标已归档" }
        if let amount = progress.recommendedMonthlyAmount {
            return "建议每月 \(MoneyFormatter.string(amount, currencyCode: goal.currencyCode))"
        }
        return goal.targetDate == nil ? "未设置目标日期" : "已达成当前目标"
    }

    private var statusColor: Color {
        switch goal.status {
        case .active: goalColor
        case .paused: .orange
        case .completed: .green
        case .archived: .secondary
        }
    }
}

private enum SavingsPagePalette {
    static let warning = Color(red: 0.58, green: 0.27, blue: 0.03)
}

private struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsAllocation.date, order: .reverse) private var allocations: [SavingsAllocation]
    @Query(sort: \Account.name) private var accounts: [Account]
    let goal: SavingsGoal
    @State private var showingAllocation = false
    @State private var showingEdit = false
    @State private var errorMessage: String?

    private var goalAllocations: [SavingsAllocation] {
        allocations.filter { $0.goal?.id == goal.id }
    }
    private var progress: SavingsGoalProgress {
        SavingsGoalService(context: context).progress(for: goal, allocations: goalAllocations)
    }
    private var goalColor: Color { Color.ledgerHex(goal.colorHex) }

    var body: some View {
        ZStack {
            HomePalette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 16) {
                        Image(systemName: goal.symbolName)
                            .font(.system(size: 26, weight: .semibold)).foregroundStyle(goalColor)
                            .frame(width: 56, height: 56).background(goalColor.opacity(0.12), in: Circle())
                        Text(MoneyFormatter.string(progress.allocated, currencyCode: goal.currencyCode))
                            .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("已分配 / 目标 \(MoneyFormatter.string(progress.target, currencyCode: goal.currencyCode))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ProgressView(value: min(max(progress.fraction, 0), 1)).tint(goalColor)
                    }
                    .frame(maxWidth: .infinity).padding(22)
                    .ledgerGlassCard(cornerRadius: 30, tint: goalColor)

                    HStack(spacing: 10) {
                        SavingsMetricCard(title: "还需", value: MoneyFormatter.string(progress.remaining, currencyCode: goal.currencyCode), tint: goalColor)
                        if let amount = progress.recommendedMonthlyAmount {
                            SavingsMetricCard(title: "建议每月", value: MoneyFormatter.string(amount, currencyCode: goal.currencyCode), tint: goalColor)
                        } else if let date = goal.targetDate {
                            SavingsMetricCard(title: "目标日期", value: date.formatted(date: .abbreviated, time: .omitted), tint: goalColor)
                        }
                    }

                    Button { showingAllocation = true } label: {
                        Text("增加或取出分配")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(goalColor)
                    .disabled(goal.status == .archived)

                    HStack {
                        Text("分配历史").font(.headline)
                        Spacer()
                        Text("\(goalAllocations.count) 笔").font(.caption).foregroundStyle(.secondary)
                    }

                    if goalAllocations.isEmpty {
                        Text("暂无分配记录")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 26)
                            .ledgerGlassCard(cornerRadius: 22, tint: goalColor)
                    } else {
                        ForEach(goalAllocations) { allocation in
                            HStack(spacing: 12) {
                                Image(systemName: allocation.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                    .font(.title3).foregroundStyle(allocation.amount >= 0 ? goalColor : .orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(allocation.note ?? (allocation.amount > 0 ? "增加分配" : "取出分配"))
                                        .font(.subheadline.weight(.semibold))
                                    Text(allocation.date, format: .dateTime.year().month().day())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(MoneyFormatter.string(allocation.amount, currencyCode: goal.currencyCode))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }
                            .padding(15).ledgerGlassCard(cornerRadius: 20, tint: goalColor)
                            .contextMenu { Button("删除", role: .destructive) { delete(allocation) } }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(goal.name)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            Menu {
                Button("编辑目标") { showingEdit = true }
                ForEach(SavingsGoalStatus.allCases.filter { $0 != goal.status }) { status in
                    Button(status.title) { setStatus(status) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $showingAllocation) {
            SavingsAllocationEditorView(
                goal: goal,
                accounts: accounts.filter { $0.book?.id == goal.bookID && !$0.isArchived }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingEdit) {
            SavingsGoalEditorView(bookID: goal.bookID, goal: goal)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func setStatus(_ status: SavingsGoalStatus) {
        do { try SavingsGoalService(context: context).setStatus(status, goal: goal) }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ allocation: SavingsAllocation) {
        do { try SavingsGoalService(context: context).delete(allocation) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SavingsMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .ledgerGlassCard(cornerRadius: 20, tint: tint)
    }
}

private struct SavingsGoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let bookID: UUID
    let goal: SavingsGoal?
    @State private var name: String
    @State private var targetText: String
    @State private var currencyCode: String
    @State private var hasDate: Bool
    @State private var targetDate: Date
    @State private var errorMessage: String?

    init(bookID: UUID, goal: SavingsGoal?) {
        self.bookID = bookID
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _targetText = State(initialValue: goal.map { NSDecimalNumber(decimal: $0.targetAmount).stringValue } ?? "")
        _currencyCode = State(initialValue: goal?.currencyCode ?? SupportedCurrency.CNY.rawValue)
        _hasDate = State(initialValue: goal?.targetDate != nil)
        _targetDate = State(initialValue: goal?.targetDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("目标名称", text: $name)
                TextField("目标金额", text: $targetText).keyboardType(.decimalPad)
                Picker("币种", selection: $currencyCode) {
                    ForEach(SupportedCurrency.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .disabled(goal != nil)
                Toggle("设置目标日期", isOn: $hasDate)
                if hasDate { DatePicker("目标日期", selection: $targetDate, displayedComponents: .date) }
            }
            .navigationTitle(goal == nil ? "新建目标" : "编辑目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        do {
            guard let target = DecimalParser.parse(targetText) else { throw SavingsGoalError.invalidTarget }
            let service = SavingsGoalService(context: context)
            if let goal {
                try service.update(goal, name: name, targetAmount: target, targetDate: hasDate ? targetDate : nil)
            } else {
                try service.create(
                    bookID: bookID,
                    name: name,
                    targetAmount: target,
                    currencyCode: currencyCode,
                    targetDate: hasDate ? targetDate : nil
                )
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SavingsAllocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let goal: SavingsGoal
    let accounts: [Account]
    @State private var isWithdrawal = false
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var accountID: UUID?
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("操作", selection: $isWithdrawal) {
                    Text("增加").tag(false)
                    Text("取出").tag(true)
                }
                .pickerStyle(.segmented)
                TextField("金额", text: $amountText).keyboardType(.decimalPad)
                DatePicker("日期", selection: $date)
                Picker("资金所在账户（可选）", selection: $accountID) {
                    Text("不关联").tag(nil as UUID?)
                    ForEach(accounts) { Text($0.name).tag($0.id as UUID?) }
                }
                TextField("备注", text: $note)
                Text("这里只记录资金用途分配，不会扣减或增加任何钱包余额。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(isWithdrawal ? "取出分配" : "增加分配")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        do {
            guard let amount = DecimalParser.parse(amountText), amount > 0 else {
                throw SavingsGoalError.invalidAllocation
            }
            _ = try SavingsGoalService(context: context).allocate(
                isWithdrawal ? -amount : amount,
                to: goal,
                date: date,
                sourceAccountID: accountID,
                note: note
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
