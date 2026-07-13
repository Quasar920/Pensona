import SwiftUI

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
