import SwiftUI

/// Public composer contract used by create, edit, copy and external-draft flows.
/// The previous glass composer remains isolated as a legacy implementation;
/// all active entry routes render this receipt-based editor.
struct EntryComposerView: View {
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let exchangeSourceAccounts: [Account]
    let categories: [LedgerCategory]
    let selectExchangeSource: (Account) throws -> Void
    let exchangeDestinationAvailability: (SupportedCurrency, Bool) -> ExchangeDestinationAvailability
    let selectExchangeDestination: (SupportedCurrency, Bool) throws -> Void
    let validation: EntryValidationState
    let successMessage: String?
    let showsNextEntry: Bool
    let isSaving: Bool
    let autoExpandCategoryOnAppear: Bool
    let nextEntry: () -> Void
    let complete: () -> Void

    var body: some View {
        ReceiptEntryComposerView(
            state: $state,
            wallets: wallets,
            exchangeSourceAccounts: exchangeSourceAccounts,
            categories: categories,
            selectExchangeSource: selectExchangeSource,
            exchangeDestinationAvailability: exchangeDestinationAvailability,
            selectExchangeDestination: selectExchangeDestination,
            validation: validation,
            successMessage: successMessage,
            showsNextEntry: showsNextEntry,
            isSaving: isSaving,
            autoExpandCategoryOnAppear: autoExpandCategoryOnAppear,
            nextEntry: nextEntry,
            complete: complete
        )
    }
}

private struct ReceiptEntryComposerView: View {
    @Environment(\.locale) private var locale
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let exchangeSourceAccounts: [Account]
    let categories: [LedgerCategory]
    let selectExchangeSource: (Account) throws -> Void
    let exchangeDestinationAvailability: (SupportedCurrency, Bool) -> ExchangeDestinationAvailability
    let selectExchangeDestination: (SupportedCurrency, Bool) throws -> Void
    let validation: EntryValidationState
    let successMessage: String?
    let showsNextEntry: Bool
    let isSaving: Bool
    let autoExpandCategoryOnAppear: Bool
    let nextEntry: () -> Void
    let complete: () -> Void

    @State private var showingSourceWallets = false
    @State private var showingDestinationWallets = false
    @State private var showingCreditCardRepayment = false
    @State private var showingDateTimePicker = false
    @State private var contextPresentation = EntryContextPresentationState()
    @State private var showingFeeTemplateManager = false
    @StateObject private var feeTemplateStore = FeeRateTemplateStore()
    @State private var activeAmount: EntryAmountTarget = .source
    @State private var keypadResetID = UUID()
    @State private var categoryReordering = false
    @State private var categoryManagementOverlay = false
    @State private var isCategoryPickerExpanded = false
    @State private var appliedInitialCategoryExpansion = false
    @State private var sourceSelectionError: String?
    @AppStorage(AppPreferences.autoExpandCategoryOnNewEntryKey)
    private var automaticallyExpandCategory = false

    private var sourceWallet: CurrencyWallet? {
        wallets.first { $0.id == state.sourceWalletID }
    }

    private var destinationWallet: CurrencyWallet? {
        wallets.first { $0.id == state.destinationWalletID }
    }

    private var categoryKind: CategoryKind {
        state.kind == .income ? .income : .expense
    }

    private var relevantCategories: [LedgerCategory] {
        categories.filter { $0.type == categoryKind && !$0.isArchived }
    }

