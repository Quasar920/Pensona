import SwiftData
import SwiftUI

/// A review-only boundary for recognition results. It deliberately receives a
/// decision, never a screenshot or OCR document, so neither can reach view state.
struct RecognitionConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]

    let book: LedgerBook
    let onSaved: ((LedgerTransaction) -> Void)?
    private let importRecord: RecognitionImportRecord?
    private let initialWalletID: UUID?
    @State private var draft: RecognitionConfirmationDraft?
    @State private var walletID: UUID?
    @State private var categoryID: UUID?
    @State private var errorMessage: String?

    init(
        decision: RecognitionDecision,
        book: LedgerBook,
        onSaved: ((LedgerTransaction) -> Void)? = nil
    ) {
        self.book = book
        self.onSaved = onSaved
        importRecord = nil
        _draft = State(initialValue: decision.confirmationDraft)
        if case let .autoEligible(walletID, _) = decision {
            initialWalletID = walletID
        } else {
            initialWalletID = nil
        }
    }

    init(
        record: RecognitionImportRecord,
        book: LedgerBook,
        onSaved: ((LedgerTransaction) -> Void)? = nil
    ) {
        self.book = book
        self.onSaved = onSaved
        importRecord = record
        _draft = State(initialValue: record.confirmationDraft)
        initialWalletID = record.selectedWalletID
    }

    private var wallets: [CurrencyWallet] {
        guard let draft else { return [] }
        return accounts
            .filter { $0.book?.id == book.id }
            .flatMap(\.enabledWallets)
            .filter { $0.currencyCode == draft.currency.rawValue }
            .sorted { ($0.account?.name ?? "", $0.currencyCode) < ($1.account?.name ?? "", $1.currencyCode) }
    }

    private var availableCategories: [LedgerCategory] {
        guard let draft else { return [] }
        let expected: CategoryKind = draft.type == .income ? .income : .expense
        return categories.filter { $0.type == expected }
    }

    private var confirmedDraftBinding: Binding<RecognitionConfirmationDraft> {
        Binding(
            get: { draft! },
            set: { draft = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section {
                            Label(reasonText(draft.decisionReason), systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                        } footer: {
                            Text("AI 结果尚未入账；保存前请核对高亮字段。")
                        }

                        if draft.isSupportedForConfirmation {
                            transactionSection
                            walletAndCategorySection
                            detailsSection
                            Section {
                                Button("确认并入账", action: save)
                                    .frame(maxWidth: .infinity)
                                    .font(.headline)
                            }
                        } else {
                            ContentUnavailableView {
                                Label("需要专门确认", systemImage: "arrow.left.arrow.right.circle")
                            } description: {
                                Text(unsupportedDescription(for: draft))
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("无法确认此识别结果", systemImage: "xmark.shield")
                }
            }
            .navigationTitle("确认识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear(perform: configureSelections)
            .alert("无法入账", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    @ViewBuilder
    private var transactionSection: some View {
        if let draft {
            Section("交易") {
                Picker("类型", selection: confirmedDraftBinding.type) {
                    Text("支出").tag(RecognizedTransactionType.expense)
                    Text("收入").tag(RecognizedTransactionType.income)
                }
                .pickerStyle(.segmented)
                TextField("金额", value: confirmedDraftBinding.paidAmount, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                LabeledContent("币种", value: draft.currency.rawValue)
                DatePicker("时间", selection: confirmedDraftBinding.occurredAt)
            }
        }
    }

    @ViewBuilder
    private var walletAndCategorySection: some View {
        if let draft {
            Section("账户与分类") {
                Picker("钱包", selection: $walletID) {
                    Text("请选择").tag(nil as UUID?)
                    ForEach(wallets) { wallet in
                        Text("\(wallet.account?.name ?? "未命名账户") · \(wallet.currencyCode)")
                            .tag(wallet.id as UUID?)
                    }
                }
                Picker("分类", selection: $categoryID) {
                    Text("未分类").tag(nil as UUID?)
                    ForEach(availableCategories) { category in
                        Label(category.name, systemImage: category.symbolName).tag(category.id as UUID?)
                    }
                }
            }
            if draft.originalAmount != nil || draft.discountAmount > 0 {
                Section("优惠信息") {
                    if let original = draft.originalAmount {
                        LabeledContent("原价", value: MoneyFormatter.plain(original, currencyCode: draft.currency.rawValue))
                    }
                    if draft.discountAmount > 0 {
                        LabeledContent("优惠", value: MoneyFormatter.plain(draft.discountAmount, currencyCode: draft.currency.rawValue))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        if draft != nil {
            Section("详情") {
                TextField("商户或交易对象", text: confirmedDraftBinding.merchantOrCounterparty)
                TextField("备注", text: confirmedDraftBinding.note, axis: .vertical)
            }
        }
    }

    private func configureSelections() {
        guard walletID == nil else { return }
        walletID = initialWalletID ?? wallets.first?.id
        if let draft, let candidate = draft.type == .income ? categories.first(where: { $0.type == .income && $0.name == "其他收入" }) : categories.first(where: { $0.type == .expense && $0.name == "其他" }) {
            categoryID = candidate.id
        }
    }

    private func save() {
        guard let draft else { return }
        guard let wallet = wallets.first(where: { $0.id == walletID }) else {
            errorMessage = "请选择与交易币种一致的钱包"
            return
        }
        let category = availableCategories.first(where: { $0.id == categoryID })
        do {
            let transaction = try RecognitionEntryService(context: context).confirm(
                draft,
                wallet: wallet,
                category: category,
                importRecord: importRecord,
                importStatus: .confirmed
            )
            onSaved?(transaction)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    private func reasonText(_ reason: RecognitionDecisionReason) -> String {
        switch reason {
        case .eligible: "请确认后入账"
        case .accountUnmatched, .accountAmbiguous, .currencyWalletMismatch: "请确认入账钱包"
        case .categoryUnmatched, .lowConfidence: "请确认分类与金额"
        case .amountRelationshipMismatch, .amountNotVisibleInOCR: "请核对金额"
        default: "此交易需要人工确认"
        }
    }

    private func unsupportedDescription(for draft: RecognitionConfirmationDraft) -> String {
        if draft.feeAmount > 0 { return "该交易包含手续费。请先在手动记账中确认手续费的钱包归属。" }
        switch draft.type {
        case .transfer: return "转账需要确认来源和目标钱包，暂不会被记成普通收支。"
        case .exchange: return "换汇需要确认换出和换入金额，暂不会被记成普通收支。"
        case .refund: return "退款需要关联原交易，暂不会被记成普通收入。"
        default: return "该识别类型还不能安全入账。"
        }
    }
}
