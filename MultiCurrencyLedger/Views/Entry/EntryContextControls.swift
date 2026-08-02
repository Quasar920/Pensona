import SwiftUI

struct EntryContextTagVisual: Equatable {
    let title: String
    let isSelected: Bool

    static func make(
        kind: EntryContextOverlayKind,
        state: TransactionFormState,
        sourceWallet: CurrencyWallet?,
        wallets: [CurrencyWallet]
    ) -> EntryContextTagVisual {
        switch kind {
        case .account:
            EntryContextTagVisual(
                title: sourceWallet?.account?.name ?? "银行卡",
                isSelected: sourceWallet != nil
            )
        case .aa:
            EntryContextTagVisual(
                title: aaTitle(state: state, sourceWallet: sourceWallet),
                isSelected: state.aaSplitDraft != nil
            )
        case .splitPayment:
            EntryContextTagVisual(
                title: splitPaymentTitle(state: state, wallets: wallets),
                isSelected: state.usesSplitPayment
            )
        case .discount:
            EntryContextTagVisual(
                title: discountTitle(state: state, sourceWallet: sourceWallet),
                isSelected: DecimalParser.parse(state.discountAmountText).map { $0 > 0 } == true
            )
        case .fee, .foreignExpense:
            EntryContextTagVisual(title: kind.rawValue, isSelected: false)
        }
    }

    private static func aaTitle(
        state: TransactionFormState,
        sourceWallet: CurrencyWallet?
    ) -> String {
        guard let draft = state.aaSplitDraft else { return "AA" }
        let amount = MoneyFormatter.plain(
            draft.othersOwedAmount,
            currencyCode: sourceWallet?.currencyCode ?? "CNY"
        )
        return "AA ¥\(amount)"
    }

    private static func discountTitle(
        state: TransactionFormState,
        sourceWallet: CurrencyWallet?
    ) -> String {
        guard let amount = DecimalParser.parse(state.discountAmountText),
              amount > 0 else {
            return "优惠"
        }
        let formattedAmount = MoneyFormatter.plain(
            amount,
            currencyCode: sourceWallet?.currencyCode ?? "CNY"
        )
        return "优惠 ¥\(formattedAmount)"
    }

    private static func splitPaymentTitle(
        state: TransactionFormState,
        wallets: [CurrencyWallet]
    ) -> String {
        guard state.usesSplitPayment else { return "组合支付" }
        let names = state.paymentParts.compactMap { part in
            wallets.first(where: { $0.id == part.walletID })?.account?.name
        }
        let uniqueNames = Array(NSOrderedSet(array: names)).compactMap { $0 as? String }
        return uniqueNames.isEmpty ? "组合支付" : uniqueNames.joined(separator: " + ")
    }
}

struct EntryContextTagLabel: View {
    let visual: EntryContextTagVisual

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(
                    visual.isSelected
                        ? LedgerPalette.accent
                        : Color.secondary.opacity(0.7),
                    lineWidth: 1.4
                )
                if visual.isSelected {
                    Circle().fill(LedgerPalette.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)

            Text(visual.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(visual.isSelected ? LedgerPalette.accent : .primary)
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .frame(height: 27)
        .background(Color.primary.opacity(0.055), in: EntryContextTagShape())
        .overlay {
            EntryContextTagShape().stroke(
                visual.isSelected
                    ? LedgerPalette.accent.opacity(0.55)
                    : Color.primary.opacity(0.10),
                lineWidth: 0.8
            )
        }
        .contentShape(EntryContextTagShape())
    }
}

struct EntryContextControls: View {
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let wallets: [CurrencyWallet]
    let validation: EntryValidationState
    let selectAccount: () -> Void
    let editSplitPayment: () -> Void
    let editAA: () -> Void
    let editDiscount: () -> Void
    let editForeignCurrency: () -> Void
    let hiddenKind: EntryContextOverlayKind?
    let hiddenKindOpacity: Double

