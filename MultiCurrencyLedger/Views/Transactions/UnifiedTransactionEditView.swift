import SwiftData
import SwiftUI

struct TransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: [SortDescriptor(\LedgerCategory.typeRawValue), SortDescriptor(\LedgerCategory.sortOrder)])
    private var categories: [LedgerCategory]
    @Query private var aaSplits: [AASplit]

    let transaction: LedgerTransaction
    let onSaved: () -> Void

    @State private var form: TransactionFormState
    @State private var pendingDraft: TransactionDraft?
    @State private var pendingAASplitDraft: AASplitDraft?
    @State private var errorMessage: String?
    @State private var showingNegativeWarning = false
    @State private var loadedAASplit = false

    init(transaction: LedgerTransaction, onSaved: @escaping () -> Void) {
        self.transaction = transaction
        self.onSaved = onSaved
        _form = State(initialValue: TransactionFormState(transaction: transaction))
    }

    private var bookID: UUID? {
        transaction.sourceAccount?.book?.id ?? transaction.destinationAccount?.book?.id
    }

    private var allWallets: [CurrencyWallet] {
        accounts
            .filter { !$0.isArchived && (bookID == nil || $0.book?.id == bookID) }
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
        guard let bookID else { return categories.filter { !$0.isArchived } }
        return categories.filter {
            (!$0.isArchived || $0.id == transaction.category?.id)
                && ($0.bookID == nil || $0.bookID == bookID)
        }
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
                TransactionFormSections(
                    state: $form,
                    wallets: allWallets,
                    categories: scopedCategories
                )

                Section {
                    Text("保存时会原子回滚原交易，再应用修改后的类型、账户、分类、商户、金额与手续费。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: validateAndSave)
                }
            }
            .onAppear(perform: ensureSelections)
            .onChange(of: form.kind) { oldKind, newKind in
                guard oldKind != newKind else { return }
                form.prepareForKindChange()
                applyDefaultsForKind()
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
                Button("取消", role: .cancel) {
                    pendingDraft = nil
                    pendingAASplitDraft = nil
                }
            }
        }
    }

    private func ensureSelections() {
        if !loadedAASplit {
            if let split = aaSplits.first(where: { $0.originalTransactionID == transaction.id }) {
                form.aaSplitDraft = AASplitDraft(
                    split: split,
                    totalAmount: transaction.sourceAmount ?? transaction.amount ?? 0
                )
            }
            loadedAASplit = true
        }
        if wallet(id: form.sourceWalletID) == nil {
            form.sourceWalletID = allWallets.first?.id
        }
        if let categoryID = form.categoryID,
           !filteredCategories.contains(where: { $0.id == categoryID }) {
            form.categoryID = nil
        }
        ensureDestinationAndFeeSelections()
    }

    private func applyDefaultsForKind() {
        if form.kind == .expense || form.kind == .income {
            form.categoryID = filteredCategories.first?.id
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
            errorMessage = error.localizedDescription
        }
    }

    private func createsNegativeBalance(_ replacement: TransactionDraft) throws -> Bool {
        let calculator = TransactionImpactCalculator()
        let oldDeltas = try calculator.deltas(for: TransactionDraft(transaction: transaction))
        let newDeltas = try calculator.deltas(for: replacement)
        var projectedBalances: [UUID: Decimal] = [:]

        for delta in oldDeltas + newDeltas {
            projectedBalances[delta.wallet.id] = delta.wallet.balance
        }
        for delta in oldDeltas {
            projectedBalances[delta.wallet.id, default: delta.wallet.balance] -= delta.amount
        }
        for delta in newDeltas {
            projectedBalances[delta.wallet.id, default: delta.wallet.balance] += delta.amount
        }
        return projectedBalances.values.contains(where: { $0 < 0 })
    }

    private func performSave() {
        guard let draft = pendingDraft else { return }
        do {
            let aaDraft = pendingAASplitDraft
            try LedgerService(context: context).replaceTransaction(
                transaction,
                with: draft
            ) { updatedTransaction in
                let service = AASplitService(context: context)
                if let aaDraft {
                    try service.upsert(aaDraft, for: updatedTransaction, save: false)
                } else {
                    try service.remove(from: updatedTransaction, save: false)
                }
            }
            pendingDraft = nil
            pendingAASplitDraft = nil
            dismiss()
            onSaved()
        } catch {
            pendingDraft = nil
            pendingAASplitDraft = nil
            errorMessage = error.localizedDescription
        }
    }

    private func wallet(id: UUID?) -> CurrencyWallet? {
        guard let id else { return nil }
        return allWallets.first { $0.id == id }
    }
}
