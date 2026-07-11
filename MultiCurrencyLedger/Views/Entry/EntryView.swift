import SwiftData
import SwiftUI

struct EntryView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]
    @State private var kind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var destinationAmountText = ""
    @State private var sourceWalletID: UUID?
    @State private var destinationWalletID: UUID?
    @State private var categoryID: UUID?
    @State private var date = Date.now
    @State private var note = ""
    @State private var adjustmentDirection: AdjustmentDirection = .increase
    @State private var adjustmentReason = "手动校准"
    @State private var includesFee = false
    @State private var feeText = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showingNegativeWarning = false

    private let adjustmentReasons = ["银行利息", "投资收益", "投资亏损", "手动校准", "其他"]

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var allWallets: [CurrencyWallet] {
        guard let bookID = selectedBook?.id else { return [] }
        let scopedAccounts = accounts.filter { $0.book?.id == bookID }
        return scopedAccounts.flatMap(\.enabledWallets).sorted {
            let left = $0.account?.name ?? ""
            let right = $1.account?.name ?? ""
            return left == right ? $0.currencyCode < $1.currencyCode : left < right
        }
    }

    private var sourceWallet: CurrencyWallet? { wallet(id: sourceWalletID) }
    private var destinationWallet: CurrencyWallet? { wallet(id: destinationWalletID) }
    private var filteredCategories: [LedgerCategory] {
        let categoryKind: CategoryKind = kind == .income ? .income : .expense
        return categories.filter { $0.type == categoryKind }
    }
    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return allWallets.filter {
            $0 !== sourceWallet && (kind != .transfer || $0.currencyCode == sourceWallet.currencyCode)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if allWallets.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("还不能记账", systemImage: "plus.circle")
                        } description: {
                            Text("请先在“资产”中创建账户并添加至少一个币种。")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else {
                    Picker("类型", selection: $kind) {
                        ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    amountSection
                    walletSection
                    detailSection

                    Section {
                        Button("保存\(kind.title)", action: validateAndSave)
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                        if let successMessage {
                            Label(successMessage, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HomePalette.background)
            .navigationTitle("记账")
            .onAppear {
                ensureSelections()
            }
            .onChange(of: kind) { _, _ in resetTypeSpecificSelections() }
            .onChange(of: sourceWalletID) { _, _ in ensureDestinationSelection() }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
            .confirmationDialog(
                "保存后余额将变为负数",
                isPresented: $showingNegativeWarning,
                titleVisibility: .visible
            ) {
                Button("仍然保存", role: .destructive, action: performSave)
                Button("取消", role: .cancel) {}
            } message: {
                Text("MVP 允许负余额，但请确认金额和钱包选择无误。")
            }
        }
    }

    private var amountSection: some View {
        Section(kind == .exchange ? "换出金额" : "金额") {
            HStack(alignment: .firstTextBaseline) {
                Text(sourceWallet?.currencyCode ?? "--")
                    .font(.title2).foregroundStyle(.secondary)
                TextField("0.00", text: $amountText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if kind == .exchange {
                HStack {
                    Text(destinationWallet?.currencyCode ?? "目标币种")
                        .foregroundStyle(.secondary)
                    TextField("换入金额", text: $destinationAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var walletSection: some View {
        Section("账户与币种") {
            Picker(kind == .transfer || kind == .exchange ? "从" : "钱包", selection: $sourceWalletID) {
                ForEach(allWallets) { wallet in
                    Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                }
            }
            if kind == .transfer || kind == .exchange {
                Picker("到", selection: $destinationWalletID) {
                    ForEach(destinationOptions) { wallet in
                        Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                    }
                }
            }
            if kind == .transfer || kind == .exchange {
                Toggle("包含手续费", isOn: $includesFee)
                if includesFee {
                    HStack {
                        Text(sourceWallet?.currencyCode ?? "")
                        TextField("手续费", text: $feeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("MVP 手续费从来源钱包额外扣除。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        Section("详情") {
            if kind == .expense || kind == .income {
                Picker("分类", selection: $categoryID) {
                    Text("未分类").tag(nil as UUID?)
                    ForEach(filteredCategories) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(category.id as UUID?)
                    }
                }
            }
            if kind == .adjustment {
                Picker("方向", selection: $adjustmentDirection) {
                    ForEach(AdjustmentDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("原因", selection: $adjustmentReason) {
                    ForEach(adjustmentReasons, id: \.self) { Text($0).tag($0) }
                }
            }
            DatePicker("日期", selection: $date)
            TextField("备注（可选）", text: $note, axis: .vertical)
        }
    }

    private func validateAndSave() {
        successMessage = nil
        guard let amount = DecimalParser.parse(amountText), amount > 0 else {
            errorMessage = "请输入大于 0 的有效金额"
            return
        }
        guard let sourceWallet else {
            errorMessage = "请选择来源钱包"
            return
        }
        if kind == .transfer || kind == .exchange, destinationWallet == nil {
            errorMessage = "请选择目标钱包"
            return
        }
        if kind == .exchange,
           !(DecimalParser.parse(destinationAmountText).map { $0 > 0 } ?? false) {
            errorMessage = "请输入大于 0 的换入金额"
            return
        }
        if includesFee,
           !(DecimalParser.parse(feeText).map { $0 > 0 } ?? false) {
            errorMessage = "请输入大于 0 的手续费"
            return
        }

        let fee = includesFee ? (DecimalParser.parse(feeText) ?? 0) : 0
        let outgoing: Decimal
        switch kind {
        case .expense, .transfer, .exchange: outgoing = amount + fee
        case .adjustment where adjustmentDirection == .decrease: outgoing = amount
        default: outgoing = 0
        }
        if outgoing > sourceWallet.balance {
            showingNegativeWarning = true
        } else {
            performSave()
        }
    }

    private func performSave() {
        guard let amount = DecimalParser.parse(amountText), let sourceWallet else { return }
        let service = LedgerService(context: context)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let fee = includesFee ? DecimalParser.parse(feeText) : nil
        let category = categories.first { $0.id == categoryID }

        do {
            switch kind {
            case .expense:
                try service.createExpense(amount: amount, wallet: sourceWallet, category: category, date: date, note: cleanNote.isEmpty ? nil : cleanNote)
            case .income:
                try service.createIncome(amount: amount, wallet: sourceWallet, category: category, date: date, note: cleanNote.isEmpty ? nil : cleanNote)
            case .transfer:
                guard let destinationWallet else { throw ValidationError("请选择目标钱包") }
                try service.createTransfer(amount: amount, from: sourceWallet, to: destinationWallet, feeAmount: fee, feeWallet: fee == nil ? nil : sourceWallet, date: date, note: cleanNote.isEmpty ? nil : cleanNote)
            case .exchange:
                guard let destinationWallet,
                      let destinationAmount = DecimalParser.parse(destinationAmountText) else {
                    throw ValidationError("请输入换入金额")
                }
                try service.createExchange(sourceAmount: amount, from: sourceWallet, destinationAmount: destinationAmount, to: destinationWallet, feeAmount: fee, feeWallet: fee == nil ? nil : sourceWallet, date: date, note: cleanNote.isEmpty ? nil : cleanNote)
            case .adjustment:
                try service.createAdjustment(amount: amount, wallet: sourceWallet, direction: adjustmentDirection, reason: adjustmentReason, date: date, note: cleanNote.isEmpty ? nil : cleanNote)
            }
            successMessage = "已保存"
            amountText = ""
            destinationAmountText = ""
            feeText = ""
            includesFee = false
            note = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func wallet(id: UUID?) -> CurrencyWallet? {
        guard let id else { return nil }
        return allWallets.first { $0.id == id }
    }

    private func walletLabel(_ wallet: CurrencyWallet) -> String {
        "\(wallet.account?.name ?? "未知账户") / \(wallet.currencyCode) / \(MoneyFormatter.plain(wallet.balance, currencyCode: wallet.currencyCode))"
    }

    private func ensureSelections() {
        if sourceWallet == nil { sourceWalletID = allWallets.first?.id }
        ensureDestinationSelection()
    }

    private func ensureDestinationSelection() {
        if !destinationOptions.contains(where: { $0.id == destinationWalletID }) {
            destinationWalletID = destinationOptions.first?.id
        }
    }

    private func resetTypeSpecificSelections() {
        categoryID = filteredCategories.first?.id
        successMessage = nil
        ensureSelections()
    }
}

struct MonthlyOverviewCard: View {
    let currencyCode: String
    let summary: MonthlySummaryResult
    let setBudget: () -> Void

    private var remainingPercentageText: String {
        guard summary.missingCodes.isEmpty else { return "--" }
        guard let remainingProgress = summary.remainingBudgetProgress else { return "--" }
        return "\(Int((remainingProgress * 100).rounded()))%"
    }

    private var remainingStateText: String {
        if summary.budget == nil { return "剩余" }
        if !summary.missingCodes.isEmpty { return "汇率缺失" }
        return summary.isOverBudget ? "已超支" : "剩余"
    }

    private var budgetTint: Color {
        summary.isOverBudget ? HomePalette.expense : Color.accentColor
    }

    private var cardSurface: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        Button(action: setBudget) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("预算")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(remainingStateText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(summary.isOverBudget ? HomePalette.expense : .secondary)
                        Text(remainingPercentageText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(summary.isOverBudget ? HomePalette.expense : .primary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }

                BudgetGaugeView(
                    currencyCode: currencyCode,
                    summary: summary,
                    tint: budgetTint,
                    showsIncompleteData: summary.budget != nil && !summary.missingCodes.isEmpty
                )
                .frame(height: 72)

                Divider()
                    .overlay(Color.primary.opacity(0.06))

                HStack(alignment: .bottom) {
                    CashFlowMetric(
                        title: "收入",
                        amount: summary.income,
                        currencyCode: currencyCode,
                        alignment: .leading
                    )

                    Spacer(minLength: 28)

                    CashFlowMetric(
                        title: "支出",
                        amount: summary.expense,
                        currencyCode: currencyCode,
                        alignment: .trailing
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 14)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(BudgetCardButtonStyle())
        .shadow(color: Color(red: 0.13, green: 0.20, blue: 0.28).opacity(0.07), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.budget == nil ? "本月预算，未设置" : "本月预算")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(summary.budget == nil ? "点击设置预算" : "点击修改预算")
    }

    private var accessibilityValue: String {
        guard let budget = summary.budget else {
            return "未设置，本月收入 \(MoneyFormatter.compactString(summary.income, currencyCode: currencyCode))，支出 \(MoneyFormatter.compactString(summary.expense, currencyCode: currencyCode))"
        }
        if !summary.missingCodes.isEmpty {
            return "\(summary.missingCodes.sorted().joined(separator: "、")) 缺少汇率，本月数据暂不完整"
        }
        let total = MoneyFormatter.compactString(budget, currencyCode: currencyCode)
        let used = MoneyFormatter.compactString(summary.expense, currencyCode: currencyCode)
        return "已用 \(used)，总预算 \(total)，\(remainingStateText) \(remainingPercentageText)"
    }
}

private struct BudgetGaugeView: View {
    let currencyCode: String
    let summary: MonthlySummaryResult
    let tint: Color
    let showsIncompleteData: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            BudgetGaugeArc()
                .stroke(
                    Color.primary.opacity(0.075),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )

            BudgetGaugeArc()
                .trim(from: 0, to: showsIncompleteData ? 0 : summary.budgetProgress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .animation(.snappy(duration: 0.32), value: summary.budgetProgress)

            Group {
                if showsIncompleteData {
                    VStack(spacing: 3) {
                        Text("汇率数据不完整")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("补充汇率后将自动更新")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let budget = summary.budget {
                    VStack(spacing: 2) {
                        Text("本月已用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(
                            MoneyFormatter.compactString(summary.expense, currencyCode: currencyCode)
                                + " / "
                                + MoneyFormatter.compactString(budget, currencyCode: currencyCode)
                        )
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    }
                } else {
                    VStack(spacing: 3) {
                        Text("点击设置预算")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("设置后将按本月支出自动更新")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 1)
        }
        .padding(.horizontal, 28)
        .accessibilityHidden(true)
    }
}

private struct BudgetGaugeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width / 2, rect.height - 6)
        let center = CGPoint(x: rect.midX, y: rect.maxY - 2)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

private struct CashFlowMetric: View {
    let title: String
    let amount: Decimal
    let currencyCode: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.compactString(amount, currencyCode: currencyCode))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let month: Date
    let currencyCode: String
    let currentAmount: Decimal?
    let save: (Decimal) throws -> Void

    @State private var amountText: String
    @State private var errorMessage: String?
    @FocusState private var isAmountFocused: Bool

    init(
        month: Date,
        currencyCode: String,
        currentAmount: Decimal?,
        save: @escaping (Decimal) throws -> Void
    ) {
        self.month = month
        self.currencyCode = currencyCode
        self.currentAmount = currentAmount
        self.save = save
        _amountText = State(initialValue: currentAmount.map {
            NSDecimalNumber(decimal: $0).stringValue
        } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("预算金额") {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(currencyCode)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextField("例如 5000", text: $amountText)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isAmountFocused)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(HomePalette.expense)
                    }
                }

                Section {
                    Text("剩余预算会根据本月支出自动计算，修改后顶部仪表盘会立即更新。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HomePalette.background)
            .navigationTitle("设置\(month.chineseYearMonth)预算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: validateAndSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { isAmountFocused = true }
            .onChange(of: amountText) { _, _ in errorMessage = nil }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func validateAndSave() {
        guard let amount = DecimalParser.parse(amountText), amount > 0 else {
            errorMessage = "请输入大于 0 的预算金额"
            return
        }

        do {
            try save(amount)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BudgetCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
