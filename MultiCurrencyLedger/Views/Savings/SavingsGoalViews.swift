import SwiftData
import SwiftUI

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \SavingsGoal.updatedAt, order: .reverse) private var goals: [SavingsGoal]
    @Query(sort: \SavingsAllocation.date, order: .reverse) private var allocations: [SavingsAllocation]
    @Query(sort: \RepaymentReminder.dueDate) private var reminders: [RepaymentReminder]

    @State private var showingPlanChooser = false
    @State private var showingGoalEditor = false
    @State private var showingReminderEditor = false
    @State private var allocationGoal: SavingsGoal?
    @State private var editingReminder: RepaymentReminder?
    @State private var errorMessage: String?

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var visibleGoals: [SavingsGoal] {
        goals.filter { $0.isGloballyVisible && $0.status != .archived }
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived && !$0.allWallets.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        planSectionTitle("存钱目标", count: visibleGoals.count)

                        if visibleGoals.isEmpty {
                            PlanEmptyCard(
                                title: AppLocalization.string("还没有存钱目标"),
                                message: AppLocalization.string("建立目标后，可通过“存入”记录资金用途分配。"),
                                symbol: "target"
                            )
                        } else {
                            ForEach(visibleGoals) { goal in
                                PlanSavingsGoalCard(
                                    goal: goal,
                                    progress: SavingsGoalService(context: context).progress(
                                        for: goal,
                                        allocations: goalAllocations(for: goal)
                                    ),
                                    allocate: { allocationGoal = goal }
                                )
                            }
                        }

                        planSectionTitle("还款提醒", count: reminders.count)
                            .padding(.top, 8)

                        if reminders.isEmpty {
                            PlanEmptyCard(
                                title: AppLocalization.string("还没有还款提醒"),
                                message: AppLocalization.string("提醒只记录待还状态，不会自动记账或注册系统通知。"),
                                symbol: "calendar.badge.clock"
                            )
                        } else {
                            ForEach(reminders) { reminder in
                                RepaymentReminderCard(
                                    reminder: reminder,
                                    accountName: accountName(for: reminder.accountID),
                                    toggleCompletion: { toggleCompletion(reminder) },
                                    edit: { editingReminder = reminder }
                                )
                                .contextMenu {
                                    Button("删除提醒", role: .destructive) { delete(reminder) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, RootEntryLayout.scrollContentClearance)
                }
            }
            .navigationTitle("计划")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingPlanChooser = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("新增计划")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .disabled(selectedBook == nil || activeAccounts.isEmpty && books.isEmpty)
                    .accessibilityHint("选择新增存钱目标或还款提醒")
                }
            }
            .navigationDestination(for: SavingsGoal.self) { goal in
                SavingsGoalDetailView(goal: goal)
                    .toolbar(.visible, for: .navigationBar)
                    .rootEntryVisibility(.hidden, for: .savings)
            }
            .confirmationDialog("新增计划", isPresented: $showingPlanChooser) {
                Button("存钱目标") { showingGoalEditor = true }
                Button("还款提醒") { showingReminderEditor = true }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showingGoalEditor) {
                if let bookID = selectedBook?.id {
                    SavingsGoalEditorView(bookID: bookID, goal: nil)
                }
            }
            .sheet(isPresented: $showingReminderEditor) {
                RepaymentReminderEditorView(accounts: activeAccounts, reminder: nil)
            }
            .sheet(item: $allocationGoal) { goal in
                SavingsAllocationEditorView(goal: goal, accounts: activeAccounts)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingReminder) { reminder in
                RepaymentReminderEditorView(accounts: activeAccounts, reminder: reminder)
            }
            .onAppear(perform: ensureSelectedBook)
            .onChange(of: books.count) { _, _ in ensureSelectedBook() }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? AppLocalization.string("未知错误"))
            }
        }
    }

    private func planSectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            Text("\(count) 项").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func goalAllocations(for goal: SavingsGoal) -> [SavingsAllocation] {
        allocations.filter { $0.goal?.id == goal.id }
    }

    private func accountName(for accountID: UUID) -> String {
        accounts.first(where: { $0.id == accountID })?.name ?? AppLocalization.string("已删除账户")
    }

    private func toggleCompletion(_ reminder: RepaymentReminder) {
        do {
            try RepaymentReminderService(context: context).setCompleted(
                !reminder.isCompleted,
                reminder: reminder
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ reminder: RepaymentReminder) {
        do {
            try RepaymentReminderService(context: context).delete(reminder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureSelectedBook() {
        guard let first = books.first else { return }
        if !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }
    }
}

private struct PlanSavingsGoalCard: View {
    let goal: SavingsGoal
    let progress: SavingsGoalProgress
    let allocate: () -> Void

    private var tint: Color { Color.ledgerHex(goal.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: goal) {
                HStack(spacing: 12) {
                    Image(systemName: goal.symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.name).font(.headline).foregroundStyle(.primary)
                        Text(targetDateText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(LedgerGlassPressStyle())

            HStack(alignment: .firstTextBaseline) {
                Text(MoneyFormatter.string(progress.allocated, currencyCode: goal.currencyCode))
                    .font(.title3.bold()).monospacedDigit()
                Text("/ \(MoneyFormatter.string(progress.target, currencyCode: goal.currencyCode))")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.bold()).foregroundStyle(tint)
            }

            ProgressView(value: min(max(progress.fraction, 0), 1)).tint(tint)

            Button(action: allocate) {
                Label("存入", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .disabled(goal.status == .completed || goal.status == .paused)
        }
        .padding(18)
        .ledgerGlassCard(cornerRadius: 26, tint: tint)
    }

    private var targetDateText: String {
        guard let date = goal.targetDate else { return AppLocalization.string( "未设置目标日期") }
        return AppLocalization.string( "目标日期 \(date.formatted(date: .abbreviated, time: .omitted))")
    }
}

private struct RepaymentReminderCard: View {
    let reminder: RepaymentReminder
    let accountName: String
    let toggleCompletion: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Text(accountName).font(.headline).foregroundStyle(.primary)
                        if reminder.isCompleted {
                            Text("已完成")
                                .font(.caption2.bold()).foregroundStyle(.green)
                        }
                    }
                    Text("待还 \(MoneyFormatter.string(reminder.outstandingAmount, currencyCode: reminder.currencyCode))")
                        .font(.title3.bold()).foregroundStyle(.primary).monospacedDigit()
                    HStack(spacing: 8) {
                        Text(reminder.dueDate, format: .dateTime.year().month().day())
                        Text(remainingDaysText)
                    }
                    .font(.caption).foregroundStyle(reminder.isCompleted ? .secondary : dueColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(LedgerGlassPressStyle())

            Button(action: toggleCompletion) {
                Image(systemName: reminder.isCompleted ? "checkmark" : "circle")
                    .font(.headline.bold())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .tint(reminder.isCompleted ? .green : HomePalette.accent)
            .accessibilityLabel(
                reminder.isCompleted
                    ? AppLocalization.string("恢复未完成")
                    : AppLocalization.string("标记为已完成")
            )
        }
        .padding(18)
        .ledgerGlassCard(cornerRadius: 26, tint: reminder.isCompleted ? .green : HomePalette.accent)
        .opacity(reminder.isCompleted ? 0.72 : 1)
    }

    private var remainingDays: Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: reminder.dueDate)
        ).day ?? 0
    }

    private var remainingDaysText: String {
        if reminder.isCompleted { return AppLocalization.string( "已完成") }
        if remainingDays == 0 { return AppLocalization.string( "今天到期") }
        if remainingDays > 0 { return AppLocalization.string( "剩余 \(remainingDays) 天") }
        return AppLocalization.string( "已逾期 \(-remainingDays) 天")
    }

    private var dueColor: Color { remainingDays < 0 ? .red : .secondary }
}

private struct PlanEmptyCard: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(HomePalette.accent)
                .frame(width: 42, height: 42)
                .background(HomePalette.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ledgerGlassCard(cornerRadius: 22, tint: HomePalette.accent)
    }
}

private struct RepaymentReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let accounts: [Account]
    let reminder: RepaymentReminder?
    @State private var accountID: UUID?
    @State private var currencyCode: String
    @State private var amountText: String
    @State private var dueDate: Date
    @State private var errorMessage: String?

    init(accounts: [Account], reminder: RepaymentReminder?) {
        self.accounts = accounts
        self.reminder = reminder
        let initialAccount = reminder.flatMap { item in accounts.first { $0.id == item.accountID } } ?? accounts.first
        _accountID = State(initialValue: initialAccount?.id)
        _currencyCode = State(initialValue: reminder?.currencyCode ?? initialAccount?.allWallets.first?.currencyCode ?? "CNY")
        _amountText = State(initialValue: reminder.map { NSDecimalNumber(decimal: $0.outstandingAmount).stringValue } ?? "")
        _dueDate = State(initialValue: reminder?.dueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
    }

    private var selectedAccount: Account? {
        accounts.first { $0.id == accountID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("还款账户", selection: $accountID) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(account.id as UUID?)
                    }
                }
                Picker("币种", selection: $currencyCode) {
                    ForEach(selectedAccount?.allWallets ?? []) { wallet in
                        Text(wallet.currencyCode).tag(wallet.currencyCode)
                    }
                }
                TextField("待还金额", text: $amountText).keyboardType(.decimalPad)
                DatePicker("还款日期", selection: $dueDate, displayedComponents: .date)
                Text("完成提醒只更新提醒状态，不会创建交易或系统通知。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(
                reminder == nil
                    ? AppLocalization.string("新建还款提醒")
                    : AppLocalization.string("编辑还款提醒")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onChange(of: accountID) { _, _ in
                if let first = selectedAccount?.allWallets.first,
                   !selectedAccount!.allWallets.contains(where: { $0.currencyCode == currencyCode }) {
                    currencyCode = first.currencyCode
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        }
    }

    private func save() {
        do {
            guard let accountID else { throw RepaymentReminderError.invalidAccount }
            guard let amount = DecimalParser.parse(amountText) else { throw RepaymentReminderError.invalidAmount }
            let service = RepaymentReminderService(context: context)
            if let reminder {
                try service.update(
                    reminder,
                    accountID: accountID,
                    currencyCode: currencyCode,
                    outstandingAmount: amount,
                    dueDate: dueDate
                )
            } else {
                try service.create(
                    accountID: accountID,
                    currencyCode: currencyCode,
                    outstandingAmount: amount,
                    dueDate: dueDate
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
        case .inProgress: AppLocalization.string( "未完成")
        case .completed: AppLocalization.string( "已完成")
        }
    }
}

private struct SavingsPageTitle: View {
    let isArchivedMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isArchivedMode ? AppLocalization.string("已归档目标") : AppLocalization.string("存钱计划"))
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(
                isArchivedMode
                    ? AppLocalization.string("查看已归档目标及其分配记录")
                    : AppLocalization.string("查看目标进度和每月建议金额")
            )
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
                    Text(isArchivedMode ? AppLocalization.string("已归档已存入") : AppLocalization.string("总已存入"))
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
        if isArchivedMode { return AppLocalization.string( "还没有已归档目标") }
        return segment == .completed
            ? AppLocalization.string( "还没有完成的目标")
            : AppLocalization.string( "设定一个存钱目标")
    }

    private var emptyMessage: String {
        if isArchivedMode { return AppLocalization.string( "从目标详情将不再需要的计划归档后，会显示在这里。") }
        if segment == .completed { return AppLocalization.string( "已完成的存钱计划会集中收纳在这里。") }
        return AppLocalization.string( "目标分配只用于规划资金用途，不会改变真实钱包余额。")
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
        if goal.status == .completed { return AppLocalization.string( "目标已完成") }
        if goal.status == .paused { return AppLocalization.string( "计划已暂停") }
        if goal.status == .archived { return AppLocalization.string( "目标已归档") }
        if let amount = progress.recommendedMonthlyAmount {
            return AppLocalization.string( "建议每月 \(MoneyFormatter.string(amount, currencyCode: goal.currencyCode))")
        }
        return goal.targetDate == nil
            ? AppLocalization.string( "未设置目标日期")
            : AppLocalization.string( "已达成当前目标")
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
                        SavingsMetricCard(title: AppLocalization.string("还需"), value: MoneyFormatter.string(progress.remaining, currencyCode: goal.currencyCode), tint: goalColor)
                        if let amount = progress.recommendedMonthlyAmount {
                            SavingsMetricCard(title: AppLocalization.string("建议每月"), value: MoneyFormatter.string(amount, currencyCode: goal.currencyCode), tint: goalColor)
                        } else if let date = goal.targetDate {
                            SavingsMetricCard(title: AppLocalization.string("目标日期"), value: date.formatted(date: .abbreviated, time: .omitted), tint: goalColor)
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
                                    Text(
                                        allocation.note
                                            ?? (allocation.amount > 0
                                                ? AppLocalization.string("增加分配")
                                                : AppLocalization.string("取出分配"))
                                    )
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
                accounts: accounts.filter { !$0.isArchived }
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
        )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
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
            .navigationTitle(goal == nil ? AppLocalization.string("新建目标") : AppLocalization.string("编辑目标"))
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
            .navigationTitle(isWithdrawal ? AppLocalization.string("取出分配") : AppLocalization.string("增加分配"))
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
