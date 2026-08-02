import SwiftUI

struct BillTopControls: View {
    let bookName: String
    let openBook: () -> Void
    let openSearch: () -> Void
    let openSettings: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: openBook) {
                    Label(bookName, systemImage: "book.closed.fill")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(minHeight: LedgerLayout.minimumHitSize)
                }
                .buttonStyle(.glass)
                .accessibilityHint("切换账本")
                .accessibilityIdentifier("home-book-switcher")
                .centeredGenieSourceFrame(id: "home-book-switcher")

                Spacer(minLength: 0)

                Button(action: openSearch) {
                    Image(systemName: "magnifyingglass")
                        .frame(width: LedgerLayout.minimumHitSize, height: LedgerLayout.minimumHitSize)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("搜索账单")

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .frame(width: LedgerLayout.minimumHitSize, height: LedgerLayout.minimumHitSize)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("设置")
            }
        }
    }
}

struct BillMonthHeader: View {
    @Environment(\.locale) private var locale

    let selectedMonth: Date
    let openPicker: () -> Void
    let changeMonth: (Int) -> Void

    var body: some View {
        ZStack {
            HStack {
                monthButton("chevron.left", offset: -1)
                Spacer(minLength: 0)
                monthButton("chevron.right", offset: 1)
            }

            Button(action: openPicker) {
                HStack(spacing: 6) {
                    Text(selectedMonth.yearMonthText(locale: locale))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: LedgerLayout.minimumHitSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(
                    localized: "选择年月，当前\(selectedMonth.yearMonthText(locale: locale))",
                    locale: locale
                )
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 44)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.4,
                          abs(value.translation.width) > 70 else { return }
                    changeMonth(value.translation.width < 0 ? 1 : -1)
                }
        )
        .accessibilityElement(children: .contain)
    }

    private func monthButton(_ symbol: String, offset: Int) -> some View {
        Button { changeMonth(offset) } label: {
            Image(systemName: symbol)
                .frame(width: LedgerLayout.minimumHitSize, height: LedgerLayout.minimumHitSize)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(offset < 0 ? "上一个月" : "下一个月")
        .accessibilityIdentifier(offset < 0 ? "bill-month-previous" : "bill-month-next")
    }
}

struct BillMonthlySummaryPanel: View {
    let summary: MonthlySummary
    let currencyCode: String
    let openBudget: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                summaryValue("支出", amount: summary.expense, role: .expense)
                Spacer()
                summaryValue("收入", amount: summary.income, role: .income)
            }
            Divider().opacity(0.55)
            HStack {
                summaryValue("结余", amount: summary.income - summary.expense, role: .neutral)
                Spacer()
                Button(action: openBudget) {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("预算剩余")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(budgetText)
                            .font(LedgerTypography.amount)
                            .monospacedDigit()
                    }
                    .frame(minWidth: 120, minHeight: LedgerLayout.minimumHitSize, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开当前月预算设置")
            }
        }
        .padding(20)
        .ledgerSurface(.summary)
    }

    @ViewBuilder
    private func summaryValue(_ title: LocalizedStringKey, amount: Decimal, role: AmountSemanticRole) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(MoneyFormatter.compactString(amount, currencyCode: currencyCode))
                .font(LedgerTypography.amount)
                .monospacedDigit()
                .foregroundStyle(semanticColor(role))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: 120, alignment: .leading)
    }

    private var budgetText: String {
        guard summary.missingCodes.isEmpty else { return "--" }
        guard let remaining = summary.remainingBudget else { return AppLocalization.string("设置预算") }
        return MoneyFormatter.compactString(remaining, currencyCode: currencyCode)
    }

    private func semanticColor(_ role: AmountSemanticRole) -> Color {
        let raw = UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? ""
        let convention = AmountColorConvention(rawValue: raw)
            ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
        return AmountSemanticStyle.color(for: role, convention: convention)
    }
}

struct BillDailyGroup: View {
    @Environment(\.locale) private var locale

    let group: BillDayGroup
    @Binding var expandedTransactionID: UUID?
    let open: (LedgerTransaction) -> Void
    let edit: (LedgerTransaction) -> Void
    let delete: (LedgerTransaction) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(group.date.dayHeading(locale: locale))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.transactions.count) 笔")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 30)

            ForEach(group.transactions) { transaction in
                BillSwipeableTransactionRow(
                    transaction: transaction,
                    expandedTransactionID: $expandedTransactionID,
                    open: { open(transaction) },
                    edit: { edit(transaction) },
                    delete: { delete(transaction) }
                )
            }
        }
    }
}