    private var selectedCategory: LedgerCategory? {
        relevantCategories.first { $0.id == state.categoryID }
    }

    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter { wallet in
            guard wallet.id != sourceWallet.id else { return false }
            if state.kind == .transfer {
                return wallet.currencyCode == sourceWallet.currencyCode
                    || wallet.account?.type == .creditCard
            }
            return wallet.currencyCode != sourceWallet.currencyCode
        }
    }

    private var activeAmountBinding: Binding<String> {
        Binding(
            get: {
                switch activeAmount {
                case .source: state.amountText
                case .destination: state.destinationAmountText
                case .settlement: state.settledAmountText
                }
            },
            set: {
                switch activeAmount {
                case .source: state.amountText = $0
                case .destination: state.destinationAmountText = $0
                case .settlement: state.settledAmountText = $0
                }
            }
        )
    }

    private var keypadAmountBinding: Binding<String> {
        switch contextPresentation.inputTarget {
        case .mainAmount:
            activeAmountBinding
        case .aaPeople:
            Binding(
                get: { contextPresentation.draft?.aaPeopleText ?? "" },
                set: { newValue in
                    guard var draft = contextPresentation.draft else { return }
                    draft.aaPeopleText = newValue.filter(\.isWholeNumber)
                    if let value = draft.validatedAAPeople { draft.aaPeople = value }
                    contextPresentation.draft = draft
                }
            )
        case let .splitPayment(index):
            Binding(
                get: {
                    guard let draft = contextPresentation.draft,
                          draft.paymentParts.indices.contains(index) else { return "" }
                    return draft.paymentParts[index].amountText
                },
                set: { newValue in
                    guard var draft = contextPresentation.draft,
                          draft.paymentParts.indices.contains(index) else { return }
                    draft.paymentParts[index].amountText = newValue
                    contextPresentation.draft = draft
                }
            )
        case .discount:
            Binding(
                get: { contextPresentation.draft?.discountAmountText ?? "" },
                set: { newValue in
                    guard var draft = contextPresentation.draft else { return }
                    draft.discountAmountText = newValue
                    contextPresentation.draft = draft
                }
            )
        case .fee:
            Binding(
                get: { contextPresentation.draft?.feeInputText ?? "" },
                set: { newValue in
                    guard var draft = contextPresentation.draft else { return }
                    draft.feeInputText = newValue
                    draft.feeTemplateName = nil
                    contextPresentation.draft = draft
                }
            )
        }
    }

    private var keypadCurrencyCode: String {
        if contextPresentation.kind == .discount,
           let walletID = contextPresentation.draft?.discountWalletID,
           let wallet = wallets.first(where: { $0.id == walletID }) {
            return wallet.currencyCode
        }
        if contextPresentation.kind == .fee,
           let walletID = contextPresentation.draft?.feeWalletID,
           let wallet = wallets.first(where: { $0.id == walletID }) {
            return wallet.currencyCode
        }
        if activeAmount == .destination {
            return destinationWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue
        }
        if activeAmount == .settlement {
            return sourceWallet?.account?.defaultSettlementCurrencyCode
                ?? sourceWallet?.currencyCode
                ?? SupportedCurrency.CNY.rawValue
        }
        if state.kind == .expense, let foreignCode = state.foreignOriginalCurrencyCode {
            return foreignCode
        }
        return sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(ReceiptPalette.paper)

            VStack(spacing: 0) {
                // The form must always be the flexible region. Keeping the
                // keypad outside it pins 下一笔 / 完成 to the same bottom
                // position whether the category list is collapsed or open.
                ScrollView {
                    receiptFormSections
                }
                .scrollIndicators(.hidden)
                .layoutPriority(1)
                keypadSection
            }
            .padding(.horizontal, 12)
            // Pull the transaction kinds into the sheet cap so the form
            // begins immediately below it and the complete expense flow fits
            // without scrolling.
            .padding(.top, 0)
            .padding(.bottom, 2)
            .accessibilityIdentifier("receipt-entry-content")

            contextOverlay
        }
        // The receipt is intentionally appearance-invariant. Dark mode still
        // dims the page behind the Sheet, but never produces a second editor UI.
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("receipt-entry-paper")
        .sheet(isPresented: $showingSourceWallets) {
            if state.kind == .exchange {
                ExchangeSourceAccountSheet(
                    accounts: exchangeSourceAccounts,
                    selectedID: sourceWallet?.account?.id
                ) { account in
                    do {
                        try selectExchangeSource(account)
                    } catch {
                        sourceSelectionError = error.localizedDescription
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                EntryAccountSheet(
                    title: state.kind == .transfer ? "选择转出账户" : "选择账户",
                    wallets: wallets,
                    selectedID: state.sourceWalletID,
                    allowsSkipping: true
                ) { state.sourceWalletID = $0?.id }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingDestinationWallets) {
            EntryAccountSheet(
                title: "选择转入账户",
                wallets: destinationOptions,
                selectedID: state.destinationWalletID,
                allowsSkipping: false
            ) { state.destinationWalletID = $0?.id }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCreditCardRepayment) {
            if let destinationWallet, destinationWallet.account?.type == .creditCard {
                EntryCreditCardRepaymentSheet(
                    state: $state,
                    sourceWallet: sourceWallet,
                    cardWallets: wallets.filter { $0.account?.id == destinationWallet.account?.id }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingFeeTemplateManager) {
            FeeTemplateManagementView(store: feeTemplateStore, kind: state.kind)
        }
        .popover(
            isPresented: $showingDateTimePicker,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            EntryDateTimePickerPopover(
                date: state.date,
                cancel: { showingDateTimePicker = false },
                complete: {
                    state.date = $0
                    showingDateTimePicker = false
                }
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(ReceiptPalette.paper.opacity(0.98))
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
        .onAppear {
            guard !appliedInitialCategoryExpansion else { return }
            appliedInitialCategoryExpansion = true
            guard automaticallyExpandCategory,
                  autoExpandCategoryOnAppear,
                  state.kind == .expense || state.kind == .income else { return }
            isCategoryPickerExpanded = true
        }
        .onChange(of: activeAmount) { _, _ in keypadResetID = UUID() }
        .onChange(of: contextPresentation.inputTarget) { _, _ in keypadResetID = UUID() }
        .alert("无法选择购汇银行卡", isPresented: Binding(
            get: { sourceSelectionError != nil },
            set: { if !$0 { sourceSelectionError = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(sourceSelectionError ?? "未知错误")
        }
    }

    @ViewBuilder
    private var typeSelector: some View {
        if state.kind == .adjustment {
            Text("余额调整")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ReceiptPalette.border))
        } else {
            HStack(spacing: 0) {
                ForEach(TransactionKind.allCases.filter { $0 != .adjustment }) { kind in
                    Button {
                        selectTransactionKind(kind)
                    } label: {
                        Text(kind.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(state.kind == kind ? Color.white : ReceiptPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(state.kind == kind ? Color.black : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(state.kind == kind ? .isSelected : [])
                    .accessibilityIdentifier("receipt-kind-\(kind.rawValue)")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ReceiptPalette.border))
        }
    }

    private func selectTransactionKind(_ kind: TransactionKind) {
        guard state.kind != kind else { return }
        // Keep the selector's tap target independent from the content below
        // it, then let the parent reset dependent form fields in one place.
        isCategoryPickerExpanded = false
        categoryReordering = false
        categoryManagementOverlay = false
        HapticFeedbackService().selection()
        withAnimation(.easeOut(duration: 0.16)) {
            state.kind = kind
        }
    }

    private var basicInfoSection: some View {
        VStack(spacing: 0) {
            ReceiptSettingRow(
                title: "时间",
                value: state.date.formatted(.dateTime.year().month().day().hour().minute()),
                symbol: "pencil",
                action: { showingDateTimePicker = true }
            )
            .accessibilityIdentifier("entry-date-time-button")

            if state.kind != .transfer {
                ReceiptSettingRow(
                    title: state.kind == .exchange ? "购汇银行卡" : "账户",
                    value: sourceWallet?.account?.name ?? "请选择账户",
                    symbol: "chevron.down",
                    action: { showingSourceWallets = true }
                )
                .accessibilityIdentifier("receipt-account-row")
            }

            HStack(spacing: 10) {
                Text("备注")
                    .font(.subheadline.weight(.medium))
                TextField("可选，直接输入备注", text: $state.note)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
            .accessibilityIdentifier("receipt-note-row")
        }
    }

    private var receiptFormSections: some View {
        VStack(spacing: 0) {
            typeSelector
            ReceiptDashDivider()
            basicInfoSection
            ReceiptDashDivider()
            mainDetailSection
            ReceiptDashDivider()
            amountSection
            ReceiptDashDivider()
            optionsSection
            // This boundary is intentionally outside the options stack so it
            // stays directly above the fixed keypad in every editor state.
            ReceiptDashDivider()
        }
    }

    @ViewBuilder
    private var mainDetailSection: some View {
        switch state.kind {
        case .expense, .income:
            EntryCategoryPager(
                categories: categories,
                type: categoryKind,
                selectedID: $state.categoryID,
                isReordering: $categoryReordering,
                isPresentingManagementOverlay: $categoryManagementOverlay,
                isCompactCategoryListExpanded: $isCategoryPickerExpanded,
                usesCompactReceiptLayout: true
            )
            EntryInlineValidation(message: validation[.category])
        case .transfer:
            ReceiptMovementSection(
                state: $state,
                sourceWallet: sourceWallet,
                destinationWallet: destinationWallet,
                destinationError: validation[.destinationWallet],
                selectSource: { showingSourceWallets = true },
                selectDestination: { showingDestinationWallets = true },
                selectDestinationCurrency: { showingCreditCardRepayment = true }
            )
        case .exchange:
            ReceiptExchangePurchaseSection(
                sourceWallet: sourceWallet,
                destinationWallet: destinationWallet,
                destinationError: validation[.destinationWallet],
                destinationAvailability: exchangeDestinationAvailability,
                selectDestination: selectExchangeDestination
            )
        case .adjustment:
            EntryAdjustmentPanel(state: $state, wallet: sourceWallet)
        }
    }

    private var amountSection: some View {
        EntryAmountPanel(
            state: $state,
            activeTarget: $activeAmount,
            sourceWallet: sourceWallet,
            destinationWallet: destinationWallet,
            categoryPath: selectedCategory.map(categoryPath),
            validation: validation
        )
        .scaleEffect(0.72)
        .frame(height: state.kind == .exchange ? 76 : 48)
        .accessibilityIdentifier("receipt-amount-section")
    }

    @ViewBuilder
    private var optionsSection: some View {
        VStack(spacing: 0) {
            switch state.kind {
            case .expense:
                expenseOptions
            case .income:
                commonMoneyOptions
                ReceiptToggleRow(title: "不计收入", isOn: $state.excludesFromMonthlyIncome)
            case .transfer:
                discountRow
                feeRow
            case .exchange:
                discountRow
                feeRow
            case .adjustment:
                EmptyView()
            }
        }
    }

    private var expenseOptions: some View {
        VStack(spacing: 0) {
            ReceiptToggleRow(
                title: "报销",
                isOn: Binding(
                    get: { state.reimbursementStatus == .pending },
                    set: { state.reimbursementStatus = $0 ? .pending : .none }
                )
            )
            ReceiptSettingRow(
                title: "AA",
                value: state.aaSplitDraft == nil ? "不参与 AA" : "已设置",
                symbol: "chevron.down",
                action: { presentContext(.aa) }
            )
            .accessibilityIdentifier("entry-context-tag-aa")
            discountRow

            // Recovery-related settings and payment-related settings are
            // separate groups in the receipt, as they affect different totals.
            ReceiptDashDivider()

            splitPaymentRow
            feeRow
            ReceiptToggleRow(title: "不计支出", isOn: $state.excludesFromMonthlyExpense)
        }
    }

    @ViewBuilder
    private var commonMoneyOptions: some View {
        discountRow
        splitPaymentRow
        feeRow
    }

    private var discountRow: some View {
        ReceiptSettingRow(
            title: "优惠",
            value: adjustmentAmountText(
                state.discountAmountText,
                walletID: state.discountWalletID
            ),
            symbol: "chevron.down",
            action: { presentContext(.discount) }
        )
        .accessibilityIdentifier("entry-context-tag-discount")
    }

    private var splitPaymentRow: some View {
        ReceiptSettingRow(
            title: "组合支付",
            value: state.usesSplitPayment ? "已设置" : "单独支付",
            symbol: "chevron.down",
            action: { presentContext(.splitPayment) }
        )
        .accessibilityIdentifier("entry-context-tag-splitPayment")
    }

    private var feeRow: some View {
        ReceiptSettingRow(
            title: "手续费",
            value: adjustmentAmountText(
                state.includesFee ? state.feeText : "",
                walletID: state.feeWalletID
            ),
            symbol: "chevron.down",
            action: { presentContext(.fee) }
        )
        .accessibilityIdentifier("entry-context-tag-fee")
    }

    private var keypadSection: some View {
        EntryGlassKeypad(
            amountText: keypadAmountBinding,
            currencyCode: keypadCurrencyCode,
            resetID: keypadResetID,
            inputMode: contextPresentation.inputTarget == .aaPeople ? .wholeNumber : .amount,
            fractionDigitsOverride: contextPresentation.inputTarget == .fee
                && contextPresentation.draft?.feeInputMode == .percentage ? 4 : nil,
            showsNextEntry: showsNextEntry && !contextPresentation.isActive,
            isSaving: isSaving || contextPresentation.isTransitioning,
            canComplete: canCompleteContextInput,
            nextEntry: nextEntry,
            complete: {
                contextPresentation.isActive
                    ? dismissContext(intent: .commit)
                    : complete()
            },
        )
        .accessibilityIdentifier("receipt-keypad")
    }

    private func adjustmentAmountText(_ amountText: String, walletID: UUID?) -> String {
        let amount = DecimalParser.parse(amountText) ?? 0
        let currencyCode = wallets.first(where: { $0.id == walletID })?.currencyCode
            ?? sourceWallet?.currencyCode
            ?? SupportedCurrency.CNY.rawValue
        return MoneyFormatter.string(amount, currencyCode: currencyCode)
    }

    private func categoryPath(_ category: LedgerCategory) -> String {
        guard let parentID = category.parentID,
              let parent = relevantCategories.first(where: { $0.id == parentID }) else {
            return category.localizedName(locale: locale)
        }
        return "\(parent.localizedName(locale: locale)) / \(category.localizedName(locale: locale))"
    }

    @ViewBuilder
    private var contextOverlay: some View {
        if let kind = contextPresentation.kind,
           let draftBinding = contextDraftBinding {
            ZStack {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Color.black.opacity(0.22)
                            .contentShape(Rectangle())
                            .onTapGesture { dismissContext(intent: .cancel) }
                            // Reserve the bottom of the receipt for its
                            // keypad. Previously the modal backdrop covered
                            // it, so discount input could not receive taps.
                            .frame(height: max(0, proxy.size.height - 286))

                        Color.clear
                            .allowsHitTesting(false)
                    }
                }

                EntryContextOverlayPanel(
                    kind: kind,
                    draft: draftBinding,
                    activePaymentPart: Binding(
                        get: { contextPresentation.activePaymentPart },
                        set: { contextPresentation.selectPaymentPart($0) }
                    ),
                    mainAmountText: state.amountText,
                    wallets: wallets,
                    currencyCode: sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue,
                    feeTemplates: feeTemplateStore.templates(for: state.kind),
                    maximumHeight: 520,
                    isAAPeopleInputActive: contextPresentation.inputTarget == .aaPeople,
                    cancel: { dismissContext(intent: .cancel) },
                    commit: { dismissContext(intent: .commit) },
                    paymentPartChanged: { keypadResetID = UUID() },
                    aaPeopleInputSelected: {
                        contextPresentation.selectAAPeopleInput()
                        keypadResetID = UUID()
                    },
                    feeInputChanged: { keypadResetID = UUID() },
                    feeTemplateSelected: applyFeeTemplate,
                    manageFeeTemplates: { showingFeeTemplateManager = true }
                )
                .frame(maxWidth: 334)
                .padding(.horizontal, 24)
            }
            .transition(.opacity)
            .zIndex(2_000)
        }
    }

    private var contextDraftBinding: Binding<EntryContextDraft>? {
        guard contextPresentation.draft != nil else { return nil }
        return Binding(
            get: {
                contextPresentation.draft
                    ?? EntryContextDraft(kind: .account, state: state, wallets: wallets)
            },
            set: { contextPresentation.draft = $0 }
        )
    }

    private func presentContext(_ kind: EntryContextOverlayKind) {
        guard !contextPresentation.isActive else { return }
        contextPresentation.prepare(
            kind: kind,
            sourceFrame: .zero,
            sourceTagVisual: EntryContextTagVisual.make(
                kind: kind,
                state: state,
                sourceWallet: sourceWallet,
                wallets: wallets
            ),
            state: state,
            wallets: wallets
        )
        contextPresentation.beginOpening(targetFrame: CGRect(x: 24, y: 100, width: 334, height: 420))
        contextPresentation.finishOpening()
        keypadResetID = UUID()
    }

    private func dismissContext(intent: EntryContextDismissalIntent) {
        guard contextPresentation.phase == .presented else { return }
        if intent == .commit, !contextPresentation.synchronizePendingInput() { return }
        contextPresentation.beginClosing(intent: intent)
        contextPresentation.finishClosing(state: &state)
        keypadResetID = UUID()
    }

    private func applyFeeTemplate(_ template: FeeRateTemplate) {
        guard var draft = contextPresentation.draft else { return }
        draft.feeInputMode = .percentage
        draft.feeInputText = NSDecimalNumber(decimal: template.percentage).stringValue
        draft.feeTemplateName = template.name
        contextPresentation.draft = draft
        dismissContext(intent: .commit)
    }

    private var canCompleteContextInput: Bool {
        switch contextPresentation.kind {
        case .aa: contextPresentation.draft?.hasValidAAPeople == true
        case .discount: contextPresentation.draft?.hasValidDiscountSelection == true
        case .fee: contextPresentation.draft?.hasValidFeeSelection == true
        default: true
        }
    }
}

private struct ReceiptSettingRow: View {
    let title: String
    let value: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(ReceiptPalette.ink)
                    .lineLimit(1)
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReceiptToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(ReceiptPalette.border, lineWidth: 1)
                        .frame(width: 30, height: 20)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isOn ? Color.black : .secondary)
                }
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

private struct ReceiptMovementSection: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let destinationWallet: CurrencyWallet?
    let destinationError: String?
    let selectSource: () -> Void
    let selectDestination: () -> Void
    let selectDestinationCurrency: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReceiptSettingRow(
                title: "转出账户",
                value: walletTitle(sourceWallet),
                symbol: "chevron.down",
                action: selectSource
            )
            HStack(spacing: 12) {
                Rectangle().fill(ReceiptPalette.border).frame(height: 1)
                Button(action: swapDirection) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(ReceiptPalette.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("交换方向")
                Rectangle().fill(ReceiptPalette.border).frame(height: 1)
            }
            ReceiptSettingRow(
                title: "转入账户",
                value: walletTitle(destinationWallet),
                symbol: "chevron.down",
                action: destinationWallet?.account?.type == .creditCard
                    ? selectDestinationCurrency
                    : selectDestination
            )
            EntryInlineValidation(message: destinationError)
        }
        .padding(.vertical, 4)
    }

    private func walletTitle(_ wallet: CurrencyWallet?) -> String {
        guard let wallet else { return "请选择" }
        return "\(wallet.account?.name ?? "未知账户") · \(wallet.currencyCode)"
    }

    private func swapDirection() {
        (state.sourceWalletID, state.destinationWalletID) = (state.destinationWalletID, state.sourceWalletID)
        (state.amountText, state.destinationAmountText) = (state.destinationAmountText, state.amountText)
        if let rate = DecimalParser.parse(state.exchangeRateText), rate > 0 {
            state.exchangeRateText = EntryCalculationState.string(
                EntryCalculationState.round(1 / rate, scale: 8)
            )
        }
    }
}

enum ExchangeDestinationAvailability: Equatable {
    case ready
    case requiresEnabling(accountName: String)
    case missingCashAccount
}

private struct ReceiptExchangePurchaseSection: View {
    let sourceWallet: CurrencyWallet?
    let destinationWallet: CurrencyWallet?
    let destinationError: String?
    let destinationAvailability: (SupportedCurrency, Bool) -> ExchangeDestinationAvailability
    let selectDestination: (SupportedCurrency, Bool) throws -> Void

    @State private var purchasesCash = false
    @State private var showingCurrencyPicker = false
    @State private var pendingCurrency: SupportedCurrency?
    @State private var pendingAccountName = ""
    @State private var showingEnableConfirmation = false
    @State private var selectionError: String?

    var body: some View {
        VStack(spacing: 0) {
            ReceiptSettingRow(
                title: "购入币种",
                value: destinationWallet?.currencyCode ?? "请选择币种",
                symbol: "chevron.down",
                action: { showingCurrencyPicker = true }
            )
            .accessibilityIdentifier("entry-exchange-currency-row")

            ReceiptToggleRow(title: "购入现金", isOn: $purchasesCash)
                .accessibilityIdentifier("entry-exchange-cash-toggle")

            EntryInlineValidation(message: destinationError)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingCurrencyPicker) {
            ReceiptPurchaseCurrencySheet(
                selectedCode: destinationWallet?.currencyCode,
                excluding: sourceWallet?.currencyCode,
                select: { currency in
                    showingCurrencyPicker = false
                    selectCurrency(currency)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "启用购入币种",
            isPresented: $showingEnableConfirmation,
            titleVisibility: .visible
        ) {
            Button("启用并继续") {
                if let pendingCurrency {
                    applySelection(pendingCurrency)
                }
            }
            Button("取消", role: .cancel) {
                purchasesCash = destinationWallet?.account?.type == .cash
            }
        } message: {
            Text("\(pendingAccountName) 尚未启用该币种。继续后会在这个既有账户下启用该币种。")
        }
        .alert("无法选择购入币种", isPresented: Binding(
            get: { selectionError != nil },
            set: { if !$0 { selectionError = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(selectionError ?? "未知错误")
        }
        .onAppear {
            purchasesCash = destinationWallet?.account?.type == .cash
        }
        .onChange(of: purchasesCash) { _, _ in
            guard let currency = destinationWallet?.currency else { return }
            selectCurrency(currency)
        }
    }

    private func selectCurrency(_ currency: SupportedCurrency) {
        switch destinationAvailability(currency, purchasesCash) {
        case .ready:
            applySelection(currency)
        case let .requiresEnabling(accountName):
            pendingCurrency = currency
            pendingAccountName = accountName
            showingEnableConfirmation = true
        case .missingCashAccount:
            purchasesCash = false
            selectionError = "尚未创建现金账户。请先在“资产”中创建现金账户，再购入外币现金。"
        }
    }

    private func applySelection(_ currency: SupportedCurrency) {
        do {
            try selectDestination(currency, purchasesCash)
            pendingCurrency = nil
        } catch {
            selectionError = error.localizedDescription
        }
    }
}

private struct ReceiptPurchaseCurrencySheet: View {
    let selectedCode: String?
    let excluding: String?
    let select: (SupportedCurrency) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(SupportedCurrency.allCases.filter { $0.rawValue != excluding }) { currency in
                    Button {
                        select(currency)
                    } label: {
                        HStack {
                            Text(currency.rawValue)
                                .font(.headline)
                            Text(currency.localizedName)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if currency.rawValue == selectedCode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("entry-exchange-currency-\(currency.rawValue)")
                }
            }
            .navigationTitle("选择购入币种")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ReceiptDashDivider: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
            }
            .stroke(ReceiptPalette.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(height: 1)
        .padding(.vertical, 3)
        .accessibilityHidden(true)
    }
}

private struct ReceiptPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let toothWidth: CGFloat = 13
        let toothDepth: CGFloat = 11
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + toothDepth))
        var x = rect.minX
        while x < rect.maxX {
            let middle = min(x + toothWidth / 2, rect.maxX)
            let end = min(x + toothWidth, rect.maxX)
            path.addLine(to: CGPoint(x: middle, y: rect.minY))
            path.addLine(to: CGPoint(x: end, y: rect.minY + toothDepth))
            x += toothWidth
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Opaque cutouts make the torn edge independent from any NavigationStack or
/// appearance background behind the receipt. Half-teeth at both boundaries
/// keep the tear continuous all the way to the paper's square side edges.
private struct ReceiptTearCutoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let toothWidth: CGFloat = 13
        let toothDepth: CGFloat = 11
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x - toothWidth / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.minY + toothDepth))
            path.addLine(to: CGPoint(x: x + toothWidth / 2, y: rect.minY))
            path.closeSubpath()
            x += toothWidth
        }
        return path
    }
}

private struct ReceiptTornEdgeLine: Shape {
    func path(in rect: CGRect) -> Path {
        let toothWidth: CGFloat = 13
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: min(x + toothWidth / 2, rect.maxX), y: rect.minY))
            path.addLine(to: CGPoint(x: min(x + toothWidth, rect.maxX), y: rect.maxY))
            x += toothWidth
        }
        return path
    }
}

private enum ReceiptPalette {
    static let paper = Color(red: 247 / 255, green: 245 / 255, blue: 239 / 255)
    static let sheetCap = Color(red: 0.92, green: 0.92, blue: 0.91)
    static let ink = Color(red: 34 / 255, green: 34 / 255, blue: 34 / 255)
    static let border = Color(red: 208 / 255, green: 206 / 255, blue: 200 / 255)
    static let dash = Color.black.opacity(0.52)
}
