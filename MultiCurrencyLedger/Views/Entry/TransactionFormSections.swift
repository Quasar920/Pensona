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

struct EntryComposerView: View {
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
    @State private var showingDatePicker = false
    @State private var datePickerMode: EntryDateTimePickerMode = .date
    @State private var legacyContextOverlay: EntryContextOverlayKind?
    @State private var contextPresentation = EntryContextPresentationState()
    @State private var contextTagFrames: [EntryContextOverlayKind: CGRect] = [:]
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
                    EntryAmountPanel(
                        state: $state,
                        activeTarget: $activeAmount,
                        sourceWallet: sourceWallet,
                        destinationWallet: destinationWallet,
                        categoryPath: selectedCategory.map(categoryPath),
                        validation: validation
                    )
                    if state.kind != .transfer && state.kind != .exchange {
                        EntryContextControls(
                            state: $state,
                            sourceWallet: sourceWallet,
                            wallets: wallets,
                            validation: validation,
                            selectAccount: { presentContext(.account) },
                            editSplitPayment: { presentContext(.splitPayment) },
                            editAA: { presentContext(.aa) },
                            editDiscount: { presentContext(.discount) },
                            editForeignCurrency: { legacyContextOverlay = .foreignExpense },
                            hiddenKind: contextPresentation.hiddenTagKind,
                            // Preserve the original layout slot. A frozen,
                            // readable copy is rendered above the blur layer.
                            hiddenKindOpacity: contextPresentation.isActive ? 0 : 1
                        )
                    } else {
                        EntryMovementContextTags(
                            state: $state,
                            editDiscount: { legacyContextOverlay = .discount },
                            editFee: { legacyContextOverlay = .fee }
                        )
                    }
                    if let successMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 16)
            // The centered date/time controls live in the navigation bar
            // with the close button. Movement pages need a 30-point smaller
            // inset to match the established expense/income top position.
            .padding(
                .top,
                state.kind == .transfer || state.kind == .exchange ? 12 : 42
            )
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

            if !categoryReordering && !categoryManagementOverlay {
                EntryGlassKeypad(
                    amountText: keypadAmountBinding,
                    currencyCode: keypadCurrencyCode,
                    resetID: keypadResetID,
                    inputMode: contextPresentation.inputTarget == .aaPeople
                        ? .wholeNumber
                        : .amount,
                    showsNextEntry: showsNextEntry && !contextPresentation.isActive,
                    isSaving: isSaving || contextPresentation.isTransitioning,
                    canComplete: contextPresentation.kind != .aa
                        || contextPresentation.draft?.hasValidAAPeople == true,
                    nextEntry: nextEntry,
                    complete: {
                        if contextPresentation.isActive {
                            dismissContext(intent: .commit)
                        } else {
                            complete()
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 28,
                        style: .continuous
                    )
                    .fill(Color.primary.opacity(0.055))
                    .ignoresSafeArea(edges: .bottom)
                }
                .padding(.top, 5)
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
        .sheet(isPresented: $showingDatePicker) {
            EntryDateTimeSheet(date: $state.date, mode: datePickerMode)
                .presentationDetents([datePickerMode == .date ? .large : .medium])
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                dateTimeControls
            }
        }
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
            let panelWidth = min(480, max(240, proxy.size.width - 36))
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
                    maximumHeight: availableHeight,
                    isAAPeopleInputActive: contextPresentation.inputTarget == .aaPeople,
                    cancel: { dismissContext(intent: .cancel) },
                    commit: { dismissContext(intent: .commit) },
                    paymentPartChanged: { keypadResetID = UUID() },
                    aaPeopleInputSelected: {
                        contextPresentation.selectAAPeopleInput()
                        keypadResetID = UUID()
                    }
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

    private var contextTransitionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.20)
            : .timingCurve(0.22, 0.72, 0.18, 1, duration: 0.62)
    }

    private var dateTimeControls: some View {
        HStack(spacing: 8) {
            Button {
                datePickerMode = .date
                showingDatePicker = true
            } label: {
                Text(state.date.formatted(.dateTime.year().month().day()))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 32)
            }
            .buttonStyle(LedgerGlassPressStyle())
            .background(.white.opacity(0.72), in: Capsule())
            .overlay { Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.8) }
            .accessibilityLabel("选择日期")

            Button {
                datePickerMode = .time
                showingDatePicker = true
            } label: {
                Text(state.date.formatted(.dateTime.hour().minute()))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 32)
            }
            .buttonStyle(LedgerGlassPressStyle())
            .background(.white.opacity(0.72), in: Capsule())
            .overlay { Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.8) }
            .accessibilityLabel("选择时间")
        }
        .disabled(contextPresentation.isActive || legacyContextOverlay != nil)
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
