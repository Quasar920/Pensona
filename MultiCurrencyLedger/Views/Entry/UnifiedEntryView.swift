import SwiftData
import SwiftUI

struct EntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]
    @Query(sort: \TransactionTag.name) private var tags: [TransactionTag]
    @Query(sort: \TransactionTemplate.updatedAt, order: .reverse)
    private var templates: [TransactionTemplate]

    private let seed: TransactionDraft?
    private let dismissAfterSave: Bool
    private let selectionStore = RecentEntrySelectionStore()

    @State private var form: TransactionFormState
    @State private var pendingDraft: TransactionDraft?
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showingNegativeWarning = false
    @State private var initialized = false

    init(seed: TransactionDraft? = nil, dismissAfterSave: Bool = false) {
        self.seed = seed
        self.dismissAfterSave = dismissAfterSave
        var initialState = seed.map(TransactionFormState.init(draft:)) ?? TransactionFormState()
        if seed != nil {
            initialState.removeImportedMetadataForCopy()
        }
        _form = State(initialValue: initialState)
    }

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var allWallets: [CurrencyWallet] {
        guard let bookID = selectedBook?.id else { return [] }
        return accounts
            .filter { $0.book?.id == bookID }
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

    private var scopedCategories: [LedgerCategory] {
        guard let bookID = selectedBook?.id else { return [] }
        return categories.filter {
            !$0.isArchived && ($0.bookID == nil || $0.bookID == bookID)
        }
    }

    private var scopedTags: [TransactionTag] {
        guard let bookID = selectedBook?.id else { return [] }
        return tags.filter { $0.bookID == bookID && !$0.isArchived }
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
                    TransactionFormSections(
                        state: $form,
                        wallets: allWallets,
                        categories: scopedCategories,
                        tags: scopedTags
                    )

                    Section {
                        Button("保存\(form.kind.title)", action: validateAndSave)
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
            .navigationTitle(seed == nil ? "记账" : "复制交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if seed == nil, !scopedTemplates.isEmpty {
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
            .onChange(of: form.kind) { oldKind, newKind in
                guard oldKind != newKind else { return }
                form.prepareForKindChange()
                applyRecentOrDefaultSelections()
                successMessage = nil
            }
            .onChange(of: form.sourceWalletID) { _, _ in
                form.synchronizePrimaryPaymentWallet()
                ensureDestinationAndFeeSelections()
            }
            .onChange(of: form.includesFee) { _, includesFee in
                if includesFee, wallet(id: form.feeWalletID) == nil {
                    form.feeWalletID = form.sourceWalletID
                }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .confirmationDialog(
                "保存后有钱包余额将变为负数",
                isPresented: $showingNegativeWarning,
                titleVisibility: .visible
            ) {
                Button("仍然保存", role: .destructive, action: performSave)
                Button("取消", role: .cancel) { pendingDraft = nil }
            } message: {
                Text("应用允许负余额，但请确认金额和钱包选择无误。")
            }
        }
    }

    private func initializeSelections() {
        guard !initialized else { return }
        if let seedBookID = seed?.sourceWallet?.account?.book?.id,
           books.contains(where: { $0.id == seedBookID }) {
            selectedBookID = seedBookID.uuidString
        } else if let first = books.first,
                  !books.contains(where: { $0.id.uuidString == selectedBookID }) {
            selectedBookID = first.id.uuidString
        }

        if seed == nil {
            applyRecentOrDefaultSelections()
        } else {
            ensureSeedSelections()
        }
        initialized = true
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
                    ?? filteredCategories.first?.id
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

    private func validateAndSave() {
        successMessage = nil
        do {
            let draft = try form.makeDraft(
                wallets: allWallets,
                categories: scopedCategories,
                tags: scopedTags
            )
            let deltas = try TransactionImpactCalculator().deltas(for: draft)
            pendingDraft = draft
            if deltas.contains(where: { $0.wallet.balance + $0.amount < 0 }) {
                showingNegativeWarning = true
            } else {
                performSave()
            }
        } catch {
            pendingDraft = nil
            errorMessage = error.localizedDescription
        }
    }

    private func performSave() {
        guard let draft = pendingDraft else { return }
        do {
            try LedgerService(context: context).create(draft)
            rememberSelections()
            pendingDraft = nil
            if dismissAfterSave {
                dismiss()
            } else {
                form.resetForContinuousEntry()
                ensureDestinationAndFeeSelections()
                successMessage = "已保存，可继续记账"
            }
        } catch {
            pendingDraft = nil
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

    private func wallet(id: UUID?) -> CurrencyWallet? {
        guard let id else { return nil }
        return allWallets.first { $0.id == id }
    }

    private func applyTemplate(_ template: TransactionTemplate) {
        do {
            let draft = try TransactionTemplateService(context: context).resolve(
                template,
                wallets: allWallets,
                categories: scopedCategories,
                tags: scopedTags
            )
            form = TransactionFormState(draft: draft)
            ensureSeedSelections()
            successMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
