import SwiftData
import SwiftUI

struct EntryView: View {
    private let seed: TransactionDraft?
    private let editingTransaction: LedgerTransaction?
    private let onSaved: (() -> Void)?
    private let dismissAfterSave: Bool
    private let resetSeedDate: Bool
    private let presentationTitle: String?
    @Binding private var hasUnsavedChanges: Bool
    private let requestDismiss: (() -> Void)?
    private let requestSaveDismiss: (() -> Void)?

    init(
        seed: TransactionDraft? = nil,
        dismissAfterSave: Bool = true,
        resetSeedDate: Bool = true,
        presentationTitle: String? = nil,
        hasUnsavedChanges: Binding<Bool> = .constant(false),
        requestDismiss: (() -> Void)? = nil,
        requestSaveDismiss: (() -> Void)? = nil
    ) {
        self.seed = seed
        editingTransaction = nil
        onSaved = nil
        self.dismissAfterSave = dismissAfterSave
        self.resetSeedDate = resetSeedDate
        self.presentationTitle = presentationTitle
        _hasUnsavedChanges = hasUnsavedChanges
        self.requestDismiss = requestDismiss
        self.requestSaveDismiss = requestSaveDismiss
    }

    init(editing transaction: LedgerTransaction, onSaved: @escaping () -> Void) {
        seed = nil
        editingTransaction = transaction
        self.onSaved = onSaved
        dismissAfterSave = true
        resetSeedDate = false
        presentationTitle = AppLocalization.string("编辑账单")
        _hasUnsavedChanges = .constant(false)
        requestDismiss = nil
        requestSaveDismiss = nil
    }

    var body: some View {
        EntryLoadedView(
            seed: seed,
            editingTransaction: editingTransaction,
            onSaved: onSaved,
            dismissAfterSave: dismissAfterSave,
            resetSeedDate: resetSeedDate,
            presentationTitle: presentationTitle,
            hasUnsavedChanges: $hasUnsavedChanges,
            requestDismiss: requestDismiss,
            requestSaveDismiss: requestSaveDismiss
        )
    }
}

