import SwiftUI
import UIKit

enum PensonaDashboardTypography {
    static let balance = LedgerFont.semibold(size: 36, relativeTo: .title3)
    static let amount = LedgerFont.semibold(size: 18, relativeTo: .headline)
    static let compactAmount = LedgerFont.regular(size: 16, relativeTo: .body)
    static let metadata = LedgerFont.regular(size: 13, relativeTo: .caption)
    static let month = LedgerFont.semibold(size: 27, relativeTo: .title2)
    static let section = LedgerFont.regular(size: 16, relativeTo: .headline)
    static let rowTitle = LedgerFont.semibold(size: 18, relativeTo: .headline)
    static let transactionTypeTitle = LedgerFont.regular(size: 18, relativeTo: .headline)
    static let rowDetail = LedgerFont.regular(size: 14, relativeTo: .caption)
    static let rowAmount = LedgerFont.regular(size: 20, relativeTo: .title3)
    static let exchangeAmount = LedgerFont.regular(size: 17, relativeTo: .headline)
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
                        .font(PensonaDashboardTypography.month)
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
                .font(LedgerFont.semibold(size: 15, relativeTo: .subheadline))
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
    @Binding var expandedTransactionID: UUID?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot {
                ReceiptNumberDashboard(summary: snapshot.summary, currencyCode: currencyCode, openBudget: openBudget)
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
                            expandedTransactionID: $expandedTransactionID,
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

/// A native SwiftUI equivalent of NumberFlow's rolling-number treatment.
/// `numericText` tracks individual numeric glyphs, so a refreshed month or a
/// newly saved transaction changes the value by rolling digits instead of
/// replacing the whole string at once.
private struct ReceiptNumberDashboard: View {
    let summary: MonthlySummary
    let currencyCode: String
    let openBudget: () -> Void

    var body: some View {
        Button(action: openBudget) {
            HStack(spacing: 0) {
                dashboardMetric(title: "收入", amount: summary.income, role: .income)
                dashboardBudget
                dashboardMetric(title: "支出", amount: summary.expense, role: .expense)
            }
            .padding(.vertical, 12)
            .ledgerSurface(.summary, cornerRadius: 20)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityHint("打开本月预算设置")
    }

    private var dashboardBudget: some View {
        VStack(spacing: 4) {
            Text("本月剩余预算")
                .font(PensonaDashboardTypography.metadata)
                .foregroundStyle(.secondary)
            if let remainingBudget = summary.remainingBudget, summary.missingCodes.isEmpty {
                RollingNumberText(
                    value: remainingBudget,
                    text: MoneyFormatter.compactString(remainingBudget, currencyCode: currencyCode),
                    font: PensonaDashboardTypography.amount,
                    color: LedgerPalette.ink
                )
            } else {
                Text(summary.missingCodes.isEmpty ? "设置预算" : "预算暂不可用")
                    .font(PensonaDashboardTypography.compactAmount)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dashboardMetric(
        title: String,
        amount: Decimal,
        role: AmountSemanticRole
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(PensonaDashboardTypography.metadata)
                .foregroundStyle(.secondary)
            RollingNumberText(
                value: amount,
                text: MoneyFormatter.compactString(amount, currencyCode: currencyCode),
                font: PensonaDashboardTypography.compactAmount,
                color: semanticColor(role)
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func semanticColor(_ role: AmountSemanticRole) -> Color {
        let raw = UserDefaults.standard.string(forKey: AppPreferences.amountColorKey) ?? ""
        let convention = AmountColorConvention(rawValue: raw)
            ?? .regionalDefault(regionCode: Locale.current.region?.identifier)
        return AmountSemanticStyle.color(for: role, convention: convention)
    }
}

private struct RollingNumberText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Decimal
    let text: String
    let font: Font
    let color: Color

    private var numericValue: Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentTransition(reduceMotion ? .identity : .numericText(value: numericValue))
            .animation(reduceMotion ? nil : .smooth(duration: 0.46), value: numericValue)
            .accessibilityLabel(text)
    }
}

private struct ReceiptTransactionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

private struct ReceiptDaySection: View {
    let group: BillDayGroup
    let currencyCode: String
    let attachmentTransactionIDs: Set<UUID>
    @Binding var expandedTransactionID: UUID?
    let openTransaction: (LedgerTransaction, CGRect) -> Void
    let editTransaction: (LedgerTransaction) -> Void
    let deleteTransaction: (LedgerTransaction) -> Void
    @State private var transactionFrames: [UUID: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayLabel)
                    .font(PensonaDashboardTypography.section)
                Spacer()
                HStack(spacing: 10) {
                    if group.income != 0 {
                        dayTotal(title: "收入", amount: group.income)
                    }
                    if group.expense != 0 {
                        dayTotal(title: "支出", amount: group.expense)
                    }
                }
            }

            ForEach(group.transactions) { transaction in
                ReceiptSwipeableTransactionRow(
                    transaction: transaction,
                    currencyCode: currencyCode,
                    hasAttachment: attachmentTransactionIDs.contains(transaction.id),
                    expandedTransactionID: $expandedTransactionID,
                    open: { openTransaction(transaction, transactionFrames[transaction.id] ?? .zero) },
                    edit: { editTransaction(transaction) },
                    delete: { deleteTransaction(transaction) }
                )
                .contextMenu {
                    Button("编辑交易", systemImage: "square.and.pencil") { editTransaction(transaction) }
                    Button("删除交易", systemImage: "trash", role: .destructive) { deleteTransaction(transaction) }
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
        .padding(.bottom, 18)
    }

    private var dayLabel: String {
        Self.dateFormatter.string(from: group.date)
    }

    private func dayTotal(title: String, amount: Decimal) -> some View {
        Text("\(title) \(MoneyFormatter.compactString(amount, currencyCode: currencyCode))")
            .font(PensonaDashboardTypography.metadata)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MM - dd"
        return formatter
    }()
}

private struct ReceiptSwipeableTransactionRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Side { case edit, delete }

    private let revealWidth: CGFloat = 82

    let transaction: LedgerTransaction
    let currencyCode: String
    let hasAttachment: Bool
    @Binding var expandedTransactionID: UUID?
    let open: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    @State private var side: Side?
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false

    private var activeSide: Side? {
        expandedTransactionID == transaction.id ? side : nil
    }

    private var restingOffset: CGFloat {
        switch activeSide {
        case .edit: revealWidth
        case .delete: -revealWidth
        case nil: 0
        }
    }

    private var horizontalOffset: CGFloat {
        constrainedOffset(restingOffset + dragTranslation, side: activeSide)
    }

    private var leadingRevealProgress: CGFloat {
        max(0, min(1, horizontalOffset / revealWidth))
    }

    private var trailingRevealProgress: CGFloat {
        max(0, min(1, -horizontalOffset / revealWidth))
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                actionButton(
                    title: "编辑",
                    symbol: "square.and.pencil",
                    isExposed: activeSide == .edit && !isDragging,
                    action: edit
                )
                    .frame(width: revealWidth)
                    .opacity(leadingRevealProgress)
                    .scaleEffect(0.92 + leadingRevealProgress * 0.08)
                    .allowsHitTesting(activeSide == .edit && !isDragging)
                    .accessibilityHidden(activeSide != .edit || isDragging)

                Spacer(minLength: 0)

                actionButton(
                    title: "删除",
                    symbol: "trash",
                    isExposed: activeSide == .delete && !isDragging,
                    action: delete
                )
                    .frame(width: revealWidth)
                    .opacity(trailingRevealProgress)
                    .scaleEffect(0.92 + trailingRevealProgress * 0.08)
                    .allowsHitTesting(activeSide == .delete && !isDragging)
                    .accessibilityHidden(activeSide != .delete || isDragging)
            }
            .frame(maxHeight: .infinity)

            ReceiptTransactionRow(
                transaction: transaction,
                currencyCode: currencyCode,
                hasAttachment: hasAttachment
            )
            .gesture(
                ReceiptHorizontalSwipeGesture(
                    changed: handleDragChanged,
                    ended: settleDrag
                )
            )
            .offset(x: horizontalOffset)
            .compositingGroup()
            .onTapGesture(perform: handleTap)
            .accessibilityIdentifier(transactionAccessibilityIdentifier)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onChange(of: expandedTransactionID) { _, id in
            guard id != transaction.id else { return }
            side = nil
            dragTranslation = 0
            isDragging = false
        }
        .accessibilityAction(named: "编辑交易", edit)
        .accessibilityAction(named: "删除交易", delete)
        .accessibilityHint("展开查看账单详情")
    }

    private func handleDragChanged(_ translation: CGFloat) {
        isDragging = true
        if expandedTransactionID != transaction.id {
            expandedTransactionID = transaction.id
            side = nil
        }
        dragTranslation = translation
    }

    private func settleDrag(_ translation: CGFloat, _ velocity: CGFloat) {
        let projection = translation + velocity * 0.12
        let projectedOffset = constrainedOffset(restingOffset + projection, side: activeSide)
        let targetSide: Side?
        switch activeSide {
        case nil where projectedOffset >= revealWidth * 0.55: targetSide = .edit
        case nil where projectedOffset <= -revealWidth * 0.55: targetSide = .delete
        case .edit where projectedOffset <= revealWidth * 0.48: targetSide = nil
        case .delete where projectedOffset >= -revealWidth * 0.48: targetSide = nil
        default: targetSide = activeSide
        }

        let changed = activeSide != targetSide
        withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical) {
            dragTranslation = 0
            isDragging = false
            side = targetSide
            expandedTransactionID = targetSide == nil ? nil : transaction.id
        }
        if changed { HapticFeedbackService().selection() }
    }

    private func handleTap() {
        if activeSide == nil {
            expandedTransactionID = nil
            open()
        } else {
            withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.physical) {
                side = nil
                expandedTransactionID = nil
            }
        }
    }

    private func constrainedOffset(_ proposed: CGFloat, side: Side?) -> CGFloat {
        switch side {
        case .edit: min(revealWidth, max(0, proposed))
        case .delete: min(0, max(-revealWidth, proposed))
        case nil: min(revealWidth, max(-revealWidth, proposed))
        }
    }

    private func actionButton(
        title: String,
        symbol: String,
        isExposed: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LedgerPalette.ink, in: Circle())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            isExposed
                ? "bill-\(title == "编辑" ? "edit" : "delete")-\(transactionAccessibilityIdentifier)"
                : ""
        )
    }

