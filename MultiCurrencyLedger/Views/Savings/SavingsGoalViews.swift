import SwiftData
import SwiftUI

struct SavingsGoalListView: View {
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @Query private var books: [LedgerBook]
    @Query private var accounts: [Account]
    @Query private var rates: [ExchangeRate]
    @Query(sort: \SavingsGoal.updatedAt, order: .reverse) private var goals: [SavingsGoal]
    @Query(sort: \SavingsAllocation.date, order: .reverse) private var allocations: [SavingsAllocation]
    @State private var showingAdd = false
    @State private var showsArchived = false

    private var bookID: UUID? { UUID(uuidString: selectedBookID) ?? books.first?.id }
    private var activeGoals: [SavingsGoal] {
        guard let bookID else { return [] }
        return goals.filter { $0.bookID == bookID && (showsArchived || $0.status != .archived) }
    }

    private var activeUnarchivedGoals: [SavingsGoal] {
        guard let bookID else { return [] }
        return goals.filter { $0.bookID == bookID && $0.status != .archived }
    }

    private var allocationSummary: (allocated: Decimal, netWorth: Decimal, missing: Set<String>) {
        guard let bookID else { return (0, 0, []) }
        let valuation = ValuationService(baseCurrencyCode: baseCurrencyCode, rates: rates)
        var allocated = Decimal.zero
        var missing = Set<String>()
        for goal in activeUnarchivedGoals {
            let amount = allocations.filter { $0.goal?.id == goal.id }.reduce(Decimal.zero) { $0 + $1.amount }
            if let value = valuation.value(amount, currencyCode: goal.currencyCode) { allocated += value }
            else { missing.insert(goal.currencyCode) }
        }
        let netWorth = AssetSummaryService(baseCurrencyCode: baseCurrencyCode, rates: rates)
            .summary(for: accounts.filter { $0.book?.id == bookID }).ownerEquity
        return (allocated, netWorth, missing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                if activeGoals.isEmpty {
                    ContentUnavailableView {
                        Label("设定一个存钱目标", systemImage: "target")
                    } description: {
                        Text("目标分配不会改变真实钱包余额，也不会计入支出或预算。")
                    } actions: {
                        Button("新建目标") { showingAdd = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            SavingsAllocationSummaryCard(
                                allocated: allocationSummary.allocated,
                                netWorth: allocationSummary.netWorth,
                                currencyCode: baseCurrencyCode,
                                missingCodes: allocationSummary.missing
                            )
                            ForEach(activeGoals) { goal in
                                NavigationLink(value: goal) {
                                    SavingsGoalCard(
                                        goal: goal,
                                        progress: SavingsGoalServicePreview.progress(
                                            goal: goal,
                                            allocations: allocations
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(18)
                        .padding(.bottom, 90)
                    }
                }
            }
            .navigationTitle("存钱目标")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsArchived.toggle() } label: {
                        Image(systemName: showsArchived ? "archivebox.fill" : "archivebox")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Label("新建", systemImage: "plus") }
                        .disabled(bookID == nil)
                }
            }
            .navigationDestination(for: SavingsGoal.self) { SavingsGoalDetailView(goal: $0) }
            .sheet(isPresented: $showingAdd) {
                if let bookID { SavingsGoalEditorView(bookID: bookID, goal: nil) }
            }
        }
    }
}

private struct SavingsAllocationSummaryCard: View {
    let allocated: Decimal
    let netWorth: Decimal
    let currencyCode: String
    let missingCodes: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("目标已分配", value: MoneyFormatter.plain(allocated, currencyCode: currencyCode))
            LabeledContent("当前净资产参考", value: MoneyFormatter.plain(netWorth, currencyCode: currencyCode))
            if allocated > netWorth {
                Label("目标分配已超过当前净资产，请检查分配记录。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !missingCodes.isEmpty {
                Text("\(missingCodes.sorted().joined(separator: "、")) 缺少汇率，未计入汇总。")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("目标分配仅说明资金用途，净资产不会被二次扣减。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(HomePalette.glassBorder, lineWidth: 0.8))
    }
}

private enum SavingsGoalServicePreview {
    static func progress(goal: SavingsGoal, allocations: [SavingsAllocation]) -> SavingsGoalProgress {
        let allocated = allocations.filter { $0.goal?.id == goal.id }.reduce(Decimal.zero) { $0 + $1.amount }
        let remaining = max(0, goal.targetAmount - allocated)
        let fraction = goal.targetAmount > 0
            ? NSDecimalNumber(decimal: allocated / goal.targetAmount).doubleValue
            : 0
        return SavingsGoalProgress(
            allocated: allocated,
            target: goal.targetAmount,
            remaining: remaining,
            fraction: fraction,
            recommendedMonthlyAmount: nil
        )
    }
}

private struct SavingsGoalCard: View {
    let goal: SavingsGoal
    let progress: SavingsGoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: goal.symbolName)
                    .font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading) {
                    Text(goal.name).font(.headline)
                    Text(goal.status.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            ProgressView(value: min(max(progress.fraction, 0), 1))
            HStack {
                Text("已分配 \(MoneyFormatter.plain(progress.allocated, currencyCode: goal.currencyCode))")
                Spacer()
                Text("目标 \(MoneyFormatter.plain(progress.target, currencyCode: goal.currencyCode))")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(HomePalette.glassBorder, lineWidth: 0.8))
    }
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

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: min(max(progress.fraction, 0), 1))
                    LabeledContent("已分配", value: MoneyFormatter.plain(progress.allocated, currencyCode: goal.currencyCode))
                    LabeledContent("还需", value: MoneyFormatter.plain(progress.remaining, currencyCode: goal.currencyCode))
                    if let amount = progress.recommendedMonthlyAmount {
                        LabeledContent("建议每月", value: MoneyFormatter.plain(amount, currencyCode: goal.currencyCode))
                    }
                    if let date = goal.targetDate {
                        LabeledContent("目标日期", value: date.formatted(date: .long, time: .omitted))
                    }
                }
            }
            Section {
                Button("增加或取出分配") { showingAllocation = true }
                    .disabled(goal.status == .archived)
            }
            Section("分配历史") {
                if goalAllocations.isEmpty {
                    Text("暂无分配记录").foregroundStyle(.secondary)
                } else {
                    ForEach(goalAllocations) { allocation in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(allocation.note ?? (allocation.amount > 0 ? "增加分配" : "取出分配"))
                                Text(allocation.date, format: .dateTime.year().month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.plain(allocation.amount, currencyCode: goal.currencyCode))
                                .monospacedDigit()
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { delete(allocation) }
                        }
                    }
                }
            }
        }
        .navigationTitle(goal.name)
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
        }
        .sheet(isPresented: $showingEdit) { SavingsGoalEditorView(bookID: goal.bookID, goal: goal) }
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
