import SwiftUI

/// Compact native form retained for schedule/template configuration. Interactive
/// create and edit flows use `EntryComposerView` below and the split glass components.
struct TransactionFormSections: View {
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]

    private var sourceWallet: CurrencyWallet? { wallets.first { $0.id == state.sourceWalletID } }
    private var filteredCategories: [LedgerCategory] {
        let kind: CategoryKind = state.kind == .income ? .income : .expense
        return categories.filter { $0.type == kind && !$0.isArchived }
    }
    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter {
            guard $0.id != sourceWallet.id else { return false }
            return state.kind == .transfer
                ? $0.currencyCode == sourceWallet.currencyCode
                : $0.currencyCode != sourceWallet.currencyCode
        }
    }

    @ViewBuilder
    var body: some View {
        Section("交易类型") {
            Picker("类型", selection: $state.kind) {
                ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        Section(state.kind == .exchange ? "卖出金额" : "金额") {
            TextField("0", text: $state.amountText).keyboardType(.decimalPad)
            if state.kind == .exchange {
                TextField("买入金额", text: $state.destinationAmountText).keyboardType(.decimalPad)
                TextField("汇率", text: $state.exchangeRateText).keyboardType(.decimalPad)
            }
        }
        Section("账户") {
            Picker(state.kind == .transfer || state.kind == .exchange ? "转出" : "账户", selection: $state.sourceWalletID) {
                Text("请选择").tag(nil as UUID?)
                ForEach(wallets) { Text(walletTitle($0)).tag($0.id as UUID?) }
            }
            if state.kind == .transfer || state.kind == .exchange {
                Picker("转入", selection: $state.destinationWalletID) {
                    Text("请选择").tag(nil as UUID?)
                    ForEach(destinationOptions) { Text(walletTitle($0)).tag($0.id as UUID?) }
                }
                Toggle("包含手续费", isOn: $state.includesFee)
                if state.includesFee {
                    TextField("手续费", text: $state.feeText).keyboardType(.decimalPad)
                }
            }
        }
        if state.kind == .expense || state.kind == .income {
            Section("分类") {
                Picker("分类", selection: $state.categoryID) {
                    Text("请选择").tag(nil as UUID?)
                    ForEach(filteredCategories) { Text($0.name).tag($0.id as UUID?) }
                }
            }
        }
        if state.kind == .adjustment {
            Section("余额调整") {
                Picker("输入方式", selection: $state.adjustmentInputMode) {
                    ForEach(AdjustmentInputMode.allCases) { Text($0.title).tag($0) }
                }
                if state.adjustmentInputMode == .delta {
                    Picker("方向", selection: $state.adjustmentDirection) {
                        ForEach(AdjustmentDirection.allCases) { Text($0.title).tag($0) }
                    }
                }
                TextField("调整原因", text: $state.adjustmentReason)
            }
        }
        Section("详情") {
            DatePicker("日期与时间", selection: $state.date)
            TextField("交易对方", text: $state.merchantOrCounterparty)
            TextField("备注", text: $state.note, axis: .vertical)
        }
    }

    private func walletTitle(_ wallet: CurrencyWallet) -> String {
        "\(wallet.account?.name ?? AppLocalization.string("未知账户")) · \(wallet.currencyCode)"
    }
}

struct EntryComposerView: View {
    @Environment(\.locale) private var locale
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]
    let validation: EntryValidationState
    let successMessage: String?
    let showsNextEntry: Bool
    let isSaving: Bool
    let nextEntry: () -> Void
    let complete: () -> Void

    @State private var showingSourceWallets = false
    @State private var showingDestinationWallets = false
    @State private var showingDatePicker = false
    @State private var showingMore = false
    @State private var showingDiscount = false
    @State private var showingAA = false
    @State private var activeAmount: EntryAmountTarget = .source
    @State private var keypadResetID = UUID()
    @State private var categoryReordering = false
    @State private var categoryManagementOverlay = false

    private var sourceWallet: CurrencyWallet? { wallets.first { $0.id == state.sourceWalletID } }
    private var destinationWallet: CurrencyWallet? { wallets.first { $0.id == state.destinationWalletID } }
    private var categoryKind: CategoryKind { state.kind == .income ? .income : .expense }
    private var relevantCategories: [LedgerCategory] {
        categories.filter { $0.type == categoryKind && !$0.isArchived }
    }
    private var selectedCategory: LedgerCategory? {
        relevantCategories.first { $0.id == state.categoryID }
    }
    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter {
            guard $0.id != sourceWallet.id else { return false }
            return state.kind == .transfer
                ? $0.currencyCode == sourceWallet.currencyCode
                : $0.currencyCode != sourceWallet.currencyCode
        }
    }
    private var amountBinding: Binding<String> {
        Binding(
            get: { activeAmount == .destination ? state.destinationAmountText : state.amountText },
            set: {
                if activeAmount == .destination { state.destinationAmountText = $0 }
                else { state.amountText = $0 }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                EntryKindGlassControl(selection: $state.kind, validationReset: {})
                EntryInlineValidation(message: validation.generalMessage)
                if state.kind == .expense || state.kind == .income {
                    EntryCategoryPager(
                        categories: categories,
                        type: categoryKind,
                        selectedID: $state.categoryID,
                        isReordering: $categoryReordering,
                        isPresentingManagementOverlay: $categoryManagementOverlay
                    )
                    EntryInlineValidation(message: validation[.category])
                } else if state.kind == .transfer || state.kind == .exchange {
                    EntryMovementPanel(
                        state: $state,
                        sourceWallet: sourceWallet,
                        destinationWallet: destinationWallet,
                        destinationError: validation[.destinationWallet],
                        selectSource: { showingSourceWallets = true },
                        selectDestination: { showingDestinationWallets = true }
                    )
                } else {
                    EntryAdjustmentPanel(state: $state, wallet: sourceWallet)
                }

                if !categoryReordering && !categoryManagementOverlay {
                    EntryAmountPanel(
                        state: $state,
                        activeTarget: $activeAmount,
                        sourceWallet: sourceWallet,
                        destinationWallet: destinationWallet,
                        categoryPath: selectedCategory.map(categoryPath),
                        validation: validation
                    )
                    EntryContextControls(
                        state: $state,
                        sourceWallet: sourceWallet,
                        validation: validation,
                        selectAccount: { showingSourceWallets = true },
                        editSplitPayment: { showingMore = true },
                        editAA: {
                            if DecimalParser.parse(state.amountText).map({ $0 > 0 }) == true { showingAA = true }
                        },
                        editDiscount: { showingDiscount = true },
                        selectNeutralAdjustment: { direction in
                            state.kind = .adjustment
                            Task { @MainActor in
                                state.adjustmentInputMode = .delta
                                state.adjustmentDirection = direction
                            }
                        }
                    )
                    if let successMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 0)
            if !categoryReordering && !categoryManagementOverlay {
                EntryGlassKeypad(
                    amountText: amountBinding,
                    currencyCode: activeAmount == .destination
                        ? (destinationWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue)
                        : (sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue),
                    resetID: keypadResetID,
                    showsNextEntry: showsNextEntry,
                    isSaving: isSaving,
                    nextEntry: nextEntry,
                    complete: complete
                )
                .padding(.horizontal, 18)
                .padding(.top, 0)
                .padding(.bottom, 0)
                .background(Color(uiColor: .systemBackground).opacity(0.94))
                .overlay(alignment: .top) { Divider().opacity(0.35) }
            }
        }
        .sheet(isPresented: $showingSourceWallets) {
            EntryAccountSheet(
                title: state.kind == .transfer || state.kind == .exchange ? "选择转出账户" : "选择账户",
                wallets: wallets,
                selectedID: state.sourceWalletID
            ) { state.sourceWalletID = $0.id }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDestinationWallets) {
            EntryAccountSheet(
                title: "选择转入账户",
                wallets: destinationOptions,
                selectedID: state.destinationWalletID
            ) { state.destinationWalletID = $0.id }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDatePicker) {
            EntryDateTimeSheet(date: $state.date)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingMore) {
            EntrySupplementarySheet(state: $state, wallets: wallets)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingDiscount) {
            EntryDiscountSheet(state: $state)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAA) {
            AASplitEditorView(
                totalAmount: DecimalParser.parse(state.amountText) ?? 0,
                currencyCode: sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue,
                initialDraft: state.aaSplitDraft
            ) { state.aaSplitDraft = $0 }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: state.kind) { _, kind in
            activeAmount = .source
            categoryReordering = false
            categoryManagementOverlay = false
            keypadResetID = UUID()
            if kind == .expense || kind == .income,
               !relevantCategories.contains(where: { $0.id == state.categoryID }) {
                state.categoryID = relevantCategories
                    .filter { $0.parentID == nil }
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .first?.id
            }
        }
        .onChange(of: activeAmount) { _, _ in keypadResetID = UUID() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showingDatePicker = true } label: {
                    Text(state.date.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 32)
                    .contentShape(Capsule())
                }
                .buttonStyle(LedgerGlassPressStyle())
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("选择日期与时间")
            }
        }
    }

    private func categoryPath(_ category: LedgerCategory) -> String {
        guard let parentID = category.parentID,
              let parent = relevantCategories.first(where: { $0.id == parentID }) else {
            return category.localizedName(locale: locale)
        }
        return "\(parent.localizedName(locale: locale)) / \(category.localizedName(locale: locale))"
    }
}
