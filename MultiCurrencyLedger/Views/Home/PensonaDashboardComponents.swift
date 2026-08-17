import SwiftUI

enum PensonaDashboardTypography {
    static let balance = Font.custom("Ioskeley Mono Semibold", size: 36, relativeTo: .title3)
    static let amount = Font.custom("Ioskeley Mono Semibold", size: 18, relativeTo: .headline)
    static let compactAmount = Font.custom("Ioskeley Mono", size: 16, relativeTo: .body)
    static let metadata = Font.custom("Ioskeley Mono", size: 13, relativeTo: .caption)
}

struct OneTsuMonthHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    let selectedMonth: Date
    let openPicker: () -> Void
    let changeMonth: (Int) -> Void

    var body: some View {
        ZStack {
            HStack {
                monthButton("chevron.left", offset: -1)
                Spacer()
                monthButton("chevron.right", offset: 1)
            }
            Button(action: openPicker) {
                HStack(spacing: 7) {
                    Text(selectedMonth.yearMonthText(locale: locale))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.primary)
                .frame(minHeight: LedgerLayout.minimumHitSize)
            }
            .buttonStyle(LedgerGlassPressStyle())
            .accessibilityLabel("选择年月，当前\(selectedMonth.yearMonthText(locale: locale))")
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 44).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.4,
                  abs(value.translation.width) > 70 else { return }
            changeMonth(value.translation.width < 0 ? 1 : -1)
        })
    }

    private func monthButton(_ symbol: String, offset: Int) -> some View {
        Button { changeMonth(offset) } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: LedgerLayout.minimumHitSize, height: LedgerLayout.minimumHitSize)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityLabel(offset < 0 ? "上一个月" : "下一个月")
    }
}

struct OneTsuReceiptLedger: View {
    let snapshot: BillPageSnapshot?
    let currencyCode: String
    let emptyState: (title: String, message: String)
    let loadError: String?
    let openBudget: () -> Void
    let openTransaction: (LedgerTransaction, CGRect) -> Void
    let editTransaction: (LedgerTransaction) -> Void
    let deleteTransaction: (LedgerTransaction) -> Void
    let addTransaction: () -> Void
    let attachmentTransactionIDs: Set<UUID>
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot {
                ReceiptBudgetLine(summary: snapshot.summary, currencyCode: currencyCode, openBudget: openBudget)
                    .padding(.bottom, 18)

                if snapshot.dayGroups.isEmpty {
                    ContentUnavailableView(
                        emptyState.title,
                        systemImage: "receipt",
                        description: Text(emptyState.message)
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .overlay(alignment: .bottom) {
                        Button("记一笔", action: addTransaction)
                            .buttonStyle(.glassProminent)
                            .tint(LedgerPalette.accent)
                            .padding(.bottom, 22)
                    }
                } else {
                    ForEach(snapshot.dayGroups) { group in
                        ReceiptDaySection(
                            group: group,
                            currencyCode: currencyCode,
                            attachmentTransactionIDs: attachmentTransactionIDs,
                            openTransaction: openTransaction,
                            editTransaction: editTransaction,
                            deleteTransaction: deleteTransaction
                        )
                    }
                }
            } else if let loadError {
                VStack(spacing: 14) {
                    ContentUnavailableView("流水加载失败", systemImage: "exclamationmark.triangle", description: Text(loadError))
                    Button("重试", action: retry)
                        .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ProgressView("正在加载流水")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
    }
}

private struct ReceiptBudgetLine: View {
    let summary: MonthlySummary
    let currencyCode: String
    let openBudget: () -> Void

    var body: some View {
        Button(action: openBudget) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                Text(budgetText)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.secondary)
            .frame(minHeight: 32)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityHint("打开本月预算设置")
    }

    private var budgetText: String {
        guard summary.missingCodes.isEmpty else { return "预算暂不可用" }
        guard let remaining = summary.remainingBudget else { return "设置本月预算" }
        return "本月预算余 \(MoneyFormatter.compactString(remaining, currencyCode: currencyCode))"
    }
}

private struct ReceiptTransactionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

private struct ReceiptDaySection: View {
    @Environment(\.locale) private var locale

