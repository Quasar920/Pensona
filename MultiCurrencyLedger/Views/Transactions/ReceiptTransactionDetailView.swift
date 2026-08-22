import SwiftData
import SwiftUI

/// Read-only receipt used by the ledger page. Editing remains an explicit
/// hand-off to the existing editor instead of turning this detail surface into
/// a second form.
struct ReceiptTransactionDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    let transaction: LedgerTransaction
    let sourceFrame: CGRect
    let close: () -> Void
    let edit: () -> Void

    @State private var isChangingBook = false
    @State private var showingTemplateName = false
    @State private var templateName = ""
    @State private var showingRefund = false
    @State private var errorMessage: String?
    @State private var isExpanded = false
    @State private var isDismissing = false

    private let transitionAnimation = Animation.timingCurve(
        0.22,
        0.90,
        0.24,
        1,
        duration: 0.45
    )
    /// Closing is intentionally a single, vertical motion.  Scaling a fully
    /// rendered receipt back into its source card creates overlapping content
    /// while the list is visible underneath it.
    private let dismissalAnimation = Animation.timingCurve(
        0.22,
        0.90,
        0.24,
        1,
        duration: 0.45
    )

    private var activeBooks: [LedgerBook] { books.filter { !$0.isArchived } }
    private var isExchange: Bool { transaction.type == .exchange }
    private var currencyCode: String { transaction.sourceCurrencyCode ?? transaction.currencyCode ?? "CNY" }
    private var destinationCurrencyCode: String { transaction.destinationCurrencyCode ?? currencyCode }
    private var accountText: String { transaction.receiptFundingText ?? transaction.homeAccountName }
    private var amountText: String { transaction.summaryAmount }
    private var canRefund: Bool { transaction.type == .expense }
    private var refundWallets: [CurrencyWallet] {
        accounts
            .filter { !$0.isArchived }
            .flatMap(\.enabledWallets)
            .filter { $0.currencyCode == currencyCode }
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasFrame = proxy.frame(in: .global)
            let headerTopInset = max(proxy.safeAreaInsets.top, 44) + 3
            // The animated destination must never depend on the safe-area
            // layout pass. Doing so changes the sheet's bounds mid-animation,
            // which is what produced the top/bottom gap then a visible jump.
            let targetFrame = CGRect(
                x: canvasFrame.minX,
                y: canvasFrame.minY,
                width: canvasFrame.width,
                height: max(1, canvasFrame.height)
            )
            let source = sourceFrame.isEmpty ? targetFrame : sourceFrame
            let initialScaleX = max(0.01, source.width / max(targetFrame.width, 1))
            let initialScaleY = max(0.01, source.height / max(targetFrame.height, 1))
            let initialOffsetX = source.midX - targetFrame.midX
            let initialOffsetY = source.minY - targetFrame.minY

            ZStack {
                Color.black
                    .opacity(isExpanded && !isDismissing ? 0.32 : 0)
                    .ignoresSafeArea()

                receiptSurface(headerTopInset: headerTopInset)
                    .frame(width: targetFrame.width, height: targetFrame.height)
                    .position(
                        x: targetFrame.midX - canvasFrame.minX,
                        y: targetFrame.midY - canvasFrame.minY
                    )
                    .scaleEffect(
                        x: isExpanded || isDismissing ? 1 : initialScaleX,
                        y: isExpanded || isDismissing ? 1 : initialScaleY,
                        anchor: .top
                    )
                    .offset(x: isExpanded || isDismissing ? 0 : initialOffsetX)
                    .offset(
                        y: isDismissing
                            ? targetFrame.height + 24
                            : (isExpanded ? 0 : initialOffsetY)
                    )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(transitionAnimation) {
                isExpanded = true
            }
        }
        .environment(\.colorScheme, .light)
        .confirmationDialog("变更账本", isPresented: $isChangingBook, titleVisibility: .visible) {
            ForEach(activeBooks) { book in
                Button(book.name) { changeBook(to: book) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("变更账本不会修改这笔交易的金额或账户。")
        }
        .alert("保存为模板", isPresented: $showingTemplateName) {
            TextField("模板名称", text: $templateName)
            Button("取消", role: .cancel) {}
            Button("保存", action: saveAsTemplate)
        } message: {
            Text("模板会保存当前交易的账户、分类和金额，使用时仍需确认后入账。")
        }
        .sheet(isPresented: $showingRefund) {
            TransactionRelationEntryView(
                original: transaction,
                kind: .refund,
                wallets: refundWallets,
                onSaved: {
                    showingRefund = false
                    dismiss()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .accessibilityIdentifier("receipt-transaction-detail")
    }

    private func receiptSurface(headerTopInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            receiptHeader(topInset: headerTopInset)

            ScrollView {
                VStack(spacing: 0) {
                    ReceiptDetailDivider()
                    factsSection
                    ReceiptDetailDivider()
                    categorySection
                    ReceiptDetailDivider()
                    amountSection
                    ReceiptDetailDivider()
                    metadataSection
                    ReceiptDetailDivider()
                    timestamps
                    actionRows
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 38)
            }
            .scrollIndicators(.hidden)
        }
        .background(ReceiptDetailPalette.paper)
    }

    private func receiptHeader(topInset: CGFloat) -> some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .frame(width: LedgerLayout.minimumHitSize, height: LedgerLayout.minimumHitSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭账单详情")
                Spacer()
            }
            Text("账单详情")
                .font(.headline.weight(.bold))
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset)
        .padding(.bottom, 12)
    }

    private var factsSection: some View {
        VStack(spacing: 13) {
            ReceiptDetailRow(title: "时间", value: transaction.date.formatted(date: .long, time: .shortened))
            ReceiptDetailRow(title: "账户", value: accountText)
            ReceiptDetailRow(title: "备注", value: transaction.displayNote ?? "—")
        }
        .padding(.vertical, 18)
    }

    private var categorySection: some View {
        ReceiptDetailRow(title: "分类", value: transaction.homeCategoryTitle)
        .padding(.vertical, 18)
    }

    private var amountSection: some View {
        Group {
            if isExchange {
                VStack(spacing: 7) {
                    Text("购汇")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(exchangeAmountText(transaction.sourceAmount ?? transaction.amount ?? 0, currencyCode: currencyCode))
                        .font(.system(size: 29, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "arrow.down")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(exchangeAmountText(transaction.destinationAmount ?? 0, currencyCode: destinationCurrencyCode))
                        .font(.system(size: 29, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } else {
                VStack(spacing: 6) {
                    Text(transaction.type.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(amountText)
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(currencyCode)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isExchange ? 20 : 24)
    }

    private var metadataSection: some View {
        Group {
            if isExchange {
                VStack(spacing: 13) {
                    ReceiptDetailRow(title: "优惠", value: exchangeFactText(transaction.discountAmount, currencyCode: transaction.discountCurrencyCode ?? currencyCode))
                    ReceiptDetailRow(title: "手续费", value: exchangeFactText(transaction.feeAmount, currencyCode: transaction.feeCurrencyCode ?? currencyCode))
                }
            } else {
                VStack(spacing: 13) {
                    ReceiptDetailRow(title: "优惠", value: transaction.receiptOfferText(currencyCode: currencyCode) ?? "无优惠")
                    ReceiptDetailRow(title: "组合支付", value: transaction.paymentParts.count > 1 ? "组合支付" : "单独支付")
                    ReceiptDetailRow(title: "报销", value: transaction.reimbursementStatus == .pending ? "待报销" : "未报销")
                    ReceiptDetailRow(title: "AA", value: "不参与 AA")
                }
            }
        }
        .padding(.vertical, 18)
    }

    private var timestamps: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("创建于 \(transaction.createdAt.formatted(date: .long, time: .shortened))")
            Text("最后修改于 \(transaction.updatedAt.formatted(date: .long, time: .shortened))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }

    private var actionRows: some View {
        VStack(spacing: 9) {
            ReceiptDetailActionRow(title: "编辑") { dismiss(then: edit) }
            ReceiptDetailActionRow(title: "变更账本") { isChangingBook = true }
            ReceiptDetailActionRow(title: "币种") { dismiss(then: edit) }
            ReceiptDetailActionRow(title: "设为模板") {
                templateName = transaction.merchantOrCounterparty ?? transaction.receiptTitle
                showingTemplateName = true
            }
            ReceiptDetailActionRow(title: "退款") { showingRefund = true }
                .disabled(!canRefund)
                .opacity(canRefund ? 1 : 0.42)
        }
    }

    private func changeBook(to book: LedgerBook) {
        do {
            transaction.bookID = book.id
            transaction.updatedAt = .now
            try context.save()
            NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsTemplate() {
        do {
            guard let bookID = transaction.bookID else { throw LedgerError.missingBook }
            try TransactionTemplateService(context: context).create(
                name: templateName,
                bookID: bookID,
                from: TransactionDraft(transaction: transaction)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exchangeAmountText(_ amount: Decimal, currencyCode: String) -> String {
        "\(MoneyFormatter.plain(amount, currencyCode: currencyCode)) \(currencyCode)"
    }

    private func exchangeFactText(_ amount: Decimal?, currencyCode: String) -> String {
        guard let amount, amount != 0 else { return "0" }
        return MoneyFormatter.plain(amount, currencyCode: currencyCode)
    }

    private func dismiss(then action: @escaping () -> Void = {}) {
        guard !isDismissing else { return }
        withAnimation(dismissalAnimation) {
            // Keep the receipt at full size and take it straight down. This
            // prevents the detail content from being compressed over cards.
            isDismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            close()
            action()
        }
    }
}

private struct ReceiptDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 14)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private struct ReceiptDetailActionRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(ReceiptDetailPalette.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ReceiptDetailPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ReceiptDetailPalette.border, lineWidth: 1)
            }
        }
        .buttonStyle(LedgerGlassPressStyle())
    }
}

private struct ReceiptDetailDivider: View {
    var body: some View {
        Rectangle()
            .stroke(ReceiptDetailPalette.dash, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .frame(height: 1)
    }
}

private enum ReceiptDetailPalette {
    static let paper = Color(red: 247 / 255, green: 245 / 255, blue: 239 / 255)
    static let surface = Color(red: 243 / 255, green: 241 / 255, blue: 235 / 255)
    static let ink = Color(red: 26 / 255, green: 26 / 255, blue: 25 / 255)
    static let border = Color(red: 208 / 255, green: 206 / 255, blue: 200 / 255)
    static let handle = Color(red: 199 / 255, green: 197 / 255, blue: 190 / 255)
    static let dash = Color.black.opacity(0.46)
}
