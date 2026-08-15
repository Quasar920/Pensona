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
                ? ($0.currencyCode == sourceWallet.currencyCode || $0.account?.type == .creditCard)
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
            } else if state.kind == .transfer,
                      let destination = wallets.first(where: { $0.id == state.destinationWalletID }),
                      destination.account?.type == .creditCard,
                      destination.currencyCode != sourceWallet?.currencyCode {
                TextField("偿还 \(destination.currencyCode)", text: $state.destinationAmountText)
                    .keyboardType(.decimalPad)
                LabeledContent("实际汇率", value: state.exchangeRateText.isEmpty ? "--" : state.exchangeRateText)
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
                    Picker("手续费扣款账户", selection: $state.feeWalletID) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(wallets) { Text(walletTitle($0)).tag($0.id as UUID?) }
                    }
                }
                if state.kind == .transfer {
                    TextField("优惠", text: $state.discountAmountText).keyboardType(.decimalPad)
                    if DecimalParser.parse(state.discountAmountText).map({ $0 > 0 }) == true {
                        Picker("优惠进入账户", selection: $state.discountWalletID) {
                            Text("请选择").tag(nil as UUID?)
                            ForEach(wallets) { Text(walletTitle($0)).tag($0.id as UUID?) }
                        }
                    }
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

struct LegacyEntryComposerView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showingCreditCardRepayment = false
    @State private var showingDateTimePicker = false
    @State private var legacyContextOverlay: EntryContextOverlayKind?
    @State private var contextPresentation = EntryContextPresentationState()
    @State private var contextTagFrames: [EntryContextOverlayKind: CGRect] = [:]
    @State private var activeAmount: EntryAmountTarget = .source
    @State private var keypadResetID = UUID()
    @State private var categoryReordering = false
    @State private var categoryManagementOverlay = false
    @State private var showingFeeTemplateManager = false
    @StateObject private var feeTemplateStore = FeeRateTemplateStore()

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
                ? ($0.currencyCode == sourceWallet.currencyCode || $0.account?.type == .creditCard)
                : $0.currencyCode != sourceWallet.currencyCode
        }
    }
    private var amountBinding: Binding<String> {
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
            return amountBinding
        case .aaPeople:
            return Binding(
                get: { contextPresentation.draft?.aaPeopleText ?? "" },
                set: { newValue in
                    guard var draft = contextPresentation.draft else { return }
                    draft.aaPeopleText = newValue.filter(\.isWholeNumber)
                    if let value = draft.validatedAAPeople {
                        draft.aaPeople = value
                    }
                    contextPresentation.draft = draft
                }
            )
        case let .splitPayment(index):
            return Binding(
                get: {
                    guard let draft = contextPresentation.draft,
                          draft.paymentParts.indices.contains(index) else {
                        return ""
                    }
                    return draft.paymentParts[index].amountText
                },
                set: { newValue in
                    guard var draft = contextPresentation.draft,
                          draft.paymentParts.indices.contains(index) else {
                        return
                    }
                    draft.paymentParts[index].amountText = newValue
                    contextPresentation.draft = draft
                }
            )
        case .discount:
            return Binding(
                get: { contextPresentation.draft?.discountAmountText ?? "" },
                set: { newValue in
                    guard var draft = contextPresentation.draft else { return }
                    draft.discountAmountText = newValue
                    contextPresentation.draft = draft
                }
            )
        case .fee:
            return Binding(
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
        if contextPresentation.kind == .splitPayment,
           let draft = contextPresentation.draft,
           draft.paymentParts.indices.contains(contextPresentation.activePaymentPart),
           let walletID = draft.paymentParts[contextPresentation.activePaymentPart].walletID,
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
        if state.kind == .expense {
            return state.foreignOriginalCurrencyCode
                ?? sourceWallet?.currencyCode
                ?? SupportedCurrency.CNY.rawValue
        }
        return sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                EntryKindGlassControl(selection: $state.kind, validationReset: {})
                EntryInlineValidation(message: validation.generalMessage)
                receiptMetadata
                ReceiptDashedDivider()
                if state.kind == .expense || state.kind == .income {
                    EntryCategoryPager(
                        categories: categories,
                        type: categoryKind,
                        selectedID: $state.categoryID,
                        isReordering: $categoryReordering,
                        isPresentingManagementOverlay: $categoryManagementOverlay,
                        isCompactCategoryListExpanded: .constant(false)
                    )
                    EntryInlineValidation(message: validation[.category])
                } else if state.kind == .transfer || state.kind == .exchange {
                    Spacer(minLength: 0)
                    EntryMovementPanel(
                        state: $state,
                        sourceWallet: sourceWallet,
                        destinationWallet: destinationWallet,
                        destinationError: validation[.destinationWallet],
                        selectSource: { showingSourceWallets = true },
                        selectDestination: { showingDestinationWallets = true },
                        selectDestinationCurrency: { showingCreditCardRepayment = true }
                    )
                } else {
                    EntryAdjustmentPanel(state: $state, wallet: sourceWallet)
                }

                if !categoryReordering && !categoryManagementOverlay {
                    ReceiptDashedDivider()
                    EntryAmountPanel(
                        state: $state,
                        activeTarget: $activeAmount,
                        sourceWallet: sourceWallet,
                        destinationWallet: destinationWallet,
                        categoryPath: selectedCategory.map(categoryPath),
                        validation: validation
                    )
                    if state.kind != .transfer && state.kind != .exchange {
                        ReceiptEntrySettings(
                            state: $state,
                            sourceWallet: sourceWallet,
                            wallets: wallets,
                            editSplitPayment: { presentContext(.splitPayment) },
                            editAA: { presentContext(.aa) },
                            editDiscount: { presentContext(.discount) },
                            editFee: { presentContext(.fee) }
                        )
                    } else {
                        EntryMovementContextTags(
                            state: $state,
                            editDiscount: { legacyContextOverlay = .discount },
                            editFee: { presentContext(.fee) }
                        )
                    }
                    if let successMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(LedgerPalette.ink)
                    }
                }
            }
            .padding(.horizontal, 16)
            // The centered date/time controls live in the navigation bar
            // with the close button. Movement pages need a 30-point smaller
            // inset to match the established expense/income top position.
            // The real torn edge is the shell's clipped top boundary.  This
            // inset reserves the space directly below it for the drag handle.
            .padding(.top, 58)
            .padding(.bottom, 0)
            // Keep the original content unavailable while a tag card owns the
            // interaction. The backdrop is applied afterwards so it can serve
            // as the sole middle-region cancellation target.
            .allowsHitTesting(!contextPresentation.isActive)
            .overlay {
                if contextPresentation.phase != .closed,
                   contextPresentation.phase != .closing {
                    ExpandedTagBackgroundEffect(
                        reduceTransparency: reduceTransparency,
                        dismiss: { dismissContext(intent: .cancel) }
                    )
                }
            }
                .accessibilityHidden(contextPresentation.isActive)
            }
            .scrollIndicators(.hidden)

            if !categoryReordering && !categoryManagementOverlay {
                EntryGlassKeypad(
                    amountText: keypadAmountBinding,
                    currencyCode: keypadCurrencyCode,
                    resetID: keypadResetID,
                    inputMode: contextPresentation.inputTarget == .aaPeople
                        ? .wholeNumber
                        : .amount,
                    fractionDigitsOverride: contextPresentation.inputTarget == .fee
                        && contextPresentation.draft?.feeInputMode == .percentage
                        ? 4
                        : nil,
                    showsNextEntry: showsNextEntry && !contextPresentation.isActive,
                    isSaving: isSaving || contextPresentation.isTransitioning,
                    canComplete: canCompleteContextInput,
                    nextEntry: nextEntry,
                    complete: {
                        if contextPresentation.isActive {
                            dismissContext(intent: .commit)
                        } else {
                            complete()
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(!contextPresentation.isTransitioning)
            }
        }
        .modifier(EntryComposerHeightModifier(
            anchorsToFullHeight: state.kind == .transfer || state.kind == .exchange
        ))
        .overlay {
            GeometryReader { proxy in
                contextOverlayHost(in: proxy)
            }
        }
        .overlay {
            if let legacyContextOverlay {
                LegacyEntryContextOverlay(
                    kind: legacyContextOverlay,
                    state: $state,
                    wallets: wallets,
                    currencyCode: sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue,
                    dismiss: { self.legacyContextOverlay = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .coordinateSpace(name: EntryContextCoordinateSpace.name)
        .onPreferenceChange(EntryContextTagFramePreferenceKey.self) {
            contextTagFrames = $0
        }
        .onPreferenceChange(EntryContextPanelFramePreferenceKey.self) { frame in
            panelFrameChanged(frame)
        }
        .sheet(isPresented: $showingSourceWallets) {
            EntryAccountSheet(
                title: state.kind == .transfer || state.kind == .exchange ? "选择转出账户" : "选择账户",
                wallets: wallets,
                selectedID: state.sourceWalletID,
                allowsSkipping: true
            ) { state.sourceWalletID = $0?.id }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
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
        .onChange(of: contextPresentation.inputTarget) { _, _ in
            keypadResetID = UUID()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active,
                  contextPresentation.isTransitioning else {
                return
            }
            contextPresentation.settleInterruptedTransition(state: &state)
            keypadResetID = UUID()
        }
    }

    private var receiptMetadata: some View {
        VStack(spacing: 0) {
            Button { showingDateTimePicker = true } label: {
                receiptInfoRow("时间", value: state.date.formatted(.dateTime.year().month().day().hour().minute()), symbol: "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entry-date-time-button")
            .popover(isPresented: $showingDateTimePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                EntryDateTimePickerPopover(date: state.date, cancel: { showingDateTimePicker = false }) {
                    state.date = $0
                    showingDateTimePicker = false
                }
                .presentationCompactAdaptation(.popover)
            }

            Button { showingSourceWallets = true } label: {
                receiptInfoRow("账户", value: sourceWallet?.account?.name ?? "请选择账户", symbol: "chevron.right")
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Text("备注").font(.subheadline.weight(.medium))
                TextField("可选，直接输入备注", text: $state.note)
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "pencil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        }
    }

    private func receiptInfoRow(_ label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            Text(value).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func contextOverlayHost(in proxy: GeometryProxy) -> some View {
        if let kind = contextPresentation.kind,
           let draftBinding = contextDraftBinding {
            let tagTop = contextTagFrames
                .filter { $0.key.usesGeniePresentation }
                .map { $0.value.minY }
                .min() ?? proxy.size.height * 0.58
            let tagBottom = contextTagFrames
                .filter { $0.key.usesGeniePresentation }
                .map { $0.value.maxY }
                .max() ?? tagTop + 27
            let availableTop: CGFloat = 12
            let availableBottom = max(availableTop + 120, tagTop - 12)
            let availableHeight = max(120, availableBottom - availableTop)
            let panelWidth = min(320, max(280, proxy.size.width * 0.78))
            let canvasHeight = min(proxy.size.height, tagBottom + 10)
            let canvasSize = CGSize(
                width: proxy.size.width,
                height: canvasHeight
            )

            ZStack(alignment: .topLeading) {
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
                    maximumHeight: availableHeight,
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
                .frame(width: panelWidth)
                .position(
                    x: proxy.size.width * 0.5,
                    y: availableTop + availableHeight * 0.5
                )
                .opacity(contextPresentation.phase == .presented ? 1 : 0)
                .allowsHitTesting(
                    contextPresentation.phase == .presented
                )
                .accessibilityHidden(
                    contextPresentation.phase != .presented
                )

                if contextPresentation.phase == .opening
                    || contextPresentation.phase == .closing {
                    ZStack(alignment: .topLeading) {
                        EntryContextTransitionPanel(
                            kind: kind,
                            draft: draftBinding.wrappedValue,
                            activePaymentPart: contextPresentation.activePaymentPart,
                            mainAmountText: state.amountText,
                            wallets: wallets,
                            currencyCode: sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue,
                            feeTemplates: feeTemplateStore.templates(for: state.kind),
                            targetHeight: contextPresentation.targetFrame.height
                        )
                        .frame(width: contextPresentation.targetFrame.width)
                        .position(
                            x: contextPresentation.targetFrame.midX,
                            y: contextPresentation.targetFrame.midY
                        )
                    }
                    .frame(
                        width: canvasSize.width,
                        height: canvasSize.height,
                        alignment: .topLeading
                    )
                    .entryContextGenieLayer(
                        progress: contextPresentation.progress,
                        panelFrame: contextPresentation.targetFrame,
                        tagFrame: contextPresentation.sourceFrame,
                        canvasSize: canvasSize,
                        reduceMotion: reduceMotion
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                if let sourceTagVisual = contextPresentation.sourceTagVisual,
                   !contextPresentation.sourceFrame.isEmpty {
                    EntryContextSourceTagOverlay(
                        kind: kind,
                        visual: sourceTagVisual,
                        frame: contextPresentation.sourceFrame,
                        isInteractive: contextPresentation.phase == .presented,
                        cancel: { dismissContext(intent: .cancel) }
                    )
                }
            }
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
        guard !contextPresentation.isActive, legacyContextOverlay == nil else { return }
        contextPresentation.prepare(
            kind: kind,
            sourceFrame: contextTagFrames[kind] ?? .zero,
            sourceTagVisual: EntryContextTagVisual.make(
                kind: kind,
                state: state,
                sourceWallet: sourceWallet,
                wallets: wallets
            ),
            state: state,
            wallets: wallets
        )
        keypadResetID = UUID()
    }

    private func panelFrameChanged(_ frame: CGRect) {
        guard !frame.isEmpty else { return }
        if contextPresentation.phase == .preparing {
            contextPresentation.beginOpening(targetFrame: frame)
            Task { @MainActor in
                // Give SwiftUI one display interval to commit the fully
                // gathered render-only layer before animating it open.
                // Without this staging frame, the insertion and progress
                // mutation can be coalesced into a visible jump.
                try? await Task.sleep(for: .milliseconds(17))
                guard contextPresentation.phase == .opening else { return }
                withAnimation(
                    contextTransitionAnimation,
                    completionCriteria: .logicallyComplete
                ) {
                    contextPresentation.progress = 0
                } completion: {
                    guard contextPresentation.phase == .opening else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        // Swap the render-only surface for the interactive
                        // panel atomically. Cross-fading two translucent white
                        // surfaces caused the visible end-frame flash.
                        contextPresentation.finishOpening()
                    }
                }
            }
        } else if contextPresentation.phase == .presented {
            contextPresentation.updateTargetFrame(frame)
        }
    }

    private func dismissContext(intent: EntryContextDismissalIntent) {
        guard contextPresentation.phase == .presented else {
            return
        }
        if intent == .commit, !contextPresentation.synchronizePendingInput() {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            contextPresentation.beginClosing(intent: intent)
        }
        Task { @MainActor in
            // First commit the exact live-panel → render-layer swap at
            // progress 0, then begin the reverse mapping on the next frame.
            try? await Task.sleep(for: .milliseconds(17))
            guard contextPresentation.phase == .closing else { return }
            withAnimation(
                contextTransitionAnimation,
                completionCriteria: .logicallyComplete
            ) {
                contextPresentation.progress = 1
            } completion: {
                guard contextPresentation.phase == .closing else { return }
                var completionTransaction = Transaction()
                completionTransaction.disablesAnimations = true
                withTransaction(completionTransaction) {
                    contextPresentation.finishClosing(state: &state)
                }
                keypadResetID = UUID()
            }
        }
    }

    private func applyFeeTemplate(_ template: FeeRateTemplate) {
        guard var draft = contextPresentation.draft else { return }
        draft.feeInputMode = .percentage
        draft.feeInputText = NSDecimalNumber(decimal: template.percentage).stringValue
        draft.feeTemplateName = template.name
        var candidate = state
        guard candidate.applyFee(
            inputText: draft.feeInputText,
            mode: draft.feeInputMode,
            currencyCode: draft.feeCurrencyCode,
            templateName: draft.feeTemplateName
        ) else {
            return
        }
        contextPresentation.draft = draft
        dismissContext(intent: .commit)
    }

    private var canCompleteContextInput: Bool {
        switch contextPresentation.kind {
        case .aa:
            contextPresentation.draft?.hasValidAAPeople == true
        case .fee:
            contextPresentation.draft?.hasValidFeeInput == true
        default:
            true
        }
    }

    private var contextTransitionAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.20)
        }
        return contextPresentation.phase == .opening
            ? .spring(response: 0.42, dampingFraction: 0.70)
            : .timingCurve(0.20, 0.72, 0.24, 1, duration: 0.24)
    }

    private var dateTimeControls: some View {
        Button {
            showingDateTimePicker = true
        } label: {
            HStack(spacing: 16) {
                Text(state.date.formatted(.dateTime.year().month().day()))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(state.date.formatted(.dateTime.hour().minute()))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .background(.white.opacity(0.72), in: Capsule())
        .overlay { Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.8) }
        .accessibilityLabel("选择日期和时间")
        .accessibilityIdentifier("entry-date-time-button")
        .disabled(contextPresentation.isActive || legacyContextOverlay != nil)
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
            .presentationBackground(
                Color(uiColor: .systemBackground).opacity(0.95)
            )
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

private struct EntryComposerHeightModifier: ViewModifier {
    let anchorsToFullHeight: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if anchorsToFullHeight {
            GeometryReader { proxy in
                content
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .top
                    )
            }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct ReceiptDashedDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(alignment: .center) {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.black.opacity(0.48))
                }
            }
            .padding(.vertical, 4)
    }
}

private struct ReceiptEntrySettings: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let wallets: [CurrencyWallet]
    let editSplitPayment: () -> Void
    let editAA: () -> Void
    let editDiscount: () -> Void
    let editFee: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReceiptDashedDivider()
            toggleRow("报销", isOn: Binding(
                get: { state.reimbursementStatus == .pending },
                set: { state.reimbursementStatus = $0 ? .pending : .none }
            ))
            actionRow("AA", value: state.aaSplitDraft == nil ? "不参与 AA" : "已设置", identifier: "entry-context-tag-aa", action: editAA)
            actionRow("优惠", value: hasDiscount ? "已设置优惠" : "无优惠", identifier: "entry-context-tag-discount", action: editDiscount)
            actionRow("组合支付", value: state.usesSplitPayment ? "已设置" : "单独支付", identifier: "entry-context-tag-split-payment", action: editSplitPayment)
            actionRow("手续费", value: state.includesFee ? "已设置手续费" : "不收取手续费", identifier: "entry-context-tag-fee", action: editFee)
            toggleRow("不计支出", isOn: $state.excludesFromMonthlyExpense)
            ReceiptDashedDivider()
        }
        .font(.subheadline)
    }

    private var hasDiscount: Bool {
        DecimalParser.parse(state.discountAmountText).map { $0 > 0 } == true
    }

    private func actionRow(_ title: String, value: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.primary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? Color.black : .secondary)
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