private struct BillSwipeableTransactionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Side { case leading, trailing }
    private enum DragAxis { case horizontal, vertical }

    private let revealWidth: CGFloat = 82

    let transaction: LedgerTransaction
    @Binding var expandedTransactionID: UUID?
    let open: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @State private var side: Side?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragAxis: DragAxis?

    private var activeSide: Side? {
        expandedTransactionID == transaction.id ? side : nil
    }

    private var showsSettledActions: Bool {
        dragAxis == nil
    }

    private var restingOffset: CGFloat {
        switch activeSide {
        case .leading: revealWidth
        case .trailing: -revealWidth
        case nil: 0
        }
    }

    private var offset: CGFloat {
        constrainedOffset(restingOffset + dragTranslation, for: activeSide)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                actionItem(
                    AppLocalization.string("编辑"),
                    symbol: "square.and.pencil",
                    color: actionNeutralColor,
                    action: edit
                )
                .frame(width: revealWidth)
                .opacity(activeSide == .leading && showsSettledActions ? 1 : 0)
                .allowsHitTesting(activeSide == .leading && showsSettledActions)

                Spacer(minLength: 0)

                actionItem(
                    AppLocalization.string("删除"),
                    symbol: "trash",
                    color: HomePalette.expense,
                    action: delete
                )
                .frame(width: revealWidth)
                .opacity(activeSide == .trailing && showsSettledActions ? 1 : 0)
                .allowsHitTesting(activeSide == .trailing && showsSettledActions)
            }

            BillTransactionRow(transaction: transaction)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 0.75)
                }
                .shadow(
                    color: .black.opacity(offset == 0 ? 0.035 : 0.075),
                    radius: offset == 0 ? 7 : 11,
                    y: 4
                )
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if dragAxis == nil {
                            dragAxis = abs(value.translation.width) > abs(value.translation.height)
                                ? .horizontal
                                : .vertical
                        }
                        guard dragAxis == .horizontal else { return }
                        dragTranslation = value.translation.width
                    }
                    .onEnded { value in
                        settleDrag(value)
                    }
                    .exclusively(before: TapGesture().onEnded(handleTap))
            )
            .accessibilityAction(named: "编辑交易", edit)
            .accessibilityAction(named: "删除交易", delete)
            .accessibilityIdentifier(transactionAccessibilityIdentifier)
        }
        .frame(height: 70)
        .clipped()
        .onChange(of: expandedTransactionID) { _, id in
            guard id != transaction.id else { return }
            side = nil
            dragTranslation = 0
            dragAxis = nil
        }
    }

    private var transactionAccessibilityIdentifier: String {
        if transaction.id == PreviewDataService.sampleDiningTransactionID
            || (ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1"
                && ["星巴克", "Starbucks"].contains(transaction.displayNote)) {
            return "sample-transaction-dining"
        }
        return "transaction-\(transaction.id.uuidString)"
    }

    private func constrainedOffset(_ proposed: CGFloat, for side: Side?) -> CGFloat {
        switch side {
        case .leading:
            return min(revealWidth, max(0, proposed))
        case .trailing:
            return min(0, max(-revealWidth, proposed))
        case nil:
            return min(revealWidth, max(-revealWidth, proposed))
        }
    }

    private func settleDrag(_ value: DragGesture.Value) {
        guard dragAxis == .horizontal else {
            dragTranslation = 0
            dragAxis = nil
            return
        }

        let projection = value.translation.width
            + (value.predictedEndTranslation.width - value.translation.width) * 0.22
        let projectedOffset = constrainedOffset(
            restingOffset + projection,
            for: activeSide
        )
        let animation = reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical
        let previousSide = activeSide
        let targetSide: Side?

        switch activeSide {
        case nil where projectedOffset >= revealWidth * 0.58:
            targetSide = .leading
        case nil where projectedOffset <= -revealWidth * 0.58:
            targetSide = .trailing
        case .leading where projectedOffset <= revealWidth * 0.50:
            targetSide = nil
        case .trailing where projectedOffset >= -revealWidth * 0.50:
            targetSide = nil
        case nil:
            targetSide = nil
        default:
            targetSide = activeSide
        }

        withAnimation(animation) {
            dragTranslation = 0
            dragAxis = nil
            side = targetSide
            if targetSide == nil {
                expandedTransactionID = nil
            } else {
                expandedTransactionID = transaction.id
            }
        }

        if previousSide != targetSide {
            HapticFeedbackService().selection()
        }
    }

    private func handleTap() {
        if activeSide == nil {
            open()
        } else {
            withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical) {
                side = nil
                expandedTransactionID = nil
            }
        }
    }

    private var actionNeutralColor: Color {
        Color(red: 0.18, green: 0.19, blue: 0.21)
    }

    private func actionItem(
        _ title: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(color, in: Circle())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 54, height: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct BillTransactionRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack(spacing: 12) {
            if let category = transaction.category {
                CategoryIconImage(category: category, size: 40)
            } else {
                Image(systemName: transaction.type.symbolName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(HomePalette.accent)
                    .frame(width: 40, height: 40)
                    .background(HomePalette.accent.opacity(0.10), in: Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.homeCategoryTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let note = transaction.displayNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(1)
                }
                Text("\(transaction.homeAccountName) · \(transaction.date.formatted(date: .omitted, time: .shortened))")
                    .font(transaction.displayNote == nil ? .caption : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(transaction.summaryAmount)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
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
