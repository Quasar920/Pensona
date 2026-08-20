import SwiftUI

struct EntryContextOverlayPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let kind: EntryContextOverlayKind
    @Binding var draft: EntryContextDraft
    @Binding var activePaymentPart: Int
    let mainAmountText: String
    let wallets: [CurrencyWallet]
    let currencyCode: String
    let feeTemplates: [FeeRateTemplate]
    let maximumHeight: CGFloat
    let isAAPeopleInputActive: Bool
    let cancel: () -> Void
    let commit: () -> Void
    let paymentPartChanged: () -> Void
    let aaPeopleInputSelected: () -> Void
    let feeInputChanged: () -> Void
    let feeTemplateSelected: (FeeRateTemplate) -> Void
    let manageFeeTemplates: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool

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

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .accessibilityFocused($titleFocused)
                Spacer()
            }

            content

            EntryContextPanelActionRow(
                canConfirm: canConfirm,
                confirmTitle: kind == .fee ? "完成" : "确认",
                cancel: cancel,
                confirm: commit
            )
        }
        .padding(16)
        .background(panelSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.8)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: EntryContextPanelFramePreferenceKey.self,
                    value: proxy.frame(in: .named(EntryContextCoordinateSpace.name))
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entry-context-panel-\(kind.rawValue)")
        .onAppear {
            Task { @MainActor in
                titleFocused = true
            }
        }
    }

    private var panelSurface: Color {
        EntryFloatingCardAppearance.surface(for: colorScheme)
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
            discountOptions
        case .fee:
            feeOptions
        case .foreignExpense:
            EmptyView()
        }
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
        .frame(height: accountContentHeight)
        .scrollIndicators(.hidden)
    }

    private var accountContentHeight: CGFloat {
        min(
            max(120, CGFloat(wallets.count + 1) * 56),
            max(120, maximumHeight - 128)
        )
    }

    private func accountRow(name: String, wallet: CurrencyWallet?) -> some View {
        Button {
            draft.selectedWalletID = wallet?.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: wallet?.account?.type.symbolName ?? "circle")
                    .foregroundStyle(LedgerPalette.accent)
                    .frame(width: 28)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if draft.selectedWalletID == wallet?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LedgerPalette.accent)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
    }

    private var aaOptions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("总人数（含自己）")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Button(action: aaPeopleInputSelected) {
                    Text(aaPeopleDisplayText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            draft.hasValidAAPeople ? Color.primary : LedgerPalette.ink
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minWidth: 52, minHeight: 44)
                        .background(
                            Color.primary.opacity(
                                isAAPeopleInputActive ? 0.075 : 0.055
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        draft.hasValidAAPeople
                                        ? Color.primary.opacity(
                                            isAAPeopleInputActive ? 0.18 : 0.10
                                        )
                                        : LedgerPalette.ink.opacity(0.7),
                                        lineWidth: 1
                                    )
                        }
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("输入总人数")
                .accessibilityValue(aaPeopleDisplayText)
                .accessibilityHint("人数必须为不小于 2 的整数")

                HStack(spacing: 0) {
                    aaPeopleStepButton(systemName: "minus", delta: -1)
                    Divider()
                        .frame(height: 22)
                    aaPeopleStepButton(systemName: "plus", delta: 1)
                }
                .frame(height: 44)
                .background(Color.primary.opacity(0.09), in: Capsule())
            }
            .padding(14)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("其他每人应还")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(MoneyFormatter.string(aaPerPersonAmount, currencyCode: currencyCode))
                    .font(.headline.monospacedDigit())
            }

        }
    }

    private var aaPeopleDisplayText: String {
        draft.aaPeopleText.isEmpty ? "— 人" : "\(draft.aaPeopleText) 人"
    }

    private func aaPeopleStepButton(systemName: String, delta: Int) -> some View {
        Button {
            let typedValue = Int(draft.aaPeopleText) ?? draft.aaPeople
            if delta < 0 {
                draft.setAAPeople(max(2, typedValue - 1))
            } else if typedValue < Int.max {
                draft.setAAPeople(max(2, typedValue + 1))
            }
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .disabled(delta < 0 && (Int(draft.aaPeopleText) ?? draft.aaPeople) <= 2)
        .accessibilityLabel(delta < 0 ? "减少人数" : "增加人数")
    }

    private var aaPerPersonAmount: Decimal {
        let total = DecimalParser.parse(mainAmountText) ?? 0
        return total / Decimal(draft.aaPeople)
    }

    private var splitPaymentOptions: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(draft.paymentParts.indices), id: \.self) { index in
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(wallets) { wallet in
                                Button(wallet.account?.name ?? wallet.currencyCode) {
                                    draft.paymentParts[index].walletID = wallet.id
                                }
                            }
                        } label: {
                            Text(walletName(for: draft.paymentParts[index].walletID))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            activePaymentPart = index
                            paymentPartChanged()
                        } label: {
                            EntryContextAmountInputLabel(
                                text: draft.paymentParts[index].amountText,
                                isActive: activePaymentPart == index
                            )
                        }
                        .accessibilityIdentifier("entry-context-split-amount-\(index)")
                        .accessibilityLabel("输入第 \(index + 1) 个账户金额")
                        .accessibilityValue(draft.paymentParts[index].amountText)
                        .accessibilityHint(activePaymentPart == index ? "正在输入金额" : "点按后开始输入金额")
                    }
                    .padding(10)
                    .background(
                        activePaymentPart == index
                            ? LedgerPalette.accent.opacity(0.08)
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                Button {
                    draft.paymentParts.append(PaymentPartFormState(walletID: nil))
                } label: {
                    Label("添加账户", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(height: splitPaymentContentHeight)
        .scrollIndicators(.hidden)
    }

    private var splitPaymentContentHeight: CGFloat {
        min(
            max(120, CGFloat(draft.paymentParts.count) * 58 + 44),
            max(120, maximumHeight - 128)
        )
    }

    private var discountOptions: some View {
        VStack(spacing: 10) {
            HStack {
                Text("优惠金额")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(draft.discountAmountText.isEmpty ? "0" : draft.discountAmountText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LedgerPalette.accent)
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if draft.transactionKind == .transfer {
                walletSelectionRow(
                    title: "优惠进入账户",
                    selection: $draft.discountWalletID,
                    identifier: "entry-discount-wallet"
                )
            }
        }
    }

    private var feeOptions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    draft.feeInputMode = draft.feeInputMode == .percentage
                        ? .fixedAmount
                        : .percentage
                    draft.feeInputText = ""
                    draft.feeTemplateName = nil
                    feeInputChanged()
                } label: {
                    Text(draft.feeInputMode.toggleTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 52)
                        .frame(minHeight: 44)
                        .background(LedgerPalette.selectionFill, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("切换手续费输入方式")

                HStack {
                    Text(draft.feeInputMode.inputTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    EntryContextAmountInputLabel(
                        text: draft.feeInputText,
                        isActive: true
                    )
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            }

            if draft.transactionKind == .transfer || draft.transactionKind == .exchange {
                walletSelectionRow(
                    title: "手续费扣款账户",
                    selection: $draft.feeWalletID,
                    identifier: "entry-fee-wallet",
                    selectionChanged: { draft.feeCurrencyCode = $0.currencyCode }
                )
            }

            VStack(spacing: 8) {
                ForEach(feeTemplates) { template in
                    Button {
                        feeTemplateSelected(template)
                    } label: {
                        HStack {
                            Text(template.name)
                            Spacer()
                            Text("\(NSDecimalNumber(decimal: template.percentage).stringValue)%")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 42)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(LedgerGlassPressStyle())
                    .accessibilityIdentifier("entry-fee-template-\(template.id.uuidString)")
                }

                Button(action: manageFeeTemplates) {
                    Label("管理手续费模板", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(LedgerGlassPressStyle())
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var canConfirm: Bool {
        switch kind {
        case .aa: draft.hasValidAAPeople
        case .discount: draft.hasValidDiscountSelection
        case .fee: draft.hasValidFeeSelection
        default: true
        }
    }

    private func walletSelectionRow(
        title: String,
        selection: Binding<UUID?>,
        identifier: String,
        selectionChanged: ((CurrencyWallet) -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Menu {
                ForEach(wallets) { wallet in
                    Button(walletDisplayName(wallet)) {
                        selection.wrappedValue = wallet.id
                        selectionChanged?(wallet)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(walletDisplayName(wallets.first { $0.id == selection.wrappedValue }))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(identifier)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func walletDisplayName(_ wallet: CurrencyWallet?) -> String {
        guard let wallet else { return "选择账户" }
        return "\(wallet.account?.name ?? "未知账户") · \(wallet.currencyCode)"
    }

    private func walletName(for id: UUID?) -> String {
        wallets.first(where: { $0.id == id })?.account?.name ?? "选择账户"
    }
}

/// A render-only counterpart for the Metal transition.
///
/// Native controls and system materials cannot be captured reliably inside a
/// SwiftUI layer shader on device. This view mirrors the complete panel using
/// renderable SwiftUI primitives. The whole result is composited once and
/// sampled by Metal, so its shell and content deform as a single surface.
struct EntryContextTransitionPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let kind: EntryContextOverlayKind
    let draft: EntryContextDraft
    let activePaymentPart: Int
    let mainAmountText: String
    let wallets: [CurrencyWallet]
    let currencyCode: String
    let feeTemplates: [FeeRateTemplate]
    let targetHeight: CGFloat

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

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }

            content
            Spacer(minLength: 0)
            EntryContextPanelActionRow(
                canConfirm: kind == .aa ? draft.hasValidAAPeople : (kind == .fee ? draft.hasValidFeeInput : true),
                confirmTitle: kind == .fee ? "完成" : "确认",
                cancel: {},
                confirm: {}
            )
        }
        .padding(16)
        .frame(height: targetHeight, alignment: .top)
        .background(panelSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityHidden(true)
    }

    private var panelSurface: Color {
        EntryFloatingCardAppearance.surface(for: colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .account:
            VStack(spacing: 8) {
                transitionAccountRow(name: "暂时不记", wallet: nil)
                ForEach(Array(wallets.prefix(6))) { wallet in
                    transitionAccountRow(
                        name: wallet.account?.name ?? wallet.currencyCode,
                        wallet: wallet
                    )
                }
            }
        case .aa:
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("总人数（含自己）")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(
                        draft.aaPeopleText.isEmpty
                            ? "— 人"
                            : "\(draft.aaPeopleText) 人"
                    )
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(
                        draft.hasValidAAPeople ? Color.primary : LedgerPalette.ink
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(minWidth: 52, minHeight: 44)
                    .background(
                        Color.primary.opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                draft.hasValidAAPeople
                                    ? Color.primary.opacity(0.18)
                                    : LedgerPalette.ink.opacity(0.7),
                                lineWidth: 1
                            )
                    }

                    HStack(spacing: 0) {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                        Divider().frame(height: 22)
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(height: 44)
                    .background(Color.primary.opacity(0.09), in: Capsule())
                }
                .padding(14)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Text("其他每人应还")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(MoneyFormatter.string(aaPerPersonAmount, currencyCode: currencyCode))
                        .font(.headline.monospacedDigit())
                }

            }
        case .splitPayment:
            VStack(spacing: 8) {
                ForEach(Array(draft.paymentParts.indices), id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(walletName(for: draft.paymentParts[index].walletID))
                            .lineLimit(1)
                            .foregroundStyle(LedgerPalette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.primary.opacity(0.07), in: Capsule())

                        EntryContextAmountInputLabel(
                            text: draft.paymentParts[index].amountText,
                            isActive: activePaymentPart == index
                        )
                    }
                    .padding(10)
                    .background(
                        activePaymentPart == index
                            ? LedgerPalette.accent.opacity(0.08)
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                Label("添加账户", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LedgerPalette.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        case .discount:
            HStack {
                Text("优惠金额")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(draft.discountAmountText.isEmpty ? "0" : draft.discountAmountText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LedgerPalette.accent)
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .fee:
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text(draft.feeInputMode.toggleTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 52, height: 44)
                        .background(LedgerPalette.selectionFill, in: RoundedRectangle(cornerRadius: 12))
                    EntryContextAmountInputLabel(text: draft.feeInputText, isActive: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                }
                ForEach(feeTemplates.prefix(3)) { template in
                    HStack {
                        Text(template.name)
                        Spacer()
                        Text("\(NSDecimalNumber(decimal: template.percentage).stringValue)%")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                }
                Label("管理手续费模板", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            }
        case .foreignExpense:
            EmptyView()
        }
    }

    private func transitionAccountRow(name: String, wallet: CurrencyWallet?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: wallet?.account?.type.symbolName ?? "circle")
                .foregroundStyle(LedgerPalette.accent)
                .frame(width: 28)
            Text(name)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if draft.selectedWalletID == wallet?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LedgerPalette.accent)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var aaPerPersonAmount: Decimal {
        let total = DecimalParser.parse(mainAmountText) ?? 0
        return total / Decimal(draft.aaPeople)
    }

    private func walletName(for id: UUID?) -> String {
        wallets.first(where: { $0.id == id })?.account?.name ?? "选择账户"
    }
}

struct EntryContextPanelActionRow: View {
    let canConfirm: Bool
    var confirmTitle = "确认"
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("取消", action: cancel)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(confirmTitle, action: confirm)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(LedgerPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!canConfirm)
                .opacity(canConfirm ? 1 : 0.45)
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(LedgerGlassPressStyle())
        .accessibilityElement(children: .contain)
    }
}

private struct EntryContextAmountInputLabel: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(text.isEmpty ? "输入金额" : text)
            if isActive {
                EntryContextInputCaret()
                    .accessibilityIdentifier("entry-context-input-caret")
            }
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(isActive ? LedgerPalette.accent : .primary)
        .frame(width: 102, alignment: .trailing)
    }
}

private struct EntryContextInputCaret: View {
    @State private var isVisible = true

    var body: some View {
        Rectangle()
            .fill(LedgerPalette.accent)
            .frame(width: 2, height: 20)
            .opacity(isVisible ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}