    var body: some View {
        VStack(spacing: 5) {
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    tag(
                        kind: .account,
                        visual: contextVisual(.account),
                        action: selectAccount
                    )
                    if state.kind == .expense {
                        tag(
                            visual: EntryContextTagVisual(
                                title: state.reimbursementStatus == .pending ? "待报销" : "报销",
                                isSelected: state.reimbursementStatus == .pending
                            )
                        ) {
                            state.reimbursementStatus = state.reimbursementStatus == .pending ? .none : .pending
                        }
                        tag(
                            kind: .aa,
                            visual: contextVisual(.aa),
                            action: editAA
                        )
                        if sourceWallet?.account?.type == .creditCard {
                            tag(
                                visual: EntryContextTagVisual(
                                    title: foreignCurrencyTitle,
                                    isSelected: state.foreignSettlementMode != nil
                                ),
                                action: editForeignCurrency
                            )
                        }
                    }
                    if state.kind == .expense || state.kind == .income {
                        tag(
                            kind: .splitPayment,
                            visual: contextVisual(.splitPayment),
                            action: editSplitPayment
                        )
                        tag(
                            kind: .discount,
                            visual: contextVisual(.discount),
                            action: editDiscount
                        )
                    }
                    if state.kind == .income {
                        tag(
                            visual: EntryContextTagVisual(
                                title: "不计收",
                                isSelected: state.excludesFromMonthlyIncome
                            )
                        ) {
                            state.excludesFromMonthlyIncome.toggle()
                        }
                    }
                    if state.kind == .expense {
                        tag(
                            visual: EntryContextTagVisual(
                                title: "不计支出",
                                isSelected: state.excludesFromMonthlyExpense
                            )
                        ) {
                            state.excludesFromMonthlyExpense.toggle()
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            EntryInlineValidation(message: validation[.sourceWallet])
        }
    }

    private func tag(
        kind: EntryContextOverlayKind? = nil,
        visual: EntryContextTagVisual,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            EntryContextTagLabel(visual: visual)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityLabel(visual.title)
        .accessibilityIdentifier(
            kind.map { "entry-context-tag-\($0.rawValue)" }
                ?? "entry-context-tag-secondary"
        )
        .opacity(kind != nil && hiddenKind == kind ? hiddenKindOpacity : 1)
        .background {
            if let kind {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: EntryContextTagFramePreferenceKey.self,
                        value: [
                            kind: proxy.frame(in: .named(EntryContextCoordinateSpace.name))
                        ]
                    )
                }
            }
        }
    }

    private func contextVisual(
        _ kind: EntryContextOverlayKind
    ) -> EntryContextTagVisual {
        EntryContextTagVisual.make(
            kind: kind,
            state: state,
            sourceWallet: sourceWallet,
            wallets: wallets
        )
    }

