import SwiftUI

struct MonthlyOverviewCard: View {
    let currencyCode: String
    let summary: MonthlySummaryResult
    let setBudget: () -> Void

    private var remainingAmountText: String {
        guard summary.missingCodes.isEmpty else { return "--" }
        guard let remaining = summary.remainingBudget else { return "设置预算" }
        return wholeNumber(remaining)
    }

    private var totalBudgetText: String {
        summary.budget.map(wholeNumber) ?? "预算"
    }

    private var gaugeProgress: Double {
        guard summary.missingCodes.isEmpty else { return 0 }
        return summary.remainingBudgetProgress ?? 0
    }

    private var stateText: String {
        if !summary.missingCodes.isEmpty { return "汇率数据不完整" }
        if summary.budget == nil { return "点击设置本月预算" }
        return summary.isOverBudget ? "本月已超出预算" : "本月剩余预算"
    }

    var body: some View {
        Button(action: setBudget) {
            FigmaBudgetGauge(
                amountText: remainingAmountText,
                stateText: stateText,
                totalText: totalBudgetText,
                progress: gaugeProgress,
                isOverBudget: summary.isOverBudget
            )
            .frame(maxWidth: .infinity)
            .frame(height: 183)
            .ledgerContentSurface(cornerRadius: 36)
            .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
        .buttonStyle(BudgetCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.budget == nil ? "本月预算，未设置" : "本月预算")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(summary.budget == nil ? "点击设置预算" : "点击修改预算")
    }

    private func wholeNumber(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
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
        return "已用 \(used)，总预算 \(total)，\(stateText) \(remainingAmountText)"
    }
}

private struct FigmaBudgetGauge: View {
    let amountText: String
    let stateText: String
    let totalText: String
    let progress: Double
    let isOverBudget: Bool

    var body: some View {
        ZStack(alignment: .top) {
            BudgetGaugeArc()
                .stroke(
                    HomePalette.gaugeTrack,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .frame(width: 214, height: 108)
                .padding(.top, 25)

            BudgetGaugeArc()
                .trim(from: 0, to: progress)
                .stroke(
                    isOverBudget ? HomePalette.expense : HomePalette.gaugeProgress,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .frame(width: 214, height: 108)
                .padding(.top, 25)
                .animation(LedgerMotion.responsive, value: progress)

            VStack(spacing: 5) {
                Text(amountText)
                    .font(.system(size: amountText.count > 7 ? 25 : 32, weight: .medium, design: .rounded))
                    .foregroundStyle(isOverBudget ? HomePalette.expense : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(stateText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150)
            .padding(.top, 76)

            HStack {
                Text("0")
                Spacer()
                Text(totalText)
            }
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(.tertiary)
            .frame(width: 226)
            .padding(.top, 143)
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive, value: configuration.isPressed)
    }
}