    let group: BillDayGroup
    let currencyCode: String
    let attachmentTransactionIDs: Set<UUID>
    let openTransaction: (LedgerTransaction, CGRect) -> Void
    let editTransaction: (LedgerTransaction) -> Void
    let deleteTransaction: (LedgerTransaction) -> Void
    @State private var transactionFrames: [UUID: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.date.formatted(.dateTime.month().day()))
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(group.transactions.count)笔")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.transactions) { transaction in
                Button { openTransaction(transaction, transactionFrames[transaction.id] ?? .zero) } label: {
                    ReceiptTransactionRow(
                        transaction: transaction,
                        currencyCode: currencyCode,
                        hasAttachment: attachmentTransactionIDs.contains(transaction.id)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("编辑交易", systemImage: "square.and.pencil") { editTransaction(transaction) }
                    Button("删除交易", systemImage: "trash", role: .destructive) { deleteTransaction(transaction) }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("编辑", systemImage: "square.and.pencil") { editTransaction(transaction) }
                        .tint(LedgerPalette.accent)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除", systemImage: "trash", role: .destructive) { deleteTransaction(transaction) }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ReceiptTransactionFramePreferenceKey.self,
                            value: [transaction.id: proxy.frame(in: .global)]
                        )
                    }
                }
                .accessibilityHint("展开查看账单详情")
            }
        }
        .onPreferenceChange(ReceiptTransactionFramePreferenceKey.self) { frames in
            transactionFrames.merge(frames) { _, latest in latest }
        }
        .padding(.bottom, 20)
    }
}

private struct ReceiptTransactionRow: View {
    let transaction: LedgerTransaction
    let currencyCode: String
    let hasAttachment: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let category = transaction.category {
                CategoryIconImage(category: category, size: 36)
            } else {
                Image(systemName: transaction.type.symbolName)
                    .font(.title3)
                    .foregroundStyle(LedgerPalette.accent)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(transaction.receiptTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let originalAmount = transaction.originalAmount,
                           originalAmount > (transaction.amount ?? 0),
                           !(transaction.type == .income && transaction.feeAmount != nil) {
                            Text(MoneyFormatter.compactString(originalAmount, currencyCode: currencyCode))
                                .font(LedgerTypography.receiptMeta)
                                .foregroundStyle(.secondary)
                                .strikethrough()
                        }
                        Text(transaction.summaryAmount)
                            .font(LedgerTypography.amount)
                            .foregroundStyle(LedgerPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                metadataLine

                if let fundingText = transaction.receiptFundingText {
                    Label(fundingText, systemImage: transaction.paymentParts.count > 1 ? "rectangle.3.group" : "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let offerText = transaction.receiptOfferText(currencyCode: currencyCode) {
                    Text(offerText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tagText = transaction.receiptTagText {
                    Text(tagText)
                        .font(.caption2)
                        .foregroundStyle(LedgerPalette.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LedgerPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LedgerPalette.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var metadataLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(transaction.homeCategoryTitle)
                dot
                Text(transaction.date.formatted(date: .omitted, time: .shortened))
            }
            if let note = transaction.receiptSubtitle {
                Text(note)
            }
            HStack(spacing: 5) {
                if transaction.reimbursementStatus == .pending {
                    Text("待报销")
                }
                if transaction.installmentIndex != nil {
                    Text("分期")
                }
                if hasAttachment {
                    Image(systemName: "paperclip")
                }
            }
        }
        .font(LedgerTypography.receiptMeta)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dot: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private var amountColor: Color {
        let raw = UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? ""
        let convention = AmountColorConvention(rawValue: raw)
            ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
        return AmountSemanticStyle.color(for: AmountSemanticStyle.role(for: transaction.type), convention: convention)
    }
}

@MainActor
private func semanticColor(_ role: AmountSemanticRole) -> Color {
    let raw = UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? ""
    let convention = AmountColorConvention(rawValue: raw)
        ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
    return AmountSemanticStyle.color(for: role, convention: convention)
}

struct PensonaDashboardBalanceCard: View {
    let summary: MonthlySummary
    let currencyCode: String
    let openBudget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("预算")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: openBudget) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(HomePalette.accent.opacity(0.10), in: Circle())
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("编辑预算")
            }

            budgetSummary

            Divider().opacity(0.58)

            HStack(spacing: 0) {
                metric(title: "本月收入", amount: summary.income, role: .income)
                Divider().frame(height: 44)
                metric(title: "本月支出", amount: summary.expense, role: .expense)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .ledgerSurface(.summary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("预算")
        .accessibilityValue(budgetAccessibilityValue)
    }

    @ViewBuilder
    private var budgetSummary: some View {
        if let budget = summary.budget, summary.missingCodes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("本月预算")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(MoneyFormatter.compactString(summary.expense, currencyCode: currencyCode)) / \(MoneyFormatter.compactString(budget, currencyCode: currencyCode))")
                    .font(PensonaDashboardTypography.balance)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)
                    .contentTransition(.numericText())
                HStack {
                    ProgressView(value: summary.budgetProgress)
                        .tint(summary.isOverBudget ? HomePalette.expense : HomePalette.accent)
                    Text("剩余 \(MoneyFormatter.compactString(summary.remainingBudget ?? 0, currencyCode: currencyCode))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(summary.isOverBudget ? HomePalette.expense : .secondary)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.missingCodes.isEmpty ? "本月尚未设置预算" : "缺少汇率，暂无法计算预算")
                    .font(.title3.weight(.semibold))
                Text("点击右上角设置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 74, alignment: .leading)
        }
    }

    private var budgetAccessibilityValue: String {
        guard let budget = summary.budget, summary.missingCodes.isEmpty else {
            return summary.missingCodes.isEmpty ? "本月尚未设置预算" : "缺少汇率"
        }
        return "\(MoneyFormatter.string(summary.expense, currencyCode: currencyCode))，预算 \(MoneyFormatter.string(budget, currencyCode: currencyCode))"
    }

    private func metric(
        title: LocalizedStringKey,
        amount: Decimal,
        role: AmountSemanticRole
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MoneyFormatter.compactString(amount, currencyCode: currencyCode))
                .font(PensonaDashboardTypography.amount)
                .monospacedDigit()
                .foregroundStyle(semanticColor(role))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, role == .income ? 14 : 0)
        .padding(.leading, role == .expense ? 18 : 0)
    }

    private func semanticColor(_ role: AmountSemanticRole) -> Color {
        let raw = UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? ""
        let convention = AmountColorConvention(rawValue: raw)
            ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
        return AmountSemanticStyle.color(for: role, convention: convention)
    }
}

struct PensonaDashboardBudgetCard: View {
    let summary: MonthlySummary
    let currencyCode: String
    let openBudget: () -> Void

    var body: some View {
        Button(action: openBudget) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("预算")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomePalette.accent)
                        .frame(width: 36, height: 36)
                        .background(HomePalette.accent.opacity(0.10), in: Circle())
                }

                if let budget = summary.budget, summary.missingCodes.isEmpty {
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本月预算")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(MoneyFormatter.compactString(summary.expense, currencyCode: currencyCode)) / \(MoneyFormatter.compactString(budget, currencyCode: currencyCode))")
                                .font(PensonaDashboardTypography.compactAmount)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("剩余")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(MoneyFormatter.compactString(summary.remainingBudget ?? 0, currencyCode: currencyCode))
                                .font(PensonaDashboardTypography.compactAmount)
                                .foregroundStyle(summary.isOverBudget ? HomePalette.expense : .primary)
                        }
                    }

                    ProgressView(value: summary.budgetProgress)
                        .tint(summary.isOverBudget ? HomePalette.expense : HomePalette.accent)
                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                        .padding(.vertical, 3)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: summary.missingCodes.isEmpty ? "target" : "exclamationmark.triangle")
                            .foregroundStyle(HomePalette.accent)
                        Text(summary.missingCodes.isEmpty ? "点击设置本月预算" : "缺少汇率，暂无法计算预算")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 46)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .ledgerSurface(.functional)
        .accessibilityHint("打开本月预算设置")
    }
}