private struct EntryLoadedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]
    @Query(sort: \TransactionTemplate.updatedAt, order: .reverse)
    private var templates: [TransactionTemplate]
    @Query private var aaSplits: [AASplit]

    private let seed: TransactionDraft?
    private let editingTransaction: LedgerTransaction?
    private let onSaved: (() -> Void)?
    private let dismissAfterSave: Bool
    private let presentationTitle: String?
    @Binding private var hasUnsavedChanges: Bool
    private let requestDismiss: (() -> Void)?
    private let requestSaveDismiss: (() -> Void)?
    private let selectionStore = RecentEntrySelectionStore()

    @State private var form: TransactionFormState
    @State private var pendingDraft: TransactionDraft?
    @State private var pendingAASplitDraft: AASplitDraft?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showingNegativeWarning = false
    @State private var initialized = false
    @State private var pendingSaveAction: EntrySaveAction = .complete
    @State private var entrySession = EntrySessionState()

    init(
        seed: TransactionDraft? = nil,
        editingTransaction: LedgerTransaction? = nil,
        onSaved: (() -> Void)? = nil,
        dismissAfterSave: Bool = true,
        resetSeedDate: Bool = true,
        presentationTitle: String? = nil,
        hasUnsavedChanges: Binding<Bool> = .constant(false),
        requestDismiss: (() -> Void)? = nil,
        requestSaveDismiss: (() -> Void)? = nil
    ) {
        self.seed = seed
        self.editingTransaction = editingTransaction
        self.onSaved = onSaved
        self.dismissAfterSave = dismissAfterSave
        self.presentationTitle = presentationTitle
        _hasUnsavedChanges = hasUnsavedChanges
        self.requestDismiss = requestDismiss
        self.requestSaveDismiss = requestSaveDismiss
        var initialState = editingTransaction.map(TransactionFormState.init(transaction:))
            ?? seed.map(TransactionFormState.init(draft:))
            ?? TransactionFormState()
        if seed != nil, resetSeedDate {
            initialState.removeImportedMetadataForCopy()
        }
        _form = State(initialValue: initialState)
        if let editingTransaction, let bookID = editingTransaction.bookID {
            _entrySession = State(initialValue: EntrySessionState(
                mode: .edit(transactionID: editingTransaction.id, bookID: bookID)
            ))
        } else {
            _entrySession = State(initialValue: EntrySessionState())
        }
    }

    private var selectedBook: LedgerBook? {
        if let bookID = editingTransaction?.bookID {
            return books.first { $0.id == bookID }
        }
        return books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var allWallets: [CurrencyWallet] {
        guard selectedBook != nil else { return [] }
        return accounts
            .filter { !$0.isArchived }
            .flatMap(\.enabledWallets)
            .sorted {
                let left = $0.account?.name ?? ""
                let right = $1.account?.name ?? ""
                return left == right ? $0.currencyCode < $1.currencyCode : left < right
            }
    }

    private var filteredCategories: [LedgerCategory] {
        let type: CategoryKind = form.kind == .income ? .income : .expense
        return scopedCategories.filter { $0.type == type }
    }

    private var defaultCategory: LedgerCategory? {
        let roots = filteredCategories.filter { $0.parentID == nil }
        return (roots.isEmpty ? filteredCategories : roots).sorted {
            $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder
        }.first
    }

    private var scopedCategories: [LedgerCategory] {
        guard selectedBook != nil else { return [] }
        return categories.filter { !$0.isArchived || $0.id == editingTransaction?.category?.id }
    }

    private var scopedTemplates: [TransactionTemplate] {
        guard let bookID = selectedBook?.id else { return [] }
        return templates.filter { $0.bookID == bookID && !$0.isArchived }
    }

    private var destinationOptions: [CurrencyWallet] {
        guard let source = wallet(id: form.sourceWalletID) else { return [] }
        return allWallets.filter { candidate in
            guard candidate.id != source.id else { return false }
            if form.kind == .transfer {
                return candidate.currencyCode == source.currencyCode
            }
            if form.kind == .exchange {
                return candidate.currencyCode != source.currencyCode
            }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                if allWallets.isEmpty {
                    ContentUnavailableView {
                        Label("还不能记账", systemImage: "plus.circle")
                    } description: {
                        Text("请先在“资产”中创建账户并添加至少一个币种。")
                    }
                    .padding(24)
                } else {
                    EntryComposerView(
                        state: $form,
                        wallets: allWallets,
                        categories: scopedCategories,
                        validation: entrySession.validation,
                        successMessage: successMessage,
                        showsNextEntry: seed == nil && editingTransaction == nil,
                        isSaving: entrySession.isSubmitting,
                        nextEntry: { validateAndSave(.next) },
                        complete: { validateAndSave(.complete) }
                    )
                }
            }
            .navigationTitle(
                presentationTitle
                    ?? (seed == nil ? AppLocalization.string("记账") : AppLocalization.string("复制交易"))
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { requestDismiss?() ?? dismiss() }
                        .accessibilityIdentifier("entry-close-button")
                }
                if seed == nil, editingTransaction == nil, !scopedTemplates.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(scopedTemplates) { template in
                                Button(template.name) { applyTemplate(template) }
                            }
                        } label: {
                            Label("模板", systemImage: "square.on.square")
                        }
                    }
                }
            }
            .onAppear(perform: initializeSelections)
            .onChange(of: form.hasUserEnteredContent) { _, hasContent in
                hasUnsavedChanges = hasContent
            }
            .onChange(of: form.kind) { oldKind, newKind in
                guard oldKind != newKind else { return }
                entrySession.validation.clear()
                form.prepareForKindChange()
                applyRecentOrDefaultSelections()
                successMessage = nil
            }
            .onChange(of: form.sourceWalletID) { _, _ in
                entrySession.validation.set(nil, for: .sourceWallet)
                form.synchronizePrimaryPaymentWallet()
                ensureDestinationAndFeeSelections()
            }
            .onChange(of: form.includesFee) { _, includesFee in
                if includesFee, wallet(id: form.feeWalletID) == nil {
                    form.feeWalletID = form.sourceWalletID
                }
            }
            .onChange(of: form.amountText) { _, _ in
                entrySession.validation.set(nil, for: .amount)
            }
            .onChange(of: form.destinationAmountText) { _, _ in
                entrySession.validation.set(nil, for: .destinationAmount)
            }
            .onChange(of: form.destinationWalletID) { _, _ in
                entrySession.validation.set(nil, for: .destinationWallet)
            }
            .onChange(of: form.categoryID) { _, _ in
                entrySession.validation.set(nil, for: .category)
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? AppLocalization.string("未知错误"))
            }
            .confirmationDialog(
                "保存后有钱包余额将变为负数",
                isPresented: $showingNegativeWarning,
                titleVisibility: .visible
            ) {
                Button("仍然保存", role: .destructive, action: performSave)
                Button("取消", role: .cancel) {
                    pendingDraft = nil
                    pendingAASplitDraft = nil
                    entrySession.finishSubmission()
                }
            } message: {
                Text("应用允许负余额，但请确认金额和钱包选择无误。")
            }
        }
    }

    private func initializeSelections() {
        guard !initialized else { return }
        #if DEBUG
        if seed == nil,
           let rawKind = ProcessInfo.processInfo.environment["ENTRY_PREVIEW_KIND"],
           let previewKind = TransactionKind(rawValue: rawKind) {
            form.kind = previewKind
        }
        #endif
        if editingTransaction != nil {
            // Edit mode is permanently scoped to the transaction's original book.
        } else if let seedBookID = seed?.bookID,
           books.contains(where: { $0.id == seedBookID }) {
            selectedBookID = seedBookID.uuidString
        } else if let first = books.first,
                  !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }

        if let editingTransaction {
            if let split = aaSplits.first(where: { $0.originalTransactionID == editingTransaction.id }) {
                form.aaSplitDraft = AASplitDraft(
                    split: split,
                    totalAmount: editingTransaction.sourceAmount ?? editingTransaction.amount ?? 0
                )
            }
            ensureSeedSelections()
        } else if seed == nil {
            applyRecentOrDefaultSelections()
        } else {
            ensureSeedSelections()
        }
        #if DEBUG
        if let amount = ProcessInfo.processInfo.environment["ENTRY_PREVIEW_AMOUNT"] {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                form.amountText = amount
                if form.kind == .exchange {
                    form.exchangeRateText = "0.12820513"
                    form.destinationAmountText = "100"
                }
                if ProcessInfo.processInfo.environment["ENTRY_PREVIEW_AUTOSAVE"] == "1" {
                    try? await Task.sleep(for: .milliseconds(180))
                    validateAndSave(.complete)
                }
            }
        }
        #endif
        initialized = true
        hasUnsavedChanges = form.hasUserEnteredContent
    }

    private func applyRecentOrDefaultSelections() {
        guard let bookID = selectedBook?.id else { return }
        let recent = selectionStore.selection(bookID: bookID, kind: form.kind)

        if wallet(id: form.sourceWalletID) == nil {
            form.sourceWalletID = wallet(id: recent.sourceWalletID)?.id ?? allWallets.first?.id
        }

        if form.kind == .expense || form.kind == .income {
            if !filteredCategories.contains(where: { $0.id == form.categoryID }) {
                form.categoryID = filteredCategories.first(where: { $0.id == recent.categoryID })?.id
                    ?? defaultCategory?.id
            }
        } else {
            form.categoryID = nil
        }

        if form.kind == .transfer || form.kind == .exchange {
            form.destinationWalletID = destinationOptions.first(where: { $0.id == recent.destinationWalletID })?.id
                ?? destinationOptions.first?.id
            form.feeWalletID = wallet(id: recent.feeWalletID)?.id ?? form.sourceWalletID
        } else {
            form.destinationWalletID = nil
            form.feeWalletID = nil
        }
    }

    private func ensureSeedSelections() {
        if wallet(id: form.sourceWalletID) == nil {
            form.sourceWalletID = allWallets.first?.id
        }
        if (form.kind == .expense || form.kind == .income),
           let categoryID = form.categoryID,
           !filteredCategories.contains(where: { $0.id == categoryID }) {
            form.categoryID = nil
        }
        ensureDestinationAndFeeSelections()
    }

    private func ensureDestinationAndFeeSelections() {
        if form.kind == .transfer || form.kind == .exchange {
            if !destinationOptions.contains(where: { $0.id == form.destinationWalletID }) {
                form.destinationWalletID = destinationOptions.first?.id
            }
            if wallet(id: form.feeWalletID) == nil {
                form.feeWalletID = form.sourceWalletID
            }
        } else {
            form.destinationWalletID = nil
            form.feeWalletID = nil
        }
    }

    private func validateAndSave(_ action: EntrySaveAction) {
        guard entrySession.validate(
            form: form,
            wallets: allWallets,
            categories: scopedCategories
        ) else { return }
        guard entrySession.beginSubmission(intent: action == .next ? .next : .complete) else { return }
        successMessage = nil
        pendingSaveAction = action
        do {
            let draft = try form.makeDraft(wallets: allWallets, categories: scopedCategories)
            let resolvedAASplit: AASplitDraft?
            if let aaDraft = form.aaSplitDraft {
                let code = draft.sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue
                resolvedAASplit = try AASplitCalculator().resolvedDraft(
                    aaDraft,
                    totalAmount: draft.amount,
                    currencyCode: code
                )
            } else {
                resolvedAASplit = nil
            }
            pendingDraft = draft
            pendingAASplitDraft = resolvedAASplit
            if try createsNegativeBalance(draft) {
                showingNegativeWarning = true
            } else {
                performSave()
            }
        } catch {
            pendingDraft = nil
            pendingAASplitDraft = nil
            entrySession.finishSubmission(error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func performSave() {
        guard let draft = pendingDraft else { return }
        do {
            let aaDraft = pendingAASplitDraft
            if let editingTransaction {
                try LedgerService(context: context).replaceTransaction(editingTransaction, with: draft) { updated in
                    let service = AASplitService(context: context)
                    if let aaDraft {
                        try service.upsert(aaDraft, for: updated, save: false)
                    } else {
                        try service.remove(from: updated, save: false)
                    }
                }
            } else {
                guard let bookID = selectedBook?.id else { throw LedgerError.missingBook }
                try LedgerService(context: context).create(draft, bookID: bookID) { transaction in
                    if let aaDraft {
                        try AASplitService(context: context).upsert(
                            aaDraft,
                            for: transaction,
                            save: false
                        )
                    }
                }
            }
            if editingTransaction == nil { rememberSelections() }
            pendingDraft = nil
            pendingAASplitDraft = nil
            if editingTransaction != nil {
                HapticFeedbackService().notification(.success)
                hasUnsavedChanges = false
                dismiss()
                onSaved?()
            } else if pendingSaveAction == .complete && dismissAfterSave {
                hasUnsavedChanges = false
                HapticFeedbackService().notification(.success)
                // 完成路径保持 submitting，防止收拢动画期间重复点击造成重复写入
                requestSaveDismiss?() ?? requestDismiss?() ?? dismiss()
            } else {
                form.resetForContinuousEntry()
                hasUnsavedChanges = false
                ensureDestinationAndFeeSelections()
                entrySession.finishSubmission()
                successMessage = AppLocalization.string("已记下一笔")
            }
        } catch {
            pendingDraft = nil
            pendingAASplitDraft = nil
            entrySession.finishSubmission(error: error)
            errorMessage = error.localizedDescription
        }
    }

    private func rememberSelections() {
        guard let bookID = selectedBook?.id else { return }
        selectionStore.save(
            RecentEntrySelection(
                sourceWalletID: form.sourceWalletID,
                destinationWalletID: form.destinationWalletID,
                categoryID: form.categoryID,
                feeWalletID: form.feeWalletID
            ),
            bookID: bookID,
            kind: form.kind
        )
    }

    private func createsNegativeBalance(_ replacement: TransactionDraft) throws -> Bool {
        guard let editingTransaction else {
            return try TransactionImpactCalculator().deltas(for: replacement).contains {
                $0.wallet.balance + $0.amount < 0
            }
        }
        let calculator = TransactionImpactCalculator()
        let oldDeltas = try calculator.deltas(for: TransactionDraft(transaction: editingTransaction))
        let newDeltas = try calculator.deltas(for: replacement)
        var projected: [UUID: Decimal] = [:]
        for delta in oldDeltas + newDeltas { projected[delta.wallet.id] = delta.wallet.balance }
        for delta in oldDeltas { projected[delta.wallet.id, default: delta.wallet.balance] -= delta.amount }
        for delta in newDeltas { projected[delta.wallet.id, default: delta.wallet.balance] += delta.amount }
        return projected.values.contains { $0 < 0 }
    }

    private func wallet(id: UUID?) -> CurrencyWallet? {
        guard let id else { return nil }
        return allWallets.first { $0.id == id }
    }

    private func applyTemplate(_ template: TransactionTemplate) {
        do {
            let draft = try TransactionTemplateService(context: context).resolve(
                template,
                wallets: allWallets,
                categories: scopedCategories
            )
            form = TransactionFormState(draft: draft)
            ensureSeedSelections()
            successMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum EntrySaveAction {
    case next
    case complete
}