    private var foreignCurrencyTitle: String {
        let code = state.foreignOriginalCurrencyCode ?? sourceWallet?.currencyCode ?? "币种"
        guard let mode = state.foreignSettlementMode else { return code }
        return "\(code) · \(mode.title)"
    }
}

struct EntryContextTagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = min(9, rect.width * 0.15)
        let radius: CGFloat = 8
        var path = Path()
        path.move(to: CGPoint(x: tip, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: tip, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// A lightweight in-place editor for the context tags. It keeps users on the
/// entry screen and uses the app keypad for amount entry rather than invoking
/// the system keyboard.
struct LegacyEntryContextOverlay: View {
    let kind: EntryContextOverlayKind
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let currencyCode: String
    let dismiss: () -> Void

    @State private var activePaymentPart = 0
    @State private var aaPeople = 2
    @State private var keypadID = UUID()

    private var title: String {
        switch kind {
        case .account: "选择账户"
        case .aa: "AA 分摊"
        case .splitPayment: "组合支付"
        case .discount: "优惠"
        case .fee: "手续费"
        case .foreignExpense: "信用卡外币消费"
        }
    }

    private var amountBinding: Binding<String> {
        switch kind {
        case .discount:
            $state.discountAmountText
        case .fee:
            $state.feeText
        case .splitPayment:
            Binding(
                get: { state.paymentParts.indices.contains(activePaymentPart) ? state.paymentParts[activePaymentPart].amountText : "" },
                set: { if state.paymentParts.indices.contains(activePaymentPart) { state.paymentParts[activePaymentPart].amountText = $0 } }
            )
        default:
            .constant("")
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(spacing: 12) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(LedgerGlassPressStyle())
                }

                content

                if kind == .discount || kind == .fee || kind == .splitPayment {
                    EntryGlassKeypad(
                        amountText: amountBinding,
                        currencyCode: keypadCurrencyCode,
                        resetID: keypadID,
                        inputMode: .amount,
                        showsNextEntry: false,
                        isSaving: false,
                        canComplete: true,
                        nextEntry: {},
                        complete: commitAndDismiss
                    )
                } else {
                    Button("完成", action: commitAndDismiss)
                        .buttonStyle(.borderedProminent)
                        .tint(LedgerPalette.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(16)
            .frame(maxWidth: 480)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 0.8) }
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
        }
        .onAppear {
            aaPeople = (state.aaSplitDraft?.otherPeopleCount ?? 1) + 1
            if kind == .splitPayment, !state.usesSplitPayment {
                state.setSplitPaymentEnabled(true, wallets: wallets)
            }
            if kind == .fee {
                state.includesFee = true
            }
            if kind == .foreignExpense {
                initializeForeignExpense()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .account:
            accountOptions
        case .aa:
            aaOptions
        case .splitPayment:
            splitPaymentOptions
        case .discount:
            movementAmountOptions(
                title: "优惠金额",
                accountTitle: "优惠进入账户",
                walletID: $state.discountWalletID
            )
        case .fee:
            movementAmountOptions(
                title: "手续费金额",
                accountTitle: "手续费扣款账户",
                walletID: $state.feeWalletID
            )
        case .foreignExpense:
            foreignExpenseOptions
        }
    }

    private func movementAmountOptions(
        title: String,
        accountTitle: String,
        walletID: Binding<UUID?>
    ) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(amountBinding.wrappedValue.isEmpty ? "0" : amountBinding.wrappedValue)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LedgerPalette.accent)
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if state.kind == .transfer || kind == .fee {
                HStack {
                    Text(accountTitle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Menu {
                        ForEach(wallets) { wallet in
                            Button(walletDisplayName(wallet)) {
                                walletID.wrappedValue = wallet.id
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(walletDisplayName(wallets.first { $0.id == walletID.wrappedValue }))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var foreignExpenseOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("消费币种")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(foreignExpenseWallets) { wallet in
                        Button {
                            selectForeignExpenseWallet(wallet)
                        } label: {
                            Text(wallet.currencyCode)
                                .font(.subheadline.weight(.semibold).monospaced())
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(
                                    state.foreignOriginalCurrencyCode == wallet.currencyCode
                                        ? LedgerPalette.accent.opacity(0.14)
                                        : Color.primary.opacity(0.05),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if isSelectedForeignCurrency {
                Picker("结算方式", selection: Binding(
                    get: { state.foreignSettlementMode ?? defaultForeignMode },
                    set: {
                        state.foreignSettlementMode = $0
                        if $0 == .repayment { state.settledAmountText = "" }
                    }
                )) {
                    ForEach(ForeignCurrencySettlementMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(state.foreignSettlementMode == .instant
                    ? "消费金额按外币填写；结算金额可在金额区域切换输入，系统自动倒推实际汇率。"
                    : "先形成该外币欠款，之后在转账页面选择该币种还款。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("当前币种与信用卡默认结算币种一致。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var accountOptions: some View {
        ScrollView {
            VStack(spacing: 8) {
                accountRow(name: "暂时不记", wallet: nil)
                ForEach(wallets) { wallet in
                    accountRow(name: wallet.account?.name ?? wallet.currencyCode, wallet: wallet)
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private func accountRow(name: String, wallet: CurrencyWallet?) -> some View {
        Button {
            state.sourceWalletID = wallet?.id
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: wallet?.account?.type.symbolName ?? "circle")
                    .foregroundStyle(LedgerPalette.accent)
                    .frame(width: 28)
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                if state.sourceWalletID == wallet?.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LedgerPalette.accent)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
    }

    private var aaOptions: some View {
        VStack(spacing: 12) {
            HStack {
                Text("总人数（含自己）").font(.subheadline.weight(.semibold))
                Spacer()
                Stepper("\(aaPeople) 人", value: $aaPeople, in: 2...20)
                    .fixedSize()
            }
            .padding(14)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            let total = DecimalParser.parse(state.amountText) ?? 0
            let owed = total * Decimal(aaPeople - 1) / Decimal(aaPeople)
            HStack {
                Text("其他人合计应还").foregroundStyle(.secondary)
                Spacer()
                Text(MoneyFormatter.string(owed, currencyCode: currencyCode)).font(.headline.monospacedDigit())
            }
        }
    }

    private var splitPaymentOptions: some View {
        VStack(spacing: 8) {
            ForEach(Array(state.paymentParts.indices), id: \.self) { index in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(wallets) { wallet in
                            Button(wallet.account?.name ?? wallet.currencyCode) {
                                state.paymentParts[index].walletID = wallet.id
                            }
                        }
                    } label: {
                        Text(walletName(for: state.paymentParts[index].walletID))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        activePaymentPart = index
                        keypadID = UUID()
                    } label: {
                        Text(state.paymentParts[index].amountText.isEmpty ? "输入金额" : state.paymentParts[index].amountText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(activePaymentPart == index ? LedgerPalette.accent : .primary)
                            .frame(width: 92, alignment: .trailing)
                    }
                }
                .padding(10)
                .background(activePaymentPart == index ? LedgerPalette.accent.opacity(0.08) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Button { state.paymentParts.append(PaymentPartFormState(walletID: nil)) } label: {
                Label("添加账户", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func walletName(for id: UUID?) -> String {
        wallets.first(where: { $0.id == id })?.account?.name ?? "选择账户"
    }

    private func commitAndDismiss() {
        if kind == .aa {
            let total = DecimalParser.parse(state.amountText) ?? 0
            let owed = total * Decimal(aaPeople - 1) / Decimal(aaPeople)
            state.aaSplitDraft = AASplitDraft(
                otherPeopleCount: aaPeople - 1,
                calculationMode: .equal,
                othersOwedAmount: owed,
                basedOnAmount: total
            )
        }
        if kind == .fee {
            let hasFee = DecimalParser.parse(state.feeText).map { $0 > 0 } == true
            state.includesFee = hasFee
            if !hasFee { state.feeWalletID = nil }
        }
        if kind == .discount, state.kind == .transfer,
           DecimalParser.parse(state.discountAmountText).map({ $0 > 0 }) != true {
            state.discountWalletID = nil
        }
        dismiss()
    }

    private var selectedSourceWallet: CurrencyWallet? {
        wallets.first { $0.id == state.sourceWalletID }
    }

    private var keypadCurrencyCode: String {
        switch kind {
        case .fee:
            return wallets.first { $0.id == state.feeWalletID }?.currencyCode ?? currencyCode
        case .discount where state.kind == .transfer:
            return wallets.first { $0.id == state.discountWalletID }?.currencyCode ?? currencyCode
        default:
            return currencyCode
        }
    }

    private var foreignExpenseWallets: [CurrencyWallet] {
        guard let accountID = selectedSourceWallet?.account?.id else { return [] }
        return wallets.filter { $0.account?.id == accountID }
    }

    private var settlementCurrencyCode: String {
        selectedSourceWallet?.account?.defaultSettlementCurrencyCode
            ?? selectedSourceWallet?.currencyCode
            ?? SupportedCurrency.CNY.rawValue
    }

    private var isSelectedForeignCurrency: Bool {
        guard let selectedCode = state.foreignOriginalCurrencyCode else { return false }
        return selectedCode != settlementCurrencyCode
    }

    private var defaultForeignMode: ForeignCurrencySettlementMode {
        selectedSourceWallet?.account?.defaultForeignCurrencySettlementMode ?? .instant
    }

    private func initializeForeignExpense() {
        guard let selectedSourceWallet else { return }
        if let existingCode = state.foreignOriginalCurrencyCode,
           let originalWallet = foreignExpenseWallets.first(where: {
               $0.currencyCode == existingCode
           }) {
            state.sourceWalletID = originalWallet.id
            if existingCode == settlementCurrencyCode {
                state.foreignSettlementMode = nil
                state.settledAmountText = ""
            } else if state.foreignSettlementMode == nil {
                state.foreignSettlementMode = defaultForeignMode
            }
            return
        }
        state.foreignOriginalCurrencyCode = selectedSourceWallet.currencyCode
        if selectedSourceWallet.currencyCode == settlementCurrencyCode {
            state.foreignSettlementMode = nil
            state.settledAmountText = ""
        } else if state.foreignSettlementMode == nil {
            state.foreignSettlementMode = defaultForeignMode
        }
    }

    private func selectForeignExpenseWallet(_ wallet: CurrencyWallet) {
        state.sourceWalletID = wallet.id
        state.foreignOriginalCurrencyCode = wallet.currencyCode
        let settlementCode = wallet.account?.defaultSettlementCurrencyCode ?? wallet.currencyCode
        if wallet.currencyCode == settlementCode {
            state.foreignSettlementMode = nil
            state.settledAmountText = ""
        } else {
            state.foreignSettlementMode = wallet.account?.defaultForeignCurrencySettlementMode ?? .instant
        }
    }

    private func walletDisplayName(_ wallet: CurrencyWallet?) -> String {
        guard let wallet else { return "请选择" }
        return "\(wallet.account?.name ?? AppLocalization.string("未知账户")) · \(wallet.currencyCode)"
    }
}