struct PensonaDashboardRecentTransactions: View {
    let transactions: [LedgerTransaction]
    let showAll: () -> Void
    let openTransaction: (LedgerTransaction) -> Void
    let addTransaction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近交易")
                    .font(.headline)
                Spacer()
                Button(action: showAll) {
                    Label("查看全部", systemImage: "chevron.right")
                        .font(.subheadline.weight(.medium))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HomePalette.accent)
                .accessibilityHint("打开全部账单")
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 60)

            if transactions.isEmpty {
                ContentUnavailableView(
                    "还没有记账记录",
                    systemImage: "receipt",
                    description: Text("点击下方加号开始添加第一笔交易")
                )
                .frame(maxWidth: .infinity, minHeight: 170)
                .overlay(alignment: .bottom) {
                    Button("添加交易", action: addTransaction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.bottom, 14)
                }
            } else {
                Divider().padding(.leading, 20)
                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                    Button { openTransaction(transaction) } label: {
                        PensonaDashboardTransactionRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("打开交易详情")
                    if index < transactions.count - 1 {
                        Divider().padding(.leading, 78)
                    }
                }
            }
        }
        .ledgerSurface(.functional)
    }
}

private struct PensonaDashboardTransactionRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack(spacing: 12) {
            if let category = transaction.category {
                CategoryIconImage(category: category, size: 42)
            } else {
                Image(systemName: transaction.type.symbolName)
                    .font(.headline)
                    .foregroundStyle(HomePalette.accent)
                    .frame(width: 42, height: 42)
                    .background(HomePalette.accent.opacity(0.10), in: Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.homeCategoryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(transaction.date.formatted(date: .abbreviated, time: .omitted)) · \(transaction.homeAccountName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(transaction.summaryAmount)
                .font(PensonaDashboardTypography.compactAmount)
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 70)
        .contentShape(Rectangle())
    }

    private var amountColor: Color {
        let raw = UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? ""
        let convention = AmountColorConvention(rawValue: raw)
            ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
        return AmountSemanticStyle.color(
            for: AmountSemanticStyle.role(for: transaction.type),
            convention: convention
        )
    }
}

struct PensonaDashboardErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("首页加载失败", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .ledgerSurface(.functional)
    }
}