    private var transactionAccessibilityIdentifier: String {
        if ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1" {
            switch transaction.displayNote {
            case "UI Test Discount Expense": return "sample-transaction-discount-expense"
            case "UI Test Transfer": return "sample-transaction-transfer"
            case "UI Test Exchange": return "sample-transaction-exchange"
            default: break
            }
        }
        if transaction.id == PreviewDataService.sampleDiningTransactionID
            || (ProcessInfo.processInfo.environment["UI_TEST_MODE"] == "1"
                && ["星巴克", "Starbucks"].contains(transaction.displayNote)) {
            return "sample-transaction-dining"
        }
        return "transaction-\(transaction.id.uuidString)"
    }
}

/// A native pan can fail before recognition when the intent is vertical. That
/// keeps the surrounding ScrollView fluid without weakening horizontal swipes.
private struct ReceiptHorizontalSwipeGesture: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(changed: changed, ended: ended)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.changed = changed
        context.coordinator.ended = ended
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation?.x
            ?? recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            context.coordinator.changed(translation)
        case .ended:
            let velocity = context.converter.localVelocity?.x
                ?? recognizer.velocity(in: recognizer.view).x
            context.coordinator.ended(translation, velocity)
        case .cancelled, .failed:
            context.coordinator.ended(translation, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var changed: (CGFloat) -> Void
        var ended: (CGFloat, CGFloat) -> Void

        init(changed: @escaping (CGFloat) -> Void, ended: @escaping (CGFloat, CGFloat) -> Void) {
            self.changed = changed
            self.ended = ended
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.05
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct ReceiptTransactionRow: View {
    let transaction: LedgerTransaction
    let currencyCode: String
    let hasAttachment: Bool

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon
                .frame(width: 38)
                .frame(maxHeight: .infinity)

            rowDetails
                .frame(maxWidth: .infinity, alignment: .leading)

            amountPanel
                .frame(minWidth: transaction.type == .exchange ? 0 : 94, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LedgerPalette.surface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(LedgerPalette.hairline, lineWidth: 1)
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if transaction.type == .transfer || transaction.type == .exchange {
            Image(systemName: transaction.type.symbolName)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(LedgerPalette.ink)
        } else if let category = transaction.category {
            CategoryIconImage(category: category, size: 36)
        } else {
            Image(systemName: transaction.type.symbolName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(LedgerPalette.ink)
        }
    }

    @ViewBuilder
    private var rowDetails: some View {
        switch transaction.type {
        case .transfer:
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.type.title)
                    .font(PensonaDashboardTypography.transactionTypeTitle)
                Text("转出 · \(transferWalletTitle(transaction.sourceWallet))")
                    .font(PensonaDashboardTypography.rowDetail)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("bill-transfer-source-account")
                Text("转入 · \(transferWalletTitle(transaction.destinationWallet))")
                    .font(PensonaDashboardTypography.rowDetail)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("bill-transfer-destination-account")
            }
        case .exchange:
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.type.title)
                    .font(PensonaDashboardTypography.transactionTypeTitle)
                Text("\(transaction.homeCategoryTitle) · \(transaction.date.formatted(date: .omitted, time: .shortened))")
                    .font(PensonaDashboardTypography.rowDetail)
                    .foregroundStyle(.secondary)
                Label(transaction.receiptFundingText ?? transaction.homeAccountName, systemImage: "creditcard")
                    .font(PensonaDashboardTypography.rowDetail)
                    .foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.category?.name ?? transaction.receiptTitle)
                    .font(PensonaDashboardTypography.rowTitle)
                Text("\(transaction.homeCategoryTitle) · \(transaction.date.formatted(date: .omitted, time: .shortened))")
                    .font(PensonaDashboardTypography.rowDetail)
                    .foregroundStyle(.secondary)
                Label(transaction.receiptFundingText ?? transaction.homeAccountName, systemImage: "creditcard")
                    .font(PensonaDashboardTypography.rowDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var amountPanel: some View {
        if transaction.type == .exchange {
            VStack(spacing: 1) {
                Text(exchangeAmount(transaction.sourceAmount ?? transaction.amount ?? 0, currency: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? currencyCode))
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("bill-exchange-source-amount")
                Image(systemName: "arrow.down")
                    .font(LedgerFont.regular(size: 14, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("bill-exchange-arrow")
                Text(exchangeAmount(transaction.destinationAmount ?? 0, currency: transaction.destinationCurrencyCode ?? currencyCode))
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("bill-exchange-destination-amount")
            }
            .fixedSize(horizontal: true, vertical: false)
            .font(PensonaDashboardTypography.exchangeAmount)
            .foregroundStyle(LedgerPalette.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        } else if transaction.type == .transfer {
            VStack(alignment: .trailing, spacing: 3) {
                Text(transferPrimaryAmount)
                    .font(PensonaDashboardTypography.rowAmount)
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .accessibilityIdentifier("bill-transfer-amount")

                if let adjustments = transferAdjustments {
                    Text(adjustments)
                        .font(PensonaDashboardTypography.rowDetail)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("bill-transfer-adjustments")
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                Text(standardPrimaryAmount)
                    .font(PensonaDashboardTypography.rowAmount)
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .accessibilityIdentifier(
                        transaction.displayNote == "UI Test Discount Expense"
                            ? "bill-discount-expense-amount"
                            : "bill-amount"
                    )

                if let adjustments = standardAdjustments {
                    Text(adjustments)
                        .font(PensonaDashboardTypography.rowDetail)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier(
                            transaction.displayNote == "UI Test Discount Expense"
                                ? "bill-discount-expense-adjustment"
                                : "bill-adjustments"
                        )
                }
            }
        }
    }

    private func transferWalletTitle(_ wallet: CurrencyWallet?) -> String {
        wallet?.account?.name ?? "未指定账户"
    }

    private var transferPrimaryAmount: String {
        let sourceCurrency = transaction.sourceCurrencyCode ?? currencyCode
        let original = transaction.sourceAmount ?? transaction.amount ?? 0
        let discount = transaction.discountAmount ?? 0
        let discountCurrency = transaction.discountCurrencyCode
            ?? transaction.discountWallet?.currencyCode
            ?? sourceCurrency
        let canApplyDiscount = discount > 0 && discountCurrency == sourceCurrency
        let netAmount = canApplyDiscount ? max(0, original - discount) : original
        return MoneyFormatter.string(netAmount, currencyCode: sourceCurrency)
    }

    private var transferAdjustments: String? {
        var details: [String] = []
        if let discount = transaction.discountAmount, discount > 0 {
            let code = transaction.discountCurrencyCode
                ?? transaction.discountWallet?.currencyCode
                ?? transaction.sourceCurrencyCode
                ?? currencyCode
            details.append("优惠 \(MoneyFormatter.string(discount, currencyCode: code))")
        }
        if let fee = transaction.feeAmount, fee > 0 {
            let code = transaction.feeCurrencyCode
                ?? transaction.feeWallet?.currencyCode
                ?? transaction.sourceCurrencyCode
                ?? currencyCode
            details.append("手续费 \(MoneyFormatter.string(fee, currencyCode: code))")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private var standardPrimaryAmount: String {
        guard transaction.type == .expense,
              transaction.originalAmount == nil,
              let discount = transaction.discountAmount,
              discount > 0 else {
            return transaction.summaryAmount
        }
        let code = transaction.sourceCurrencyCode ?? transaction.currencyCode ?? currencyCode
        let original = transaction.sourceAmount ?? transaction.amount ?? 0
        return "−" + MoneyFormatter.string(max(0, original - discount), currencyCode: code)
    }

    private var standardAdjustments: String? {
        var details: [String] = []
        if let discount = transaction.discountAmount, discount > 0 {
            let code = transaction.discountCurrencyCode
                ?? transaction.sourceCurrencyCode
                ?? transaction.currencyCode
                ?? currencyCode
            details.append("优惠：\(MoneyFormatter.string(discount, currencyCode: code))")
        }
        if let fee = transaction.feeAmount, fee > 0 {
            let code = transaction.feeCurrencyCode
                ?? transaction.sourceCurrencyCode
                ?? transaction.currencyCode
                ?? currencyCode
            details.append("手续费：\(MoneyFormatter.string(fee, currencyCode: code))")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private func exchangeAmount(_ amount: Decimal, currency: String) -> String {
        "\(MoneyFormatter.plain(amount, currencyCode: currency)) \(currency)"
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
